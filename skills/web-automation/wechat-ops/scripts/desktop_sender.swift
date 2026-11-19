import AppKit
import CryptoKit
import Darwin
import ImageIO

// Local Cua transport only. Never dispatch to the main WeChat or an arbitrary chat.
let bundle = "com.tencent.xinWeChat.send"
let helper = "文件传输助手"
let session = "wechat-desktop-\(UUID().uuidString)"
typealias JSONObject = [String: Any]
struct Refused: Error { let reason: String; init(_ reason: String) { self.reason = reason } }

func json(_ object: JSONObject) throws -> Data {
    try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
}
func object(_ data: Data) throws -> JSONObject {
    guard let result = try JSONSerialization.jsonObject(with: data) as? JSONObject else {
        throw Refused("expected a JSON object")
    }
    return result
}
var usedDriver = false
func cua(_ tool: String, _ args: JSONObject = [:]) throws -> JSONObject {
    usedDriver = true
    var args = args
    args["session"] = session
    let proc = Process(), out = Pipe()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    proc.arguments = ["cua-driver", "call", tool, String(decoding: try json(args), as: UTF8.self)]
    proc.standardOutput = out
    // Driver errors may embed chat content. Do not forward them to stdout or logs.
    proc.standardError = FileHandle.nullDevice
    try proc.run()
    let timer = DispatchWorkItem { if proc.isRunning { _ = kill(proc.processIdentifier, SIGKILL) } }
    DispatchQueue.global().asyncAfter(deadline: .now() + 18, execute: timer)
    let bytes = out.fileHandleForReading.readDataToEndOfFile()
    proc.waitUntilExit()
    timer.cancel()
    guard proc.terminationStatus == 0, let result = try? object(bytes) else {
        throw Refused("driver did not return a usable response for \(tool)")
    }
    return result
}

struct Window: Equatable {
    let pid: Int
    let id: Int
    let title: String
    let width: Double
    var args: JSONObject { ["pid": pid, "window_id": id] }
}
func windows() throws -> [Window] {
    let data = try cua("list_windows", ["app": bundle])
    guard let rows = data["windows"] as? [JSONObject] else { throw Refused("window list unavailable") }
    return rows.compactMap { row in
        guard row["layer"] as? Int == 0, row["is_on_screen"] as? Bool == true,
              let pid = row["pid"] as? Int, let id = row["window_id"] as? Int,
              let title = row["title"] as? String, let bounds = row["bounds"] as? JSONObject,
              let width = bounds["width"] as? Double else { return nil }
        return Window(pid: pid, id: id, title: title, width: width)
    }
}
func requireBackground(_ w: Window) throws {
    guard let app = NSRunningApplication(processIdentifier: pid_t(w.pid)), app.bundleIdentifier == bundle,
          let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != app.processIdentifier else {
        throw Refused("test clone is unavailable, unverified, or frontmost")
    }
}
func snapshot(_ w: Window) throws -> JSONObject {
    try requireBackground(w)
    let r = try cua("get_window_state", w.args.merging([
        "include_screenshot": false, "tree_format": "both", "max_depth": 22, "max_elements": 250,
    ]) { _, b in b })
    // Recheck owner binding: a forked/recycled PID or stale snapshots must not redirect input.
    guard r["pid"] as? Int == w.pid, r["window_id"] as? Int == w.id,
          r["degraded_reason"] == nil, r["window_title"] as? String == w.title,
          r["elements"] is [JSONObject], r["tree_markdown"] is String else {
        throw Refused("test clone window is not accessible in the background")
    }
    return r
}
func lines(_ r: JSONObject) -> [String] { (r["tree_markdown"] as? String ?? "").components(separatedBy: "\n") }

