// Read-only inspection of an already-running clone; never suspends, writes,
// injects, invokes Qt, or sends messages. task_for_pid may be refused by macOS.
#include <mach/mach.h>
#include <mach/mach_vm.h>
#include <mach-o/dyld_images.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static int read_at(mach_port_t task, uint64_t addr, void *dst, size_t size) {
    mach_vm_size_t got = 0;
    return mach_vm_read_overwrite(task, addr, size, (mach_vm_address_t)dst, &got)
        == KERN_SUCCESS && got == size;
}

// Qt QObjectData starts with its vptr and q_ptr. A backlink is stronger evidence
// than a vtable hit, but does not prove ownership, lifetime, or current recipient.
static int qobject_backlink(mach_port_t task, uint64_t addr) {
    uint64_t object[2], data[2];
    return read_at(task, addr, object, sizeof object) && object[1]
        && read_at(task, object[1], data, sizeof data) && data[1] == addr;
}

static int type_name(mach_port_t task, uint64_t object, char name[160]) {
    uint64_t vptr = 0, ti = 0, chars = 0;
    if (!read_at(task, object, &vptr, 8) || vptr < 16
        || !read_at(task, vptr - 8, &ti, 8) || !ti
        || !read_at(task, ti + 8, &chars, 8) || !chars) return 0;
    // libc++'s non-unique type_info name reserves the high bit as a tag.
    chars &= ~(1ULL << 63);
    for (size_t i = 0; i < 160; i++) {
        if (!read_at(task, chars + i, name + i, 1)) return 0;
        if (!name[i]) return i > 0;
        if ((unsigned char)name[i] < 32 || (unsigned char)name[i] > 126
            || name[i] == '"' || name[i] == '\\') return 0;
    }
    return 0;
}

static void print_members(mach_port_t task, uint64_t parent, int depth) {
    uint64_t words[192];
    if (!read_at(task, parent, words, sizeof words)) { printf("[]"); return; }
    int first = 1;
    printf("[");
    for (size_t i = 1; i < sizeof words / sizeof words[0]; i++) {
        char name[160] = "";
        if (!qobject_backlink(task, words[i])) continue;
        if (!type_name(task, words[i], name)) name[0] = 0;
        uint64_t vptr = 0;
        read_at(task, words[i], &vptr, sizeof vptr);
        printf("%s{\"offset\":\"0x%zx\",\"address\":\"0x%llx\",\"vptr\":\"0x%llx\",\"type\":\"%s\",\"members\":",
            first ? "" : ",", i * 8, (unsigned long long)words[i],
            (unsigned long long)vptr, name);
        if (depth == 0 && strstr(name, "ChatInputField"))
            print_members(task, words[i], depth + 1);
        else printf("[]");
        printf("}");
        first = 0;
    }
    printf("]");
}

static uint64_t image_base(mach_port_t task) {
    struct task_dyld_info info;
    mach_msg_type_number_t count = TASK_DYLD_INFO_COUNT;
    if (task_info(task, TASK_DYLD_INFO, (task_info_t)&info, &count) != KERN_SUCCESS)
        return 0;
    struct dyld_all_image_infos all;
    if (!read_at(task, info.all_image_info_addr, &all, sizeof all)
        || all.infoArrayCount > 8192) return 0;
    for (uint32_t i = 0; i < all.infoArrayCount; i++) {
        struct dyld_image_info image;
        if (!read_at(task, (uint64_t)all.infoArray + i * sizeof image, &image, sizeof image))
            return 0;
        char name[1024] = {0};
        // Read one byte at a time: a path may end at a region boundary.
        for (size_t j = 0; j + 1 < sizeof name; j++) {
            if (!read_at(task, (uint64_t)image.imageFilePath + j, name + j, 1)) break;
            if (!name[j]) break;
        }
        if (strstr(name, "/Contents/Resources/wechat.dylib"))
            return (uint64_t)image.imageLoadAddress;
    }
    return 0;
}

static double seconds(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec + ts.tv_nsec / 1e9;
}

static int self_test(void) {
    uint64_t data[2] = {0}, object[2] = {0, (uint64_t)data};
    data[1] = (uint64_t)object;
    if (!qobject_backlink(mach_task_self(), (uint64_t)object)) return 1;
    data[1] = 1;
    if (qobject_backlink(mach_task_self(), (uint64_t)object)) return 1;
    if (qobject_backlink(mach_task_self(), 1)) return 1;
    puts("probe self-test: 3/3 passed (valid backlink, false hit, unmapped)");
    return 0;
}

