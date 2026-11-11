// wechat_send.c — minimal in-process sender for WeChat for Mac (arm64).
//
// Loaded into a *re-signed clone* of WeChat.app (load-command injection, see
// build_dylib.sh). It drives WeChat's own Qt widgets from inside the process:
//
//   1. find the chat input view: scan writable memory for an object whose
//      *dynamic type* (RTTI) name contains "ChatInputView"
//   2. find the editor: the input view owns it, so scan that object's members
//      for a pointer to an object whose RTTI name contains "TextEdit"
//      (global scan is only the fallback)
//   3. set the draft:  <QTextEdit static_metacall>(editor, InvokeMetaMethod, 16, {0,&qstring})
//      (id 16 = setPlainText(QString); verified on 4.1.10 and 4.2.0 with MetaNames.java)
//   4. send:          <ChatInputView static_metacall>(input, InvokeMetaMethod, 8, {0,&action})
//      (4.2.0 local id: m[8] Send(SendActionType); 4.1.10's map said 5 — always re-derive)
//
// No debugger, no task_for_pid, no mach_vm_write: everything runs in-process.
// This is the whole point — upstream uses LLDB/mach_vm_write because it wants a
// server-pushed profile; a loaded dylib does not need to.
//
// Everything below is env/config driven, because a relaunch of the clone costs
// a re-login (the ad-hoc signature no longer matches the keychain ACL holding
// the session). Prefer /tmp/wxs.conf over env vars when you can:
//   WXS_QTEDIT_SMC=0x6c8fea8   (QTextEdit::static_metacall, 4.2.0)
//   WXS_INPUT_SMC=0x133510     (mmui::ChatInputView::static_metacall, 4.2.0)
//   WXS_INPUT_RTTI=ChatInputView  WXS_EDITOR_RTTI=TextEdit
//   WXS_SOCKET=/tmp/wechat_send.sock
//   /tmp/wxs.conf (re-read per request): set_id=16  send_id=8  action=<SendActionType>
//
// CAVEATS:
//   * SendActionType value for plain text (config `action`) is still unverified.
//   * Qt6 QString is hand-built here (ref=-1, size, offset) instead of calling
//     QString::fromUtf8, so no Qt string symbol is needed.
//
// Build: scripts/native/build_dylib.sh

#include <mach/mach.h>
#include <mach/mach_vm.h>
#include <mach/vm_region.h>
#include <mach-o/dyld.h>
#include <dlfcn.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

typedef void (*meta_fn)(void *obj, int call, int id, void **args);
#define INVOKE_META_METHOD 0

static unsigned long env_rva(const char *k, unsigned long dflt) {
    const char *v = getenv(k);
    return v ? strtoul(v, NULL, 0) : dflt;
}

// base of the *core* wechat.dylib image.
// Careful: two images are named "wechat.dylib" --
//   Contents/Resources/wechat.dylib   ~307 MB  <- the real core (RVAs are for this)
//   Contents/Frameworks/wechat.dylib  ~84 KB   <- a stub; base+RVA against it jumps garbage
// So match the Resources path explicitly (fall back to the largest match).
static unsigned long wechat_dylib_base(void) {
    uint32_t cnt = _dyld_image_count();
    unsigned long best = 0;
    for (uint32_t i = 0; i < cnt; i++) {
        const char *n = _dyld_get_image_name(i);
        if (!n || !strstr(n, "wechat.dylib")) continue;
        unsigned long base = (unsigned long)_dyld_get_image_header(i);
        if (strstr(n, "/Contents/Resources/wechat.dylib")) return base;   // exact: the core
        if (!best) best = base;                                          // fallback
    }
    return best;
}

// Build a Qt6 QString in place. Qt6 QString is a single pointer to
// QArrayData{int ref; int size; uint alloc; uint cap; qptrdiff offset;} + data.
// Static data uses ref == -1; the payload follows the header.
typedef struct {
    void *d_ptr;
    void *backing;              // keeps the QArrayData alive
} qstring_t;