struct Chat {
    let window: Window
    let token: String
    let draft: String
    let messages: [String]
    let photoDraft: Bool
    let canSend: Bool
}
func chat(_ w: Window, _ r: JSONObject) -> Chat? {
    let rows = lines(r)
    guard let title = rows.onlyMatch(#"^\s*- \[([0-9]+)\] AXStaticText .*\[id=big_title_line_h_view "#),
          let editor = rows.onlyMatch(#"^\s*- \[([0-9]+)\] AXTextArea .*\[id=chat_input_field "#),
          let elements = r["elements"] as? [JSONObject],
          elements.contains(where: { $0["element_index"] as? Int == title && $0["role"] as? String == "AXStaticText" && $0["label"] as? String == helper }),
          let input = elements.first(where: { $0["element_index"] as? Int == editor && $0["role"] as? String == "AXTextArea" }),
          let token = input["element_token"] as? String else { return nil }
    let messageIndexes = Set(rows.matches(#"^\s*- \[([0-9]+)\] AXStaticText .*\[id=chat_bubble_item_view "#))
    return Chat(window: w, token: token, draft: input["value"] as? String ?? "",
                messages: elements.compactMap { row in
                    guard let index = row["element_index"] as? Int, messageIndexes.contains(index),
                          row["role"] as? String == "AXStaticText" else { return nil }
                    return row["label"] as? String
                },
                photoDraft: rows.contains { $0.contains("发送后合并展示照片") },
                canSend: elements.filter { $0["role"] as? String == "AXButton" && $0["label"] as? String == "发送" && $0["enabled"] as? Bool == true }.count == 1)
}
extension Array where Element == String {
    func matches(_ pattern: String) -> [Int] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return compactMap { row -> Int? in
            guard let m = regex.firstMatch(in: row, range: NSRange(row.startIndex..., in: row)),
                  let range = Range(m.range(at: 1), in: row) else { return nil }
            return Int(row[range])
        }
    }

    func onlyMatch(_ pattern: String) -> Int? {
        let all = matches(pattern)
        return all.count == 1 ? all[0] : nil
    }
}
func action(_ w: Window, _ step: JSONObject, _ observe: Bool = false) throws {
    try requireBackground(w)
    var args = w.args
    args["delivery_mode"] = "background"
    args["foreground_fallback"] = false
    args["steps"] = [step]
    if observe { args["observe"] = ["include_screenshot": false] }
    let r = try cua("run_steps", args)
    guard r["ok"] as? Bool == true else { throw Refused("background action was refused or unverified") }
}
func helperSessionToken(_ r: JSONObject) -> String? {
    let rows = lines(r)
    guard let elements = r["elements"] as? [JSONObject] else { return nil }
    let candidates = elements.filter { element in
        guard element["role"] as? String == "AXStaticText",
              let label = element["label"] as? String,
              label.components(separatedBy: "\n").first == helper,
              let index = element["element_index"] as? Int,
              let first = rows.firstIndex(where: {
                  $0.trimmingCharacters(in: .whitespaces).hasPrefix("- [\(index)] AXStaticText \"")
              }) else { return false }
        let block = [rows[first]] + rows.dropFirst(first + 1).prefix { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("- ") }
        return block.contains { $0.contains("[id=session_item_文件传输助手 actions=[press]") }
    }
    return candidates.count == 1 ? candidates[0]["element_token"] as? String : nil
}

func locate(navigate: Bool) throws -> Chat {
    let ws = try windows()
    let exact = ws.filter { $0.title == helper }
    let main = ws.filter { $0.title == "微信" && $0.width >= 500 }
    guard exact.count <= 1, let w = exact.first ?? (main.count == 1 ? main[0] : nil) else {
        throw Refused("no unique accessible test clone chat window")
    }
    let r = try snapshot(w)
    if let c = chat(w, r) { return c }
    guard navigate, exact.isEmpty, let token = helperSessionToken(r) else {
        throw Refused("filehelper is not selected or its session row is ambiguous")
    }
    try action(w, ["click": ["element_token": token]])
    return try locate(navigate: false)
}

func withFiles<T>(_ files: [URL], on pb: NSPasteboard = .general, _ body: () throws -> T) throws -> T {
    let old = pb.changeCount
    let previous = try (pb.pasteboardItems ?? []).map { item -> NSPasteboardItem in
        let saved = NSPasteboardItem()
        // Copy static text/HTML bytes; leave file promises and unknown formats alone.
        for type in item.types {
            guard ["NSStringPboardType", "public.utf8-plain-text", "Apple HTML pasteboard type", "public.html"].contains(type.rawValue),
                  let bytes = item.data(forType: type), saved.setData(bytes, forType: type) else {
                throw Refused("clipboard format is not proven restorable; left unchanged")
            }
        }
        return saved
    }
    guard pb.changeCount == old else { throw Refused("clipboard changed during backup") }
    var owned = pb.clearContents()
    let written = pb.writeObjects(files as [NSURL])
    owned = pb.changeCount
    func restore() throws {
        guard pb.changeCount == owned else { return } // Preserve the user's newer copy.
        pb.clearContents()
        if !previous.isEmpty && !pb.writeObjects(previous) { throw Refused("clipboard restore failed") }
    }
    let result = Result {
        guard written, let actual = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
              actual.map(\.path) == files.map(\.path), pb.changeCount == owned else { throw Refused("clipboard staging could not be verified") }
        return try body()
    }
    try restore()
    return try result.get()
}

// shortcut: visible AX labels only, use an authorized history backend for full history or message metadata.
func readVisible(_ req: JSONObject, target: (Bool) throws -> Chat) throws -> JSONObject {
    guard req["recipient"] as? String == "filehelper" else { throw Refused("only filehelper is supported") }
    let op = req["op"] as? String
    let allowed: Set<String> = op == "search" ? ["op", "recipient", "limit", "query"] : ["op", "recipient", "limit"]
    guard Set(req.keys).isSubset(of: allowed) else { throw Refused("unsupported visible-history parameter") }
    let limit = req["limit"] ?? 20
    guard let number = limit as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
          (1...100).contains(number.intValue), number.doubleValue == Double(number.intValue) else {
        throw Refused("limit must be an integer from 1 to 100")
    }
    let query = req["query"] as? String
    if op == "search" {
        guard let query, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              query.utf16.count <= 2000 else { throw Refused("search requires a nonempty query up to 2000 UTF-16 code units") }
    }
    // Do not click, scroll, or open a conversation while reading.
    let visible = try target(false).messages
    let selected = Array(visible.suffix(number.intValue))
    var result: JSONObject = ["status": "ok", "recipient": "filehelper", "scope": "visible_ax_labels",
                              "complete_history": false, "visible_count": visible.count, "scanned_count": selected.count]
    if op == "stats" {
        result["label_frequencies"] = Dictionary(grouping: selected, by: { $0 }).values.map(\.count).sorted(by: >)
        result["distinct_label_count"] = Set(selected).count
    } else {
        let matches = query.map { q in selected.filter { $0.range(of: q, options: [.caseInsensitive, .literal]) != nil } } ?? selected
        result["items"] = matches.map { ["label": $0] }
        result["match_count"] = matches.count
    }
    return result
}

func dispatch(_ req: JSONObject,
              stateDir: String? = ProcessInfo.processInfo.environment["WECHAT_DESKTOP_STATE_DIR"],
              target: (Bool) throws -> Chat = { try locate(navigate: $0) },
              read: @escaping (Window) throws -> Chat = { w in
                  guard let state = chat(w, try snapshot(w)) else { throw Refused("filehelper identity could not be verified") }
                  return state
              },
              act: @escaping (Window, JSONObject) throws -> Void = { try action($0, $1) },
              paste: ([URL], () throws -> Chat) throws -> Chat = { try withFiles($0, $1) },
              draftWait: TimeInterval = 4, readbackWait: TimeInterval = 6) throws -> JSONObject {
    switch req["op"] as? String {
    case "probe":
        let c = try target(false)
        return ["status": "target_matched", "recipient": "filehelper", "draft_empty": c.draft.isEmpty]
    case "history", "search", "stats":
        return try readVisible(req, target: target)
    case "send", "receipt": break
    default: throw Refused("op must be probe, history, search, stats, send or receipt")
    }
    guard let id = req["request_id"] as? String, id.range(of: #"\A[A-Za-z0-9_-]{1,128}\z"#, options: .regularExpression) != nil,
          let location = stateDir, location.hasPrefix("/") else {
        throw Refused("request_id and an absolute WECHAT_DESKTOP_STATE_DIR are required")
    }
    var st = stat()
    guard lstat(location, &st) == 0, (st.st_mode & S_IFMT) == S_IFDIR, st.st_uid == geteuid(), st.st_mode & 0o777 == 0o700 else {
        throw Refused("state directory must exist, be owned by the current user and have mode 0700")
    }
    let dir = URL(fileURLWithPath: location, isDirectory: true)
    let receipt = dir.appendingPathComponent(id + ".json")
    if req["op"] as? String == "receipt" {
        if !FileManager.default.fileExists(atPath: receipt.path) { return ["status": "not_found", "request_id": id] }
        var value = try object(Data(contentsOf: receipt)); value.removeValue(forKey: "fingerprint"); return value
    }
    let lock = open(dir.appendingPathComponent("sender.lock").path, O_WRONLY | O_CREAT | O_NOFOLLOW, 0o600)
    guard lock >= 0 else { throw Refused("could not open sender lock") }
    defer { close(lock) }
    guard flock(lock, LOCK_EX | LOCK_NB) == 0 else { throw Refused("another send is in progress; query its receipt") }
    guard req["recipient"] as? String == "filehelper" else { throw Refused("only filehelper is supported") }
    let text = req["text"] as? String
    let paths = req["photos"] as? [String]
    guard (text != nil) != (paths != nil), (req["text"] == nil) == (text == nil), (req["photos"] == nil) == (paths == nil) else {
        throw Refused("provide exactly one of text or photos")
    }
    var files: [URL] = []
    if let text {
        guard !text.isEmpty, text.utf16.count <= 2000,
              text.rangeOfCharacter(from: CharacterSet.controlCharacters.union(.newlines)) == nil,
              !text.contains("\u{fffc}") else { throw Refused("only single-line plain text up to 2000 UTF-16 code units is supported") }
    } else if let paths {
        guard (1...4).contains(paths.count), paths.allSatisfy({ $0.hasPrefix("/") }) else { throw Refused("provide 1–4 absolute JPEG paths") }
        files = try paths.map { path in
            let url = URL(fileURLWithPath: path).resolvingSymlinksInPath()
            let props = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard props.isRegularFile == true, let size = props.fileSize, size > 0, size <= 32 * 1024 * 1024,
                  let image = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetType(image) as String? == "public.jpeg" else {
                throw Refused("photos must be readable local JPEGs, at most 32 MiB each")
            }
            return url
        }
        guard Set(files).count == files.count else { throw Refused("duplicate photo paths") }
    }
    var content: JSONObject = [:]
    if let text { content["text"] = text } else {
        content["photos"] = try files.map { file in
            ["path": file.path, "sha256": SHA256.hash(data: try Data(contentsOf: file)).map { String(format: "%02x", $0) }.joined()]
        }
    }
    let fingerprint = SHA256.hash(data: try json(content)).map { String(format: "%02x", $0) }.joined()
    if FileManager.default.fileExists(atPath: receipt.path) {
        var prior = try object(Data(contentsOf: receipt))
        guard prior.removeValue(forKey: "fingerprint") as? String == fingerprint else { throw Refused("request_id already used for different contents") }
        return prior
    }
    let start = ProcessInfo.processInfo.systemUptime
    let c = try target(true), w = c.window
    guard c.draft.isEmpty else { throw Refused("existing draft left unchanged") }
    let frontBefore = NSWorkspace.shared.frontmostApplication?.processIdentifier
    var row: JSONObject = ["status": "status_unknown", "request_id": id, "fingerprint": fingerprint,
                           "diagnostic": "registered before writing draft; do not replay an uncertain operation"]
    try json(row).write(to: receipt, options: [.atomic])
    var submitAttempted = false
    do {
        let staged: Chat
        if let text {
            try act(w, ["type_text": ["element_token": c.token, "text": text]])
            staged = try read(w)
            guard staged.draft == text else { throw Refused("draft did not match the complete text") }
        } else {
            staged = try paste(files) {
                try act(w, ["press_key": ["element_token": c.token, "key": "v", "modifiers": ["cmd"]]])
                let expected = String(repeating: "\u{fffc}", count: files.count)
                let deadline = ProcessInfo.processInfo.systemUptime + draftWait
                while true {
                    let current = try read(w)
                    if current.draft == expected && (files.count == 1 || current.photoDraft) && current.canSend {
                        return current
                    }
                    guard expected.hasPrefix(current.draft), ProcessInfo.processInfo.systemUptime < deadline else {
                        throw Refused("photo draft count or media marker did not match; no submit attempted")
                    }
                    // Qt can populate the draft after the key dispatch has returned. Never paste twice.
                    Thread.sleep(forTimeInterval: 0.10)
                }
            }
        }
        guard staged.canSend else { throw Refused("send control is not ready") }
        let beforeSubmit = ProcessInfo.processInfo.systemUptime
        submitAttempted = true
        try act(w, ["press_key": ["element_token": staged.token, "key": "Return"]])
        let tracked = text ?? "图片"
        let previousCount = staged.messages.filter { $0 == tracked }.count
        let deadline = beforeSubmit + readbackWait
        var delta: Int
        while true {
            let after = try read(w)
            delta = after.messages.filter { $0 == tracked }.count - previousCount
            if after.draft.isEmpty && delta > 0 { break }
            guard (after.draft == staged.draft || after.draft.isEmpty),
                  ProcessInfo.processInfo.systemUptime < deadline else {
                throw Refused("no distinct new sender-side message verified; do not replay this request")
            }
            // The send may finish after the key returns. Only poll reads, never replay Return.
            Thread.sleep(forTimeInterval: 0.15)
        }
        let end = ProcessInfo.processInfo.systemUptime
        row["status"] = "submitted_unconfirmed"
        row["diagnostic"] = "draft cleared and new matching sender-side message rows appeared; recipient delivery not verified"
        row["visible_matching_rows_delta"] = delta
        if !files.isEmpty { row["photos_submitted"] = files.count }
        row["prepare_ms"] = Int((beforeSubmit - start) * 1000)
        row["submit_and_readback_ms"] = Int((end - beforeSubmit) * 1000)
        row["same_frontmost_sample"] = frontBefore == NSWorkspace.shared.frontmostApplication?.processIdentifier
    } catch {
        row["status"] = submitAttempted ? "status_unknown" : "failed"
        row["diagnostic"] = (error as? Refused)?.reason ?? "operation stopped; check the original receipt and draft before doing anything else"
    }
    do {
        try json(row).write(to: receipt, options: [.atomic])
    } catch {
        // The earlier receipt remains authoritative if final persistence fails.
        return ["status": "status_unknown", "request_id": id,
                "diagnostic": "could not save final receipt; do not replay this request"]
    }
    row.removeValue(forKey: "fingerprint")
    return row
}

func selfTest() throws {
    let state = FileManager.default.temporaryDirectory.appendingPathComponent("wechat-sender-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: state, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    defer { try! FileManager.default.removeItem(at: state) }
    let w = Window(pid: 123, id: 42, title: helper, width: 598)
    let fixture: JSONObject = [
        "tree_markdown": "- [1] AXStaticText = \"文件传输助手\" [id=big_title_line_h_view actions=[raise]]\n- [4] AXTextArea \"输入\" [id=chat_input_field actions=[raise]]\n- [6] AXStaticText \"你好\" [id=chat_bubble_item_view actions=[press]]\n- [7] AXStaticText \"文件传输助手\n图片\n14:44\" [id=session_item_文件传输助手 actions=[press]]",
        "elements": [["element_index": 1, "role": "AXStaticText", "label": helper],
                     ["element_index": 4, "role": "AXTextArea", "element_token": "s00000001:4"],
                     ["element_index": 6, "role": "AXStaticText", "label": "你好"],
                     ["element_index": 7, "role": "AXStaticText", "label": "文件传输助手\n图片\n14:44", "element_token": "s00000001:7"]]
    ]
    precondition(chat(w, fixture)?.messages == ["你好"])
    precondition(helperSessionToken(fixture) == "s00000001:7")
    precondition(helperSessionToken(fixture.merging(["tree_markdown": "- [7] AXStaticText \"文件传输助手\" [id=session_item_other actions=[press]]"]) { _, new in new }) == nil)
    func view(_ draft: String, _ messages: [String] = []) -> Chat {
        Chat(window: w, token: "s00000001:4", draft: draft, messages: messages, photoDraft: false, canSend: !draft.isEmpty)
    }
    let recent: (Bool) throws -> Chat = { navigate in
        precondition(!navigate, "read-only operations must not navigate")
        return view("", ["旧消息", "Alpha 123", "图片", "图片"])
    }
    let history = try dispatch(["op": "history", "recipient": "filehelper", "limit": 3], target: recent)
    precondition((history["items"] as? [[String: String]])?.compactMap { $0["label"] } == ["Alpha 123", "图片", "图片"])
    precondition(history["complete_history"] as? Bool == false && history["visible_count"] as? Int == 4)
    let hits = try dispatch(["op": "search", "recipient": "filehelper", "query": "alpha"], target: recent)
    precondition(hits["match_count"] as? Int == 1 && hits["scanned_count"] as? Int == 4)
    let missed = try dispatch(["op": "search", "recipient": "filehelper", "query": "Alpha", "limit": 2], target: recent)
    precondition(missed["match_count"] as? Int == 0 && missed["scanned_count"] as? Int == 2)
    let counts = try dispatch(["op": "stats", "recipient": "filehelper", "limit": 3], target: recent)
    precondition(counts["label_frequencies"] as? [Int] == [2, 1] && counts["distinct_label_count"] as? Int == 2 && counts["items"] == nil)
    for invalid: JSONObject in [["op": "history", "recipient": "other"], ["op": "history", "recipient": "filehelper", "limit": true],
                                 ["op": "stats", "recipient": "filehelper", "limit": 101], ["op": "search", "recipient": "filehelper", "query": "  "],
                                 ["op": "history", "recipient": "filehelper", "since": "today"]] {
        do {
            _ = try dispatch(invalid, target: { _ in preconditionFailure("invalid input reached the reader") })
            preconditionFailure("invalid history request accepted")
        } catch is Refused {}
    }
    var submits = 0
    var draft = ""
    var lostReply = false
    var wrongDraft = false
    func send(_ id: String, text: String = "你好", recipient: String = "filehelper") throws -> JSONObject {
        try dispatch(["op": "send", "request_id": id, "recipient": recipient, "text": text], stateDir: state.path,
                     target: { _ in view(draft) }, read: { _ in view(draft, draft.isEmpty ? [text] : []) },
                     act: { _, command in
                         if command["type_text"] != nil { draft = wrongDraft ? "错误正文" : text }
                         else {
                             submits += 1
                             if lostReply { throw Refused("simulated timeout") }
                             draft = ""
                         }
                     })
    }
    func requireStatus(_ row: JSONObject, _ status: String) {
        precondition(row["status"] as? String == status, "unexpected status: \(row)")
    }
    requireStatus(try send("once"), "submitted_unconfirmed")
    requireStatus(try send("once"), "submitted_unconfirmed")
    do { _ = try send("once", text: "不同正文"); preconditionFailure("request conflict accepted") } catch is Refused {}
    do { _ = try send("other", recipient: "other"); preconditionFailure("wrong recipient accepted") } catch is Refused {}
    precondition(submits == 1)
    wrongDraft = true
    requireStatus(try send("mismatch"), "failed")
    precondition(submits == 1 && draft == "错误正文")
    wrongDraft = false
    draft = ""
    lostReply = true
    requireStatus(try send("lost"), "status_unknown")
    requireStatus(try send("lost"), "status_unknown")
    requireStatus(try dispatch(["op": "receipt", "request_id": "lost"], stateDir: state.path), "status_unknown")
    precondition(submits == 2)

    let pixel = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1, bitsPerSample: 8,
                                 samplesPerPixel: 3, hasAlpha: false, isPlanar: false, colorSpaceName: .deviceRGB,
                                 bytesPerRow: 0, bitsPerPixel: 0)!
    pixel.setColor(.white, atX: 0, y: 0)
    let jpeg = pixel.representation(using: .jpeg, properties: [:])!
    let files = try (1...4).map { index -> URL in
        let url = state.appendingPathComponent("photo-\(index).jpg")
        try jpeg.write(to: url)
        return url
    }
    let board = NSPasteboard.withUniqueName()
    defer { board.releaseGlobally() }
    let item = NSPasteboardItem()
    let html = Data("<b>原内容</b>".utf8)
    precondition(item.setData(html, forType: .html) && item.setString("原内容", forType: .string))
    precondition(board.writeObjects([item]))
    try withFiles(files, on: board) {
        precondition((board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL])?.map(\.path) == files.map(\.path))
    }
    precondition(board.data(forType: .html) == html && board.string(forType: .string) == "原内容")
    try withFiles(files, on: board) {
        board.clearContents()
        precondition(board.setString("新内容", forType: .string))
    }
    precondition(board.string(forType: .string) == "新内容")
    let unsupported = NSPasteboard.PasteboardType("org.example.wechat-selftest")
    board.clearContents()
    precondition(board.setData(Data([1, 2, 3]), forType: unsupported))
    do {
        try withFiles(files, on: board) { preconditionFailure("unsupported clipboard type accepted") }
    } catch is Refused {
        precondition(board.data(forType: unsupported) == Data([1, 2, 3]))
    }

    for (id, count, expected) in [("photos", 4, "submitted_unconfirmed"), ("short-draft", 3, "failed"),
                                  ("same-history", 4, "status_unknown")] {
        var armed = false
        var calls: [String] = []
        var reads = 0
        var postSubmitReads = 0
        let result = try dispatch(["op": "send", "request_id": id, "recipient": "filehelper", "photos": files.map(\.path)],
                                  stateDir: state.path, target: { _ in view("") }, read: { _ in
            if calls == ["v"] {
                reads += 1
                // The first read may lag behind the paste; reject unrelated content immediately.
                let draft = count == 4 ? String(repeating: "\u{fffc}", count: reads == 1 ? 0 : 4) : "unrelated draft"
                return Chat(window: w, token: "s00000002:4", draft: draft,
                            messages: id == "same-history" ? ["图片"] : [], photoDraft: true, canSend: true)
            }
            postSubmitReads += 1
            return view("", id == "same-history" || postSubmitReads > 1 ? ["图片"] : [])
        }, act: { _, command in
            let key = (command["press_key"] as? JSONObject)?["key"] as? String ?? ""
            precondition((key == "v" && armed) || (key == "Return" && !armed))
            calls.append(key)
        }, paste: { staged, readDraft in
            precondition(staged == files.map { $0.resolvingSymlinksInPath() })
            armed = true
            defer { armed = false }
            return try readDraft()
        }, readbackWait: id == "same-history" ? 0 : 6)
        requireStatus(result, expected)
        precondition(calls == (count == 4 ? ["v", "Return"] : ["v"]))
        precondition((result["photos_submitted"] as? Int) == (expected == "submitted_unconfirmed" ? 4 : nil))
    }
    precondition(!usedDriver)
    print("self-test ok: target parsing, draft guard, single submit, conflict, unknown receipt, photo batch and count gate; no Cua actions")
}

umask(0o077)
if CommandLine.arguments.dropFirst().elementsEqual(["self-test"]) {
    try selfTest()
    exit(0)
}
let output: JSONObject
let input = FileHandle.standardInput.readData(ofLength: 1 << 20)
var code: Int32 = 0
var originalID: String?
do {
    let req = try object(input)
    originalID = req["request_id"] as? String
    output = try dispatch(req)
    if output["status"] as? String == "status_unknown" { code = 2 }
    else if output["status"] as? String == "failed" { code = 1 }
} catch {
    var failure: JSONObject = ["status": "failed", "diagnostic": (error as? Refused)?.reason ?? "sender failed; check the original receipt before reusing this request"]
    if let id = originalID, id.range(of: #"\A[A-Za-z0-9_-]{1,128}\z"#, options: .regularExpression) != nil { failure["request_id"] = id }
    output = failure
    code = 1
}
if usedDriver {
    do { _ = try cua("end_session") } catch { FileHandle.standardError.write(Data("could not end Cua session\n".utf8)) }
}
FileHandle.standardOutput.write(try json(output) + Data([10]))
exit(code)
