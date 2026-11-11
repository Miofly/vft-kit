// Experimental in-process Qt bridge. New builds accept only the exact command
// "probe\n". Mutation remains disabled until QString factory/lifetime, recipient
// identity, draft preservation and submit verification are validated per build.
// Do not overwrite a dylib mapped by an already-logged-in clone or restart it
// merely to load this build. Use wechat_probe.c for live, external read-only work.
#include <dispatch/dispatch.h>
#include <mach/mach.h>
#include <mach/mach_vm.h>
#include <mach-o/dyld.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/un.h>
#include <unistd.h>
#include <errno.h>
#include <time.h>

typedef struct {
    uintptr_t input_vtable, editor_vtable;
    size_t editor_offset;
} probe_profile;

// No fallback RVAs: an absent or malformed profile cannot become an accidental
// call into another build. The caller supplies RVAs for the fingerprinted image.
static int parse_address(const char *text, uintptr_t *value) {
    if (!text || !*text || text[0] == '-' || text[0] == '+') return 0;
    char *end;
    errno = 0;
    unsigned long long n = strtoull(text, &end, 0);
    if (errno || *end || !n || n > UINTPTR_MAX) return 0;
    *value = (uintptr_t)n;
    return 1;
}

static int read_at(uintptr_t addr, void *dst, size_t size) {
    mach_vm_size_t got = 0;
    return mach_vm_read_overwrite(mach_task_self(), addr, size,
        (mach_vm_address_t)dst, &got) == KERN_SUCCESS && got == size;
}

// QObjectData::q_ptr must point back at the QObject. Readability alone is not
// sufficient. This is a preflight check, not proof of lifetime or recipient.
static int qobject_backlink(uintptr_t obj) {
    uintptr_t words[2], data[2];
    return read_at(obj, words, sizeof words) && words[1]
        && read_at(words[1], data, sizeof data) && data[1] == obj;
}

static int bound_editor(uintptr_t input, const probe_profile *profile, uintptr_t *editor) {
    uintptr_t vptr;
    return input && qobject_backlink(input)
        && read_at(input, &vptr, sizeof vptr) && vptr == profile->input_vtable
        && profile->editor_offset <= 4096 && profile->editor_offset % 8 == 0
        && read_at(input + profile->editor_offset, editor, sizeof *editor)
        && qobject_backlink(*editor)
        && read_at(*editor, &vptr, sizeof vptr) && vptr == profile->editor_vtable;
}

static uintptr_t core_base(void) {
    const char *suffix = "/Contents/Resources/wechat.dylib";
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *path = _dyld_get_image_name(i);
        if (!path) continue;
        size_t a = strlen(path), b = strlen(suffix);
        if (a >= b && !strcmp(path + a - b, suffix))
            return (uintptr_t)_dyld_get_image_header(i);
    }
    return 0; // Never pick the same-named Frameworks stub.
}

static double seconds(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec + ts.tv_nsec / 1e9;
}

typedef struct { uintptr_t input; unsigned matches; int bounded; } scan_result;
static scan_result find_inputs(uintptr_t vtable) {
    scan_result result = {0};
    unsigned char buf[65536];
    mach_vm_address_t addr = 0;
    uint64_t scanned = 0;
    double start = seconds();
    for (;;) {
        if (seconds() - start > 10 || scanned >= (2ULL << 30)) {
            result.bounded = 1; break;
        }
        mach_vm_size_t size = 0;
        vm_region_basic_info_data_64_t region;
        mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
        mach_port_t object = MACH_PORT_NULL;
        kern_return_t kr = mach_vm_region(mach_task_self(), &addr, &size,
            VM_REGION_BASIC_INFO_64, (vm_region_info_t)&region, &count, &object);
        if (object != MACH_PORT_NULL) mach_port_deallocate(mach_task_self(), object);
        if (kr != KERN_SUCCESS || !size || addr + size < addr) break;
        if ((region.protection & (VM_PROT_READ | VM_PROT_WRITE)) == (VM_PROT_READ | VM_PROT_WRITE)
            && !(region.protection & VM_PROT_EXECUTE) && size <= (256ULL << 20)) {
            for (uintptr_t p = addr; p < addr + size; p += sizeof buf) {
                if (seconds() - start > 10 || scanned >= (2ULL << 30)) {
                    result.bounded = 1; break;
                }
                size_t n = addr + size - p < sizeof buf ? addr + size - p : sizeof buf;
                scanned += n;
                if (!read_at(p, buf, n)) continue;
                for (size_t off = 0; off + 8 <= n; off += 8) {
                    uintptr_t value;
                    memcpy(&value, buf + off, sizeof value);
                    if (value != vtable || !qobject_backlink(p + off)) continue;
                    result.input = p + off;
                    result.matches++;
                }
            }
        }
        if (result.bounded) break;
        addr += size;
    }
    return result;
}

static int is_probe(const char *buf, size_t n) {
    return n == 6 && !memcmp(buf, "probe\n", 6);
}

typedef struct {
    uintptr_t input;
    probe_profile profile;
    uintptr_t editor;
    int valid, on_main;
} binding_request;

// Any future QWidget access belongs here, on the main queue, after rebinding
// and recipient/draft checks. No Qt method is invoked in this revision.
static void check_binding_on_main(void *context) {
    binding_request *request = context;
    request->on_main = pthread_main_np();
    request->valid = request->on_main
        && bound_editor(request->input, &request->profile, &request->editor);
}