static qstring_t make_qstring(const uint16_t *utf16, int len) {
    size_t hdr = 24, bytes = (size_t)(len + 1) * 2;
    unsigned char *blk = calloc(1, hdr + bytes);
    if (!blk) return (qstring_t){0, 0};
    int *ref = (int *)(blk);
    int *size = (int *)(blk + 4);
    long *offset = (long *)(blk + 16);
    *ref = -1;
    *size = len;
    *offset = (long)(hdr - 8);          // data pointer sits after the header
    memcpy(blk + hdr, utf16, bytes);
    qstring_t q = { blk, blk };
    return q;
}

static const uint16_t *utf8_to_utf16(const char *s, int *out_len) {
    size_t n = strlen(s);
    uint16_t *w = calloc(n + 1, sizeof(uint16_t));
    int k = 0;
    for (size_t i = 0; i < n;) {
        unsigned char c = (unsigned char)s[i];
        unsigned cp;
        if (c < 0x80) { cp = c; i += 1; }
        else if ((c >> 5) == 0x6 && i + 1 < n) { cp = ((c & 0x1f) << 6) | (s[i+1] & 0x3f); i += 2; }
        else if ((c >> 4) == 0xe && i + 2 < n) { cp = ((c & 0x0f) << 12) | ((s[i+1] & 0x3f) << 6) | (s[i+2] & 0x3f); i += 3; }
        else if ((c >> 3) == 0x1e && i + 3 < n) {
            cp = ((c & 0x07) << 18) | ((s[i+1] & 0x3f) << 12) | ((s[i+2] & 0x3f) << 6) | (s[i+3] & 0x3f); i += 4;
            if (cp > 0xffff) {                       // surrogate pair
                cp -= 0x10000;
                w[k++] = 0xd800 + (cp >> 10);
                w[k++] = 0xdc00 + (cp & 0x3ff);
                continue;
            }
        } else { cp = 0xfffd; i += 1; }
        w[k++] = (uint16_t)cp;
    }
    w[k] = 0;
    *out_len = k;
    return w;
}

// Safe read: mach_vm_read_overwrite returns an error instead of crashing the
// process when the range is not backed. Never dereference arbitrary addresses.
static int safe_read(const void *addr, void *dst, size_t n, size_t *got) {
    mach_vm_size_t g = 0;
    kern_return_t kr = mach_vm_read_overwrite(mach_task_self(),
        (mach_vm_address_t)addr, n, (mach_vm_address_t)dst, &g);
    if (got) *got = (size_t)g;
    return kr == KERN_SUCCESS;
}

// Read n bytes from a possibly-invalid address; 1 on success.
static int readable(const void *addr, void *dst, size_t n) {
    size_t got = 0;
    return safe_read(addr, dst, n, &got) && got == n;
}

// Itanium RTTI: object -> vptr; vptr[-1] -> type_info; type_info+8 -> name.
// Matching by *dynamic type name* instead of one exact vtable is what makes
// discovery work: the object that is actually instantiated is usually a
// subclass, whose vtable address differs from the one the metaobject scan
// reports. (v3 matched the exact vtable and found zero callable objects.)
static int obj_type_matches(const void *p, const char *needle, char *out, size_t outsz) {
    unsigned long vptr = 0, ti = 0, namep = 0;
    char buf[256];
    if (!readable(p, &vptr, 8) || vptr < 0x100000000UL) return 0;
    if (!readable((const char *)vptr - 8, &ti, 8) || ti < 0x100000000UL) return 0;
    if (!readable((const char *)ti + 8, &namep, 8) || namep < 0x100000000UL) return 0;
    if (!readable((const void *)namep, buf, sizeof(buf) - 1)) return 0;
    buf[sizeof(buf) - 1] = 0;
    if (!strstr(buf, needle)) return 0;
    if (out && outsz) { strncpy(out, buf, outsz - 1); out[outsz - 1] = 0; }
    return 1;
}