int main(int argc, char **argv) {
    if (argc == 2 && !strcmp(argv[1], "--self-test")) return self_test();
    if (argc != 4) {
        fprintf(stderr, "usage: wechat_probe PID INPUT_VTABLE_RVA EDITOR_VTABLE_RVA\n");
        return 2;
    }
    char *end = NULL;
    long pid = strtol(argv[1], &end, 10);
    if (*end || pid <= 0) return 2;
    uint64_t rv[2];
    for (int i = 0; i < 2; i++) {
        rv[i] = strtoull(argv[i + 2], &end, 0);
        if (*end || !rv[i]) return 2;
    }
    mach_port_t task = MACH_PORT_NULL;
    kern_return_t kr = task_for_pid(mach_task_self(), (int)pid, &task);
    if (kr != KERN_SUCCESS) {
        fprintf(stderr, "task_for_pid refused: %s; no state changed\n", mach_error_string(kr));
        return 3;
    }
    uint64_t base = image_base(task);
    if (!base) {
        fprintf(stderr, "core Resources/wechat.dylib image not found\n");
        mach_port_deallocate(mach_task_self(), task);
        return 4;
    }
    printf("{\"pid\":%ld,\"base\":\"0x%llx\",\"vtables\":[", pid, (unsigned long long)base);
    for (int k = 0; k < 2; k++) {
        uint64_t slots[4] = {0};
        int ok = read_at(task, base + rv[k] - 16, slots, sizeof slots);
        printf("%s{\"rva\":\"0x%llx\",\"readable\":%s,\"offset_to_top\":%lld,\"typeinfo\":\"0x%llx\"}",
            k ? "," : "", (unsigned long long)rv[k], ok ? "true" : "false",
            (long long)slots[0], (unsigned long long)slots[1]);
    }
    printf("],\"candidates\":[");
    unsigned char buf[65536];
    unsigned raw[2] = {0}, valid[2] = {0};
    uint64_t scanned = 0;
    mach_vm_address_t addr = 0;
    double started = seconds();
    int first = 1, capped = 0;
    for (;;) {
        if (seconds() - started > 15 || scanned >= (2ULL << 30)) { capped = 1; break; }
        mach_vm_size_t size = 0;
        vm_region_basic_info_data_64_t region;
        mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
        mach_port_t object = MACH_PORT_NULL;
        kr = mach_vm_region(task, &addr, &size, VM_REGION_BASIC_INFO_64,
                           (vm_region_info_t)&region, &count, &object);
        if (object != MACH_PORT_NULL) mach_port_deallocate(mach_task_self(), object);
        if (kr != KERN_SUCCESS || !size || addr + size < addr) break;
        if ((region.protection & (VM_PROT_READ | VM_PROT_WRITE)) == (VM_PROT_READ | VM_PROT_WRITE)
            && !(region.protection & VM_PROT_EXECUTE) && size <= (256ULL << 20)) {
            for (uint64_t p = addr; p < addr + size; p += sizeof buf) {
                if (seconds() - started > 15) { capped = 1; break; }
                size_t want = addr + size - p < sizeof buf ? addr + size - p : sizeof buf;
                scanned += want;
                if (!read_at(task, p, buf, want)) continue;
                for (size_t off = 0; off + 8 <= want; off += 8) {
                    uint64_t value;
                    memcpy(&value, buf + off, 8);
                    for (int k = 0; k < 2; k++) {
                        if (value != base + rv[k]) continue;
                        raw[k]++;
                        uint64_t candidate = p + off;
                        int good = qobject_backlink(task, candidate);
                        if (good) valid[k]++;
                        if (raw[k] <= 12) {
                            char name[160] = "";
                            if (good && !type_name(task, candidate, name)) name[0] = 0;
                            printf("%s{\"kind\":\"%s\",\"address\":\"0x%llx\",\"qobject_backlink\":%s,\"type\":\"%s\",\"members\":",
                                first ? "" : ",", k ? "editor" : "input",
                                (unsigned long long)candidate, good ? "true" : "false", name);
                            if (good && k == 0) print_members(task, candidate, 0); else printf("[]");
                            printf("}");
                            first = 0;
                        }
                    }
                }
            }
        }
        if (capped) break;
        addr += size;
    }
    printf("],\"raw_hits\":[%u,%u],\"backlinks\":[%u,%u],\"scanned_bytes\":%llu,\"bounded\":%s,\"elapsed_seconds\":%.3f}\n",
        raw[0], raw[1], valid[0], valid[1], (unsigned long long)scanned,
        capped ? "true" : "false", seconds() - started);
    mach_port_deallocate(mach_task_self(), task);
    return 0;
}