static int self_test(void) {
    uintptr_t input[65] = {0}, editor[2] = {0}, input_data[2] = {0}, editor_data[2] = {0};
    input[0] = 0x1234; input[1] = (uintptr_t)input_data; input_data[1] = (uintptr_t)input;
    editor[0] = 0x5678; editor[1] = (uintptr_t)editor_data; editor_data[1] = (uintptr_t)editor;
    input[64] = (uintptr_t)editor;
    probe_profile profile = {0x1234, 0x5678, 0x200};
    uintptr_t found = 0, value = 0;
    unsigned tests = 0;
#define CHECK(condition) do { if (!(condition)) { fprintf(stderr, "failed: %s\n", #condition); return 1; } tests++; } while (0)
    CHECK(is_probe("probe\n", 6));
    CHECK(!is_probe("hello", 5));
    CHECK(!is_probe("send\n", 5));
    CHECK(!is_probe("probe\ntext", 10));
    CHECK(parse_address("0x200", &value) && value == 512);
    CHECK(!parse_address(NULL, &value));
    CHECK(!parse_address("0", &value));
    CHECK(!parse_address("-1", &value));
    CHECK(!parse_address("0x200junk", &value));
    CHECK(!parse_address("9999999999999999999999999999", &value));
    CHECK(bound_editor((uintptr_t)input, &profile, &found) && found == (uintptr_t)editor);
    input[64] = 1;
    CHECK(!bound_editor((uintptr_t)input, &profile, &found));
    input[64] = (uintptr_t)editor;
    editor_data[1] = 1;
    CHECK(!bound_editor((uintptr_t)input, &profile, &found));
    editor_data[1] = (uintptr_t)editor;
    profile.editor_offset = 8192;
    CHECK(!bound_editor((uintptr_t)input, &profile, &found));
    profile.editor_offset = 0x200;
    binding_request request = {(uintptr_t)input, profile, 0, 0, 0};
    check_binding_on_main(&request);
    CHECK(request.on_main && request.valid);
#undef CHECK
    printf("sender safety self-test: %u/%u passed; no WeChat accessed\n", tests, tests);
    return 0;
}

static int main_executable(void) {
    char path[4096];
    uint32_t size = sizeof path;
    const char *suffix = "/Contents/MacOS/WeChat";
    if (_NSGetExecutablePath(path, &size)) return 0;
    size_t a = strlen(path), b = strlen(suffix);
    return a >= b && !strcmp(path + a - b, suffix);
}

static void *serve(void *unused) {
    (void)unused;
    const char *socket_path = getenv("WXS_SOCKET");
    if (!socket_path || !*socket_path) { fprintf(stderr, "[wxs] WXS_SOCKET required; disabled\n"); return NULL; }
    struct sockaddr_un address = {0};
    address.sun_family = AF_UNIX;
    if (strlen(socket_path) >= sizeof address.sun_path) return NULL;
    strcpy(address.sun_path, socket_path);
    int server = socket(AF_UNIX, SOCK_STREAM, 0);
    if (server < 0) return NULL;
    // Never unlink an existing socket: it may belong to the logged-in old build.
    if (bind(server, (struct sockaddr *)&address, sizeof address) || chmod(socket_path, 0600)
        || listen(server, 4)) {
        fprintf(stderr, "[wxs] socket unavailable; no existing endpoint replaced\n");
        close(server); return NULL;
    }
    for (;;) {
        int client = accept(server, NULL, NULL);
        if (client < 0) { if (errno == EINTR) continue; break; }
        int no_sigpipe = 1;
        setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &no_sigpipe, sizeof no_sigpipe);
        struct timeval timeout = {2, 0};
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof timeout);
        char command[32] = {0};
        size_t used = 0;
        ssize_t n;
        do {
            n = read(client, command + used, sizeof command - used);
            if (n > 0) used += (size_t)n;
        } while (n > 0 && used < sizeof command);
        if (!is_probe(command, used)) {
            dprintf(client, "{\"status\":\"refused\",\"diagnostic\":\"probe_only_no_mutation\"}\n");
            close(client); continue;
        }
        uintptr_t input_rva, editor_rva, offset;
        uintptr_t base = core_base();
        if (!base || !parse_address(getenv("WXS_INPUT_VTABLE"), &input_rva)
            || !parse_address(getenv("WXS_EDITOR_VTABLE"), &editor_rva)
            || !parse_address(getenv("WXS_EDITOR_OFFSET"), &offset)
            || offset > 4096 || offset % 8 || input_rva > UINTPTR_MAX - base
            || editor_rva > UINTPTR_MAX - base) {
            dprintf(client, "{\"status\":\"not_ready\",\"diagnostic\":\"profile_missing_or_invalid\"}\n");
            close(client); continue;
        }
        scan_result result = find_inputs(base + input_rva);
        binding_request request = {result.input, {base + input_rva, base + editor_rva, offset}, 0, 0, 0};
        if (!result.bounded && result.matches == 1)
            dispatch_sync_f(dispatch_get_main_queue(), &request, check_binding_on_main);
        dprintf(client, "{\"status\":\"probe_only\",\"matches\":%u,\"bounded\":%s,\"binding_valid\":%s,\"main_thread\":%s,\"mutation_ready\":false}\n",
            result.matches, result.bounded ? "true" : "false",
            request.valid ? "true" : "false", request.on_main ? "true" : "false");
        close(client);
    }
    close(server);
    return NULL;
}

#ifdef WXS_SELF_TEST
int main(void) { return self_test(); }
#elif defined(WXS_HOST_TEST)
// Standalone harness: its socket and main queue belong to this process, not WeChat.
int main(void) {
    pthread_t thread;
    if (pthread_create(&thread, NULL, serve, NULL)) return 1;
    pthread_detach(thread);
    dispatch_main();
}
#else
__attribute__((constructor)) static void start(void) {
    if (!main_executable()) return;
    pthread_t thread;
    if (!pthread_create(&thread, NULL, serve, NULL)) pthread_detach(thread);
}
#endif