// First object in writable memory whose dynamic type name contains `needle`.
// `name` receives the mangled type name actually matched (evidence in the log).
static void *find_by_rtti(const char *needle, unsigned long img_lo, unsigned long img_hi,
                          char *name, size_t namesz) {
    const size_t CHUNK = 0x1000;
    unsigned char *buf = malloc(CHUNK);
    if (!buf) return NULL;
    vm_address_t addr = 0;
    void *found = NULL;
    for (;;) {
        vm_size_t size = 0;
        vm_region_basic_info_data_64_t info;
        mach_msg_type_number_t cnt = VM_REGION_BASIC_INFO_COUNT_64;
        mach_port_t obj = MACH_PORT_NULL;
        if (vm_region_64(mach_task_self(), &addr, &size, VM_REGION_BASIC_INFO_64,
                         (vm_region_info_t)&info, &cnt, &obj) != KERN_SUCCESS) break;
        if (obj != MACH_PORT_NULL) mach_port_deallocate(mach_task_self(), obj);
        if ((info.protection & VM_PROT_WRITE) && !(info.protection & VM_PROT_EXECUTE)
            && size <= (256UL << 20)) {
            unsigned long end = addr + size;
            for (unsigned long p = addr; p + 8 <= end; p += CHUNK) {
                size_t want = (size_t)((end - p) < CHUNK ? (end - p) : CHUNK), got = 0;
                if (!safe_read((void *)p, buf, want, &got) || got < 8) continue;
                for (size_t off = 0; off + 8 <= got; off += 8) {
                    unsigned long v = *(unsigned long *)(buf + off);
                    if (v < img_lo || v >= img_hi) continue;   // must look like a vptr
                    if (obj_type_matches((void *)(p + off), needle, name, namesz)) {
                        found = (void *)(p + off);
                        goto done;
                    }
                }
            }
        }
        addr += size;
    }
done:
    free(buf);
    return found;
}

// Same check, but only over the members of one object: the editor is owned by
// the input view, so this is both faster and much less prone to false hits.
static void *find_member_by_rtti(void *parent, size_t span, const char *needle,
                                 char *name, size_t namesz) {
    for (size_t off = 0; off + 8 <= span; off += 8) {
        unsigned long v = 0;
        if (!readable((char *)parent + off, &v, 8) || v < 0x100000000UL) continue;
        if (obj_type_matches((void *)v, needle, name, namesz)) return (void *)v;
    }
    return NULL;
}

// Method ids come from /tmp/wxs.conf (KEY=VALUE), re-read per request, so a
// wrong id costs a file edit -- not a relaunch. A relaunch costs a re-login:
// the ad-hoc re-signature no longer matches the keychain ACL that holds the
// WeChat session, so the clone comes back at the QR screen.
static void conf_int(const char *key, int *dst) {
    const char *path = getenv("WXS_CONF") ?: "/tmp/wxs.conf";
    FILE *f = fopen(path, "r");
    if (!f) return;
    char line[256];
    while (fgets(line, sizeof line, f)) {
        char *eq = strchr(line, '=');
        if (!eq) continue;
        *eq = 0;
        char *k = line;
        while (*k == ' ' || *k == '\t') k++;
        char *e = k + strlen(k);
        while (e > k && (e[-1] == ' ' || e[-1] == '\t' || e[-1] == '\n' || e[-1] == '\r')) *--e = 0;
        if (!strcmp(k, key)) *dst = (int)strtol(eq + 1, NULL, 0);
    }
    fclose(f);
}

static int do_send(void *input, void *editor, meta_fn qte_smc, meta_fn in_smc,
                   int set_id, int send_id, int action, const char *text) {
    if (!input || !editor) return -1;
    int len = 0;
    const uint16_t *w = utf8_to_utf16(text, &len);
    qstring_t q = make_qstring(w, len);
    void *set_args[2] = { NULL, &q };                       // {retval, QString*}
    dprintf(2, "[wxs] setPlainText id=%d obj=%p smc=%p len=%d\n", set_id, editor, (void *)qte_smc, len);
    qte_smc(editor, INVOKE_META_METHOD, set_id, set_args);  // 16 = QTextEdit::setPlainText(QString)
    dprintf(2, "[wxs] setPlainText returned\n");
    void *send_args[2] = { NULL, &action };                 // {retval, SendActionType*}
    dprintf(2, "[wxs] Send id=%d obj=%p smc=%p action=%d\n", send_id, input, (void *)in_smc, action);
    in_smc(input, INVOKE_META_METHOD, send_id, send_args);  // mmui::ChatInputView::Send(SendActionType)
    dprintf(2, "[wxs] Send returned\n");
    free((void *)w);
    if (q.backing) free(q.backing);
    return 0;
}

// Helpers (WeChatAppEx, *Helper) inherit DYLD_INSERT_LIBRARIES too; only the
// main executable should own the socket.
static int is_main_executable(void) {
    char buf[4096];
    uint32_t sz = sizeof(buf);
    if (_NSGetExecutablePath(buf, &sz) != 0) return 0;
    // must END with it: ".../WeChatAppEx.app/Contents/MacOS/WeChatAppEx" also
    // contains "/Contents/MacOS/WeChat" as a prefix, and helpers do not map wechat.dylib.
    const char *suffix = "/Contents/MacOS/WeChat";
    size_t n = strlen(buf), m = strlen(suffix);
    return n >= m && strcmp(buf + n - m, suffix) == 0;
}

static void serve(void) {
    if (!is_main_executable()) return;
    // wechat.dylib is not mapped yet when this constructor runs -> resolve lazily.
    unsigned long base = 0;
    unsigned long qte_smc = base + env_rva("WXS_QTEDIT_SMC", 0x6c8fea8);
    unsigned long in_smc = base + env_rva("WXS_INPUT_SMC", 0x133510);
    const char *in_rtti = getenv("WXS_INPUT_RTTI") ?: "ChatInputView";
    const char *ed_rtti = getenv("WXS_EDITOR_RTTI") ?: "TextEdit";
    const char *sock_path = getenv("WXS_SOCKET") ?: "/tmp/wechat_send.sock";

    unlink(sock_path);
    int srv = socket(AF_UNIX, SOCK_STREAM, 0);
    struct sockaddr_un sa = {0};
    sa.sun_family = AF_UNIX;
    strncpy(sa.sun_path, sock_path, sizeof(sa.sun_path) - 1);
    if (bind(srv, (struct sockaddr *)&sa, sizeof(sa)) || listen(srv, 4)) {
        fprintf(stderr, "[wechat_send] bind/listen failed: %s\n", sock_path);
        return;
    }
    for (;;) {
        int c = accept(srv, NULL, NULL);
        if (c < 0) continue;
        char buf[8192] = {0};
        ssize_t n = read(c, buf, sizeof(buf) - 1);
        if (n <= 0) { close(c); continue; }
        if (!base) {
            base = wechat_dylib_base();
            if (base) {
                qte_smc = base + env_rva("WXS_QTEDIT_SMC", 0x6c8fea8);
                in_smc  = base + env_rva("WXS_INPUT_SMC", 0x133510);
            } else { dprintf(c, "notready: wechat.dylib not mapped\n"); close(c); continue; }
        }
        int set_id = 16, send_id = 8, action = 0;   // defaults = WeChat 4.2.0
        conf_int("set_id", &set_id);
        conf_int("send_id", &send_id);
        conf_int("action", &action);
        char nm[256] = "", nm2[256] = "";
        void *input = find_by_rtti(in_rtti, base, base + 0x40000000UL, nm, sizeof nm);
        void *editor = NULL;
        if (input) editor = find_member_by_rtti(input, 0x800, ed_rtti, nm2, sizeof nm2);
        if (!editor) editor = find_by_rtti(ed_rtti, base, base + 0x40000000UL, nm2, sizeof nm2);
        dprintf(2, "[wxs] input=%p(%s) editor=%p(%s) set_id=%d send_id=%d action=%d\n",
                input, nm, editor, nm2, set_id, send_id, action);
        int rc = do_send(input, editor, (meta_fn)qte_smc, (meta_fn)in_smc,
                         set_id, send_id, action, buf);
        dprintf(2, "[wxs] do_send rc=%d\n", rc);
        dprintf(c, rc == 0 ? "ok\n" : "fail %d\n", rc);
        close(c);
    }
}

__attribute__((constructor)) static void start(void) {
    pthread_t t;
    pthread_create(&t, NULL, (void *(*)(void *))serve, NULL);
}
