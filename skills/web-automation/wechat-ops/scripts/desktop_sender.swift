import AppKit
import CryptoKit
import Darwin
import ImageIO
import Vision

// Local Cua transport only. Never fall back to a different app or chat.
let mainBundle = "com.tencent.xinWeChat"
let legacyBundle = "com.tencent.xinWeChat.send"
let testBundle = "com.tencent.xinWeChat420Test"
let bundle = ProcessInfo.processInfo.environment["WECHAT_DESKTOP_BUNDLE_ID"] ?? mainBundle
func supportedBundle(_ id: String) -> Bool { id == mainBundle || id == legacyBundle || id == testBundle }
func receiptLocation(_ base: String?, for bundle: String) -> String? {
    guard let base, base.hasPrefix("/") else { return nil }
    // Old unscoped receipts belong to the legacy clone.
    return bundle == mainBundle ? URL(fileURLWithPath: base).appendingPathComponent("main", isDirectory: true).path : base
}
let helper = "文件传输助手"
let session = "wechat-desktop-\(UUID().uuidString)"
typealias JSONObject = [String: Any]
struct Refused: Error { let reason: String; init(_ reason: String) { self.reason = reason } }
struct RequestConflict: Error {}

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
    guard supportedBundle(bundle) else { throw Refused("unsupported WeChat bundle ID") }
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
        throw Refused("selected WeChat is unavailable, unverified, or frontmost")
    }
}
func snapshot(_ w: Window, capture: Bool = false) throws -> JSONObject {
    try requireBackground(w)
    let r = try cua("get_window_state", w.args.merging([
        "include_screenshot": capture, "max_image_dimension": 0,
        "tree_format": "both", "max_depth": 22, "max_elements": 300,
    ]) { _, b in b })
    // Recheck owner binding: a forked/recycled PID or stale snapshots must not redirect input.
    guard r["pid"] as? Int == w.pid, r["window_id"] as? Int == w.id,
          r["degraded_reason"] == nil, r["window_title"] as? String == w.title,
          r["elements"] is [JSONObject], r["tree_markdown"] is String else {
        throw Refused("selected WeChat window is not accessible in the background")
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
func filehelperLabels(_ r: JSONObject) -> [String]? {
    let rows = lines(r)
    guard let title = rows.onlyMatch(#"^\s*- \[([0-9]+)\] AXStaticText .*\[id=big_title_line_h_view "#),
          let list = rows.onlyMatch(#"^\s*- \[([0-9]+)\] AXList .*\[id=chat_message_list "#),
          let elements = r["elements"] as? [JSONObject],
          elements.contains(where: { $0["element_index"] as? Int == title && $0["role"] as? String == "AXStaticText" && $0["label"] as? String == helper }),
          elements.contains(where: { $0["element_index"] as? Int == list && $0["role"] as? String == "AXList" }) else { return nil }
    let messageIndexes = Set(rows.matches(#"^\s*- \[([0-9]+)\] AXStaticText .*\[id=chat_bubble_item_view "#))
    return elements.compactMap { row in
        guard let index = row["element_index"] as? Int, messageIndexes.contains(index),
              row["parent_index"] as? Int == list, row["role"] as? String == "AXStaticText" else { return nil }
        return row["label"] as? String
    }
}

func chat(_ w: Window, _ r: JSONObject) -> Chat? {
    let rows = lines(r)
    guard let messages = filehelperLabels(r),
          let editor = rows.onlyMatch(#"^\s*- \[([0-9]+)\] AXTextArea .*\[id=chat_input_field "#),
          let elements = r["elements"] as? [JSONObject],
          let input = elements.first(where: { $0["element_index"] as? Int == editor && $0["role"] as? String == "AXTextArea" }),
          let token = input["element_token"] as? String else { return nil }
    return Chat(window: w, token: token, draft: input["value"] as? String ?? "", messages: messages,
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
    guard r["truncated"] as? Bool == false, let entries = try? sessionEntries(r) else { return nil }
    let candidates = entries.filter { $0.name.utf8.elementsEqual(helper.utf8) }
    return candidates.count == 1 ? candidates[0].token : nil
}

func sessionSnapshot() throws -> JSONObject {
    let main = try windows().filter { $0.title == "微信" && $0.width >= 500 }
    guard main.count == 1 else { throw Refused("no unique accessible WeChat main window") }
    return try snapshot(main[0])
}

func readUnreadBadge(_ req: JSONObject, source: () throws -> JSONObject) throws -> JSONObject {
    guard Set(req.keys) == ["op"] else { throw Refused("unread_badge takes no parameters") }
    let state = try source()
    let rows = lines(state)
    guard state["truncated"] as? Bool == false,
          let root = rows.first,
          root.range(of: #"^- \[\d+\] AXWindow "微信" \["#, options: .regularExpression) != nil else {
        throw Refused("main window sidebar is not verifiable")
    }
    let sidebar = rows.dropFirst().prefix { $0.hasPrefix("  - AXButton ") }
    let prefix = #"  - AXButton "微信""#
    let buttons = sidebar.filter { $0 == prefix || $0.hasPrefix(prefix + " (") }
    guard buttons.count == 1, let button = buttons.first,
          sidebar.contains(#"  - AXButton "通讯录""#) else { throw Refused("chat sidebar button unavailable") }
    var badge: Any = NSNull()
    if button != prefix {
        let label = button.dropFirst(prefix.count)
        let pattern = #"^ \([0-9]{1,9}条新消息\)$"#
        guard label.range(of: pattern, options: .regularExpression) != nil,
              let count = Int(label.dropFirst(2).dropLast("条新消息)".count)) else {
            throw Refused("chat sidebar badge format is unknown")
        }
        badge = count
    }
    return ["status": "ok", "scope": "chat_sidebar_badge", "badge_count": badge, "complete_unread": false]
}

func readSessions(_ req: JSONObject, source: () throws -> JSONObject) throws -> JSONObject {
    let resolve = req["op"] as? String == "resolve"
    let allowed: Set<String> = resolve ? ["op", "hint", "limit"] : ["op", "limit"]
    guard Set(req.keys).isSubset(of: allowed),
          let limit = (req["limit"] ?? 20) as? NSNumber, CFGetTypeID(limit) != CFBooleanGetTypeID(),
          (1...100).contains(limit.intValue), limit.doubleValue == Double(limit.intValue) else {
        throw Refused("only an integer limit from 1 to 100 is supported for session queries")
    }
    let hint = req["hint"] as? String ?? ""
    if resolve && (hint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || hint.utf16.count > 2000) {
        throw Refused("resolve requires a nonempty exact name up to 2000 UTF-16 code units")
    }
    let snapshot = try source()
    let structured = try sessionEntries(snapshot).map(\.name)
    let names = structured.isEmpty ? displaySessionNames(snapshot) : structured
    guard !names.isEmpty else { throw Refused("session snapshot contains no verifiable rows") }
    var result: JSONObject = ["status": "ok", "scope": "session_list_ax_snapshot", "complete_sessions": false,
                              "snapshot_truncated": snapshot["truncated"] as? Bool ?? true, "scanned_count": names.count]
    if structured.isEmpty { result["session_source"] = "markdown_labels" }
    if resolve {
        let matches = names.filter { $0.utf8.elementsEqual(hint.utf8) }
        result["match_count"] = matches.count
        result["resolution"] = matches.isEmpty ? "not_found_in_snapshot" : (matches.count == 1 ? "unique_in_snapshot" : "ambiguous")
        result["candidates"] = matches.prefix(limit.intValue).map { ["name": $0] }
    } else {
        result["chats"] = names.prefix(limit.intValue).map { ["name": $0] }
    }
    return result
}

func sessionEntries(_ snapshot: JSONObject) throws -> [(name: String, token: String?)] {
    let rows = lines(snapshot)
    guard let list = rows.onlyMatch(#"^\s*- \[([0-9]+)\] AXList .*\[id=session_list "#),
          let elements = snapshot["elements"] as? [JSONObject],
          elements.contains(where: { $0["element_index"] as? Int == list && $0["role"] as? String == "AXList" }) else {
        throw Refused("session list is not uniquely identifiable")
    }
    let metadataEnd = #" actions=[press]"#
    return elements.compactMap { element -> (name: String, token: String?)? in
        guard element["parent_index"] as? Int == list, element["role"] as? String == "AXStaticText",
              let index = element["element_index"] as? Int,
              let name = (element["label"] as? String)?.components(separatedBy: "\n").first, !name.isEmpty,
              let start = rows.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("- [\(index)] AXStaticText ") }) else { return nil }
        let block = [rows[start]] + rows.dropFirst(start + 1).prefix { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("- [") }
        guard let tail = block.last, let marker = tail.range(of: " [id=session_item_\(name)\(metadataEnd)", options: [.literal, .backwards]),
              !tail[marker.upperBound...].contains("[id="), tail.hasSuffix("]") else { return nil }
        return (name, element["element_token"] as? String)
    }
}

// Display-only fallback for Cua rows without element indices or action metadata.
func displaySessionNames(_ snapshot: JSONObject) -> [String] {
    displayListLabels(snapshot, rootPattern: #"^ *- \[\d+\] AXList "会话" \[id=session_list "#)
}

func readViewLabels(_ req: JSONObject, source: () throws -> JSONObject) throws -> JSONObject {
    let moments = req["op"] as? String == "moments_labels"
    guard Set(req.keys).isSubset(of: ["op", "query", "limit"]),
          let limit = (req["limit"] ?? 20) as? NSNumber, CFGetTypeID(limit) != CFBooleanGetTypeID(),
          (1...100).contains(limit.intValue), limit.doubleValue == Double(limit.intValue),
          let query = (req["query"] ?? "") as? String, query.utf16.count <= 2000,
          query.isEmpty || !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw Refused("label reads require a literal query up to 2000 UTF-16 code units and a limit from 1 to 100")
    }
    let state = try source()
    let root = moments ? #"^ *- \[\d+\] AXList "朋友圈" \[id=sns_list "# : #"^ *- \[\d+\] AXList "通讯录" \[id=contact_list "#
    let labels = displayListLabels(state, rootPattern: root, multiline: moments)
    guard !labels.isEmpty else { throw Refused("requested list is not readable in the background") }
    let matches = labels.filter { query.isEmpty || $0.range(of: query, options: [.literal, .caseInsensitive]) != nil }
    return ["status": "ok", "scope": moments ? "moments_list_ax_labels" : "contact_list_ax_labels",
            (moments ? "complete_moments" : "complete_contacts"): false,
            "scanned_count": labels.count, "match_count": matches.count,
            "items": matches.prefix(limit.intValue).map { ["label": $0] }]
}

func displayListLabels(_ snapshot: JSONObject, rootPattern: String, multiline: Bool = false) -> [String] {
    guard snapshot["truncated"] as? Bool == false else { return [] }
    let rows = lines(snapshot)
    let roots = rows.indices.filter { rows[$0].range(of: rootPattern, options: .regularExpression) != nil }
    guard roots.count == 1, let root = roots.first else { return [] }
    let indent = rows[root].prefix(while: { $0 == " " }).count
    let node = String(repeating: " ", count: indent + 2) + #"- AXStaticText ""#
    var names: [String] = []
    var pending: String?
    for line in rows.dropFirst(root + 1) {
        if let name = pending {
            // A nested or sibling row cannot also be treated as the end of a label.
            guard !line.trimmingCharacters(in: .whitespaces).hasPrefix("- ") else { return [] }
            let closed = line.hasSuffix("\"")
            let fragment = closed ? String(line.dropLast()) : line
            guard !fragment.contains("\"") else { return [] }
            let label = multiline ? name + "\n" + fragment : name
            guard label.utf16.count <= (multiline ? 8000 : 2000) else { return [] }
            if closed {
                names.append(label)
                pending = nil
            } else {
                pending = label
            }
            continue
        }
        if line.hasPrefix(node) {
            let tail = line.dropFirst(node.count)
            let name = tail.hasSuffix("\"") ? tail.dropLast() : tail
            guard !name.contains("\""), !name.trimmingCharacters(in: .whitespaces).isEmpty,
                  name.utf16.count <= 2000 else { return [] }
            if tail.hasSuffix("\"") { names.append(String(name)) }
            else { pending = String(name) }
        } else if line.trimmingCharacters(in: .whitespaces).hasPrefix("- "),
                  line.prefix(while: { $0 == " " }).count <= indent {
            break
        } else if !line.isEmpty {
            return []
        }
    }
    return pending == nil ? names : []
}

func filehelperWindow() throws -> Window {
    let ws = try windows()
    let exact = ws.filter { $0.title == helper }
    let main = ws.filter { $0.title == "微信" && $0.width >= 500 }
    guard exact.count <= 1, let w = exact.first ?? (main.count == 1 ? main[0] : nil) else {
        throw Refused("no unique accessible WeChat chat window")
    }
    return w
}

func verifiedFilehelperLabels(_ state: JSONObject) throws -> [String] {
    guard state["truncated"] as? Bool == false, let labels = filehelperLabels(state) else {
        throw Refused("filehelper title or message list is not verifiable")
    }
    guard labels.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
        throw Refused("filehelper snapshot has no verifiable message labels")
    }
    return labels
}

func visibleFilehelperLabels() throws -> [String] {
    try verifiedFilehelperLabels(snapshot(filehelperWindow()))
}

private let sessionListPattern = #"^ *- \[([0-9]+)\] AXList "会话" \[id=session_list "#

func navigationSidebar(_ state: JSONObject) throws -> (row: JSONObject, names: [String]) {
    let names = displaySessionNames(state)
    guard !names.isEmpty, let index = lines(state).onlyMatch(sessionListPattern),
          let rows = state["elements"] as? [JSONObject],
          let row = rows.first(where: { $0["element_index"] as? Int == index && $0["role"] as? String == "AXList" }),
          row["element_token"] is String else { throw Refused("filehelper sidebar is not verifiable") }
    return (row, names)
}

func sidebarPixel(_ point: CGPoint, window: CGRect, sidebar: CGRect, width: Int, height: Int) -> CGPoint? {
    guard point.x > 0, point.x < 1, point.y > 0, point.y < 1,
          width > 0, height > 0, window.width > 0, window.height > 0,
          abs(Double(width) / Double(height) - window.width / window.height) < 0.015,
          window.contains(sidebar),
          sidebar.contains(CGPoint(x: window.minX + point.x * window.width,
                                   y: window.minY + point.y * window.height)) else { return nil }
    return CGPoint(x: point.x * Double(width), y: point.y * Double(height))
}

func visualFilehelperClick(_ state: JSONObject, sidebar: JSONObject) throws -> JSONObject {
    func rect(_ data: Any?, width: String, height: String) -> CGRect? {
        guard let d = data as? JSONObject, let x = d["x"] as? Double, let y = d["y"] as? Double,
              let w = d[width] as? Double, let h = d[height] as? Double, w > 0, h > 0 else { return nil }
        return CGRect(x: x, y: y, width: w, height: h)
    }
    guard state["screenshot_frame_valid"] as? Bool == true, let id = state["capture_id"] as? String,
          let window = rect(state["window_bounds"], width: "width", height: "height"),
          let list = rect(sidebar["frame"], width: "w", height: "h"),
          let encoded = state["screenshot_png_b64"] as? String, let data = Data(base64Encoded: encoded),
          let source = CGImageSourceCreateWithData(data as CFData, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
          state["screenshot_width"] as? Int == image.width, state["screenshot_height"] as? Int == image.height else {
        throw Refused("filehelper screenshot is not bound to the window")
    }
    let request = VNRecognizeTextRequest()
    request.recognitionLanguages = ["zh-Hans", "en-US"]
    try VNImageRequestHandler(cgImage: image).perform([request])
    let hits = try (request.results ?? []).flatMap { row -> [CGPoint] in
        guard let text = row.topCandidates(1).first else { return [] }
        var start = text.string.startIndex
        var points: [CGPoint] = []
        while let range = text.string.range(of: helper, range: start..<text.string.endIndex) {
            start = range.upperBound
            if let box = try text.boundingBox(for: range)?.boundingBox,
               let point = sidebarPixel(CGPoint(x: box.midX, y: 1 - box.midY), window: window,
                                        sidebar: list, width: image.width, height: image.height) {
                points.append(point)
            }
        }
        return points
    }
    guard hits.count == 1, let point = hits.first else { throw Refused("filehelper is not unique in the sidebar screenshot") }
    return ["click": ["x": point.x, "y": point.y, "count": 2, "capture_id": id]]
}

func navigateMainFilehelper(_ w: Window, from first: JSONObject) throws -> Chat {
    let initial = try navigationSidebar(first).names
    let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
    var state = first
    func step(_ command: JSONObject) throws {
        guard front != nil, NSWorkspace.shared.frontmostApplication?.processIdentifier == front else {
            throw Refused("foreground application changed; no further input dispatched")
        }
        try action(w, command)
    }
    func scroll(_ row: JSONObject, _ direction: String) throws {
        guard let token = row["element_token"] as? String else { throw Refused("filehelper sidebar token is unavailable") }
        try step(["scroll": ["element_token": token, "direction": direction, "amount": 6]])
        state = try snapshot(w)
    }
    func restore(_ moves: Int, _ direction: String) throws {
        guard moves > 0 else { return }
        state = try snapshot(w)
        for _ in 0..<moves {
            let page = try navigationSidebar(state)
            if page.names == initial { return }
            try scroll(page.row, direction)
        }
        guard try navigationSidebar(state).names == initial else { throw Refused("could not verify restoration of the sidebar") }
    }
    for (direction, reverse) in [("up", "down"), ("down", "up")] {
        var moves = 0
        var seen = Set<[String]>()
        do {
            while true {
                let page = try navigationSidebar(state)
                let matches = page.names.filter { $0 == helper }.count
                guard matches <= 1 else { throw Refused("filehelper is ambiguous in the sidebar") }
                if matches == 1 {
                    let fresh = try snapshot(w, capture: true)
                    let sidebar = try navigationSidebar(fresh)
                    guard sidebar.names == page.names else { throw Refused("sidebar changed before navigation") }
                    try step(visualFilehelperClick(fresh, sidebar: sidebar.row))
                    return try locate(navigate: false)
                }
                guard moves < 10, seen.insert(page.names).inserted else { break }
                moves += 1
                try scroll(page.row, direction)
            }
        } catch {
            do { try restore(moves, reverse) }
            catch { throw Refused("navigation stopped; sidebar restoration could not be verified") }
            throw error
        }
        try restore(moves, reverse)
    }
    throw Refused("filehelper was not uniquely located within the background scroll limit")
}

func locate(navigate: Bool) throws -> Chat {
    let w = try filehelperWindow()
    let r = try snapshot(w)
    if r["truncated"] as? Bool == false, let c = chat(w, r) { return c }
    guard navigate, w.title != helper else { throw Refused("filehelper is not selected or its window is not verifiable") }
    // Qt may open a separate chat window rather than change the main window.
    if let token = helperSessionToken(r) {
        try action(w, ["double_click": ["element_token": token]])
        return try locate(navigate: false)
    }
    guard bundle == mainBundle else { throw Refused("filehelper session row is not actionable") }
    return try navigateMainFilehelper(w, from: r)
}

private let restorableClipboardTypes: Set<String> = [
    "NSStringPboardType", "public.utf8-plain-text", "Apple HTML pasteboard type", "public.html",
]

func photoClipboardTypesSupported(_ pb: NSPasteboard) -> Bool {
    let before = pb.changeCount
    let supported = (pb.pasteboardItems ?? []).allSatisfy { item in
        item.types.allSatisfy { restorableClipboardTypes.contains($0.rawValue) }
    }
    return supported && pb.changeCount == before
}

func withFiles<T>(_ files: [URL], on pb: NSPasteboard = .general, _ body: () throws -> T) throws -> T {
    let old = pb.changeCount
    let previous = try (pb.pasteboardItems ?? []).map { item -> NSPasteboardItem in
        let saved = NSPasteboardItem()
        // Copy static text/HTML bytes; leave file promises and unknown formats alone.
        for type in item.types {
            guard restorableClipboardTypes.contains(type.rawValue),
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
func readVisible(_ req: JSONObject, labels: () throws -> [String]) throws -> JSONObject {
    guard req["recipient"] as? String == "filehelper" else { throw Refused("only filehelper is supported") }
    let op = req["op"] as? String
    var allowed: Set<String> = ["op", "recipient", "limit"]
    if op == "search" { allowed.insert("query") }
    if op == "export" { allowed.insert("format") }
    guard Set(req.keys).isSubset(of: allowed) else { throw Refused("unsupported visible-history parameter") }
    let format = req["format"] ?? "json"
    guard let format = format as? String, ["json", "markdown", "html", "csv"].contains(format) else {
        throw Refused("export format must be json, markdown, html or csv")
    }
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
    let visible = try labels()
    let selected = Array(visible.suffix(number.intValue))
    var result: JSONObject = ["status": "ok", "recipient": "filehelper", "scope": "visible_ax_labels",
                              "complete_history": false, "visible_count": visible.count, "scanned_count": selected.count]
    if op == "stats" {
        result["label_frequencies"] = Dictionary(grouping: selected, by: { $0 }).values.map(\.count).sorted(by: >)
        result["distinct_label_count"] = Set(selected).count
    } else {
        let matches = query.map { q in selected.filter { $0.range(of: q, options: [.caseInsensitive, .literal]) != nil } } ?? selected
        result["match_count"] = matches.count
        if op == "export", format == "markdown" {
            let body = matches.joined(separator: "\n\n")
            let longest = body.split(whereSeparator: { $0 != "`" }).map(\.count).max() ?? 0
            let fence = String(repeating: "`", count: max(3, longest + 1))
            result["format"] = format
            result["markdown"] = "# 文件传输助手：可见消息快照（非完整历史）\n\n\(fence)text\n\(body)\n\(fence)\n"
        } else if op == "export", format == "html" {
            let rows = matches.map { label in
                let escaped = label.replacingOccurrences(of: "&", with: "&amp;")
                    .replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
                return "<li>\(escaped)</li>"
            }
            result["format"] = format
            result["html"] = "<!doctype html><html lang=\"zh-Hans\"><meta charset=\"utf-8\"><title>文件传输助手：可见消息快照</title><h1>可见消息快照（非完整历史）</h1><ol>\(rows.joined())</ol></html>"
        } else if op == "export", format == "csv" {
            let rows = matches.map { label in
                // Quoting alone does not prevent a spreadsheet from evaluating a cell as a formula.
                let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
                let prefix = trimmed.first.map { "=+-@＝＋－＠".contains($0) } == true || label.hasPrefix("\t") || label.hasPrefix("\r") || label.hasPrefix("\n") ? "'" : ""
                return "\"\(prefix)\(label.replacingOccurrences(of: "\"", with: "\"\""))\"\r\n"
            }
            result["format"] = format
            result["csv"] = "label\r\n" + rows.joined()
        } else {
            if op == "export" { result["format"] = format }
            result["items"] = matches.map { ["label": $0] }
        }
    }
    return result
}

func dispatch(_ req: JSONObject,
              stateDir: String? = receiptLocation(ProcessInfo.processInfo.environment["WECHAT_DESKTOP_STATE_DIR"], for: bundle),
              target: (Bool) throws -> Chat = { try locate(navigate: $0) },
              read: @escaping (Window) throws -> Chat = { w in
                  guard let state = chat(w, try snapshot(w)) else { throw Refused("filehelper identity could not be verified") }
                  return state
              },
              act: @escaping (Window, JSONObject) throws -> Void = { try action($0, $1) },
              paste: ([URL], () throws -> Chat) throws -> Chat = { try withFiles($0, $1) },
              clipboard: () -> Bool = { photoClipboardTypesSupported(.general) },
              sessions: () throws -> JSONObject = sessionSnapshot,
              historyLabels: () throws -> [String] = visibleFilehelperLabels,
              draftWait: TimeInterval = 4, readbackWait: TimeInterval = 6) throws -> JSONObject {
    switch req["op"] as? String {
    case "readiness":
        guard Set(req.keys) == ["op"] else { throw Refused("readiness takes no parameters") }
        let state = try? sessions()
        let chats = state.flatMap { state in try? readSessions(["op": "chats", "limit": 1], source: { state }) }
        let contacts = state.flatMap { state in try? readViewLabels(["op": "contact_labels", "limit": 1], source: { state }) }
        let moments = state.flatMap { state in try? readViewLabels(["op": "moments_labels", "limit": 1], source: { state }) }
        let badge = state.flatMap { state in try? readUnreadBadge(["op": "unread_badge"], source: { state }) }
        return ["status": "ok", "scope": "desktop_snapshot_readiness", "bundle_id": bundle,
                "main_window_readable": state != nil, "sessions_readable": chats != nil,
                "contacts_labels_readable": contacts != nil, "moments_labels_readable": moments != nil,
                "unread_badge_readable": badge != nil, "positive_unread_badge": (badge?["badge_count"] as? Int ?? 0) > 0,
                "filehelper_readable": (try? historyLabels()) != nil, "live_wechat": false, "sent": false]
    case "open_filehelper":
        guard Set(req.keys) == ["op"], bundle == mainBundle else {
            throw Refused("open_filehelper takes no parameters and requires the main WeChat client")
        }
        _ = try target(true)
        return ["status": "ok", "recipient": "filehelper", "sent": false]
    case "probe":
        let c = try target(false)
        return ["status": "target_matched", "recipient": "filehelper", "draft_empty": c.draft.isEmpty,
                "photo_clipboard_types_supported": clipboard()]
    case "history", "search", "stats", "export":
        return try readVisible(req, labels: historyLabels)
    case "chats", "resolve":
        return try readSessions(req, source: sessions)
    case "unread_badge":
        return try readUnreadBadge(req, source: sessions)
    case "contact_labels", "moments_labels":
        return try readViewLabels(req, source: sessions)
    case "send", "receipt": break
    default: throw Refused("op must be open_filehelper, probe, chats, resolve, unread_badge, contact_labels, moments_labels, history, search, stats, export, send or receipt")
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
        var value = try object(Data(contentsOf: receipt))
        value.removeValue(forKey: "fingerprint")
        value["receipt_recorded"] = true
        return value
    }
    let lock = open(dir.appendingPathComponent("sender.lock").path, O_WRONLY | O_CREAT | O_NOFOLLOW, 0o600)
    guard lock >= 0 else { throw Refused("could not open sender lock") }
    defer { close(lock) }
    guard flock(lock, LOCK_EX | LOCK_NB) == 0 else {
        return ["status": "status_unknown", "request_id": id,
                "diagnostic": "sender lock unavailable; query the original receipt, do not replay this request"]
    }
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
        guard prior.removeValue(forKey: "fingerprint") as? String == fingerprint else { throw RequestConflict() }
        prior["receipt_recorded"] = true
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
        row["prepare_ms"] = Int((beforeSubmit - start) * 1000)
        defer {
            row["submit_and_readback_ms"] = Int((ProcessInfo.processInfo.systemUptime - beforeSubmit) * 1000)
            row["same_frontmost_sample"] = frontBefore != nil && frontBefore == NSWorkspace.shared.frontmostApplication?.processIdentifier
        }
        try act(w, ["press_key": ["element_token": staged.token, "key": "Return"]])
        let tracked = text ?? "图片"
        let previousCount = staged.messages.filter { $0 == tracked }.count
        let deadline = beforeSubmit + readbackWait
        while true {
            let after = try read(w)
            let delta = after.messages.filter { $0 == tracked }.count - previousCount
            row["draft_empty_after_submit"] = after.draft.isEmpty
            row["visible_matching_rows_delta"] = delta
            if after.draft.isEmpty && delta > 0 { break }
            guard (after.draft == staged.draft || after.draft.isEmpty),
                  ProcessInfo.processInfo.systemUptime < deadline else {
                throw Refused("no distinct new sender-side message verified; do not replay this request")
            }
            // The send may finish after the key returns. Only poll reads, never replay Return.
            Thread.sleep(forTimeInterval: 0.15)
        }
        row["status"] = "submitted_unconfirmed"
        row["diagnostic"] = "draft cleared and new matching sender-side message rows appeared; recipient delivery not verified"
        if !files.isEmpty { row["photos_submitted"] = files.count }
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
    row["receipt_recorded"] = true
    return row
}

func selfTest() throws {
    precondition(supportedBundle(mainBundle) && supportedBundle(legacyBundle) && supportedBundle(testBundle))
    precondition(!supportedBundle("com.tencent.xinWeChat.unverified"))
    precondition(receiptLocation("/state", for: mainBundle) == "/state/main")
    precondition(receiptLocation("/state", for: legacyBundle) == "/state")
    precondition(receiptLocation("state", for: mainBundle) == nil)
    let state = FileManager.default.temporaryDirectory.appendingPathComponent("wechat-sender-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: state, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    defer { try! FileManager.default.removeItem(at: state) }
    let w = Window(pid: 123, id: 42, title: helper, width: 598)
    let fixture: JSONObject = [
        "tree_markdown": "- [1] AXStaticText = \"文件传输助手\" [id=big_title_line_h_view actions=[raise]]\n- [4] AXTextArea \"输入\" [id=chat_input_field actions=[raise]]\n- [5] AXList \"消息\" [id=chat_message_list actions=[raise]]\n  - [6] AXStaticText \"你好\" [id=chat_bubble_item_view actions=[press]]\n- [7] AXStaticText \"文件传输助手\n图片\n14:44\" [id=session_item_文件传输助手 actions=[press]]\n- [8] AXStaticText \"不属于当前会话\" [id=chat_bubble_item_view actions=[press]]",
        "elements": [["element_index": 1, "role": "AXStaticText", "label": helper],
                     ["element_index": 4, "role": "AXTextArea", "element_token": "s00000001:4"],
                     ["element_index": 5, "role": "AXList"],
                     ["element_index": 6, "role": "AXStaticText", "label": "你好", "parent_index": 5],
                     ["element_index": 7, "role": "AXStaticText", "label": "文件传输助手\n图片\n14:44", "element_token": "s00000001:7"],
                     ["element_index": 8, "role": "AXStaticText", "label": "不属于当前会话", "parent_index": 0]]
    ]
    precondition(chat(w, fixture)?.messages == ["你好"])
    let readOnly = fixture.merging([
        "tree_markdown": lines(fixture).filter { !$0.contains("id=chat_input_field ") }.joined(separator: "\n"),
        "elements": (fixture["elements"] as! [JSONObject]).filter { $0["element_index"] as? Int != 4 }
    ]) { _, new in new }
    precondition(filehelperLabels(readOnly) == ["你好"] && chat(w, readOnly) == nil)
    let completeReadOnly = readOnly.merging(["truncated": false]) { _, new in new }
    let verifiedLabels = try verifiedFilehelperLabels(completeReadOnly)
    precondition(verifiedLabels == ["你好"])
    let noLabels = completeReadOnly.merging(["elements": (completeReadOnly["elements"] as! [JSONObject]).filter {
        $0["parent_index"] as? Int != 5
    }]) { _, new in new }
    for unavailable in [noLabels, completeReadOnly.merging(["truncated": true]) { _, new in new }] {
        do {
            _ = try verifiedFilehelperLabels(unavailable)
            preconditionFailure("unobservable history was reported as empty")
        } catch is Refused {}
    }
    let wrongChat = readOnly.merging(["elements": (readOnly["elements"] as! [JSONObject]).map { row in
        row["element_index"] as? Int == 1 ? row.merging(["label": "其他会话"]) { _, new in new } : row
    }]) { _, new in new }
    precondition(filehelperLabels(wrongChat) == nil)
    let readOnlyResult = try dispatch(["op": "history", "recipient": "filehelper"],
                                      target: { _ in preconditionFailure("history reached the sender") },
                                      historyLabels: { filehelperLabels(readOnly)! })
    precondition(readOnlyResult["items"] as? [[String: String]] == [["label": "你好"]])
    var ambiguousList = fixture
    ambiguousList["tree_markdown"] = (fixture["tree_markdown"] as! String) + "\n- [9] AXList [id=chat_message_list actions=[raise]]"
    precondition(chat(w, ambiguousList) == nil)
    precondition(helperSessionToken(fixture) == nil) // A matching label outside the session list cannot authorize navigation.
    precondition(helperSessionToken(fixture.merging(["tree_markdown": "- [7] AXStaticText \"文件传输助手\" [id=session_item_other actions=[press]]"]) { _, new in new }) == nil)
    let listFixture: JSONObject = [
        "tree_markdown": """
        - [10] AXList "会话" [id=session_list actions=[raise]]
          - [11] AXStaticText "测试群
        私人预览" [id=session_item_测试群 actions=[press]]
          - [12] AXStaticText "测试群" [id=session_item_测试群 actions=[press]]
          - [13] AXStaticText "文件传输助手" [id=session_item_文件传输助手 actions=[press]]
        - [14] AXStaticText "无关窗口" [id=session_item_无关窗口 actions=[press]]
        """,
        "truncated": false,
        "elements": [["element_index": 10, "role": "AXList"],
                     ["element_index": 11, "parent_index": 10, "role": "AXStaticText", "label": "测试群\n私人预览"],
                     ["element_index": 12, "parent_index": 10, "role": "AXStaticText", "label": "测试群"],
                     ["element_index": 13, "parent_index": 10, "role": "AXStaticText", "label": helper, "element_token": "s00000001:13"],
                     ["element_index": 14, "parent_index": 0, "role": "AXStaticText", "label": "无关窗口"]]
    ]
    precondition(helperSessionToken(listFixture) == "s00000001:13")
    precondition(helperSessionToken(listFixture.merging(["truncated": true]) { _, new in new }) == nil)
    var duplicateHelper = listFixture
    duplicateHelper["tree_markdown"] = (listFixture["tree_markdown"] as! String) + "\n  - [15] AXStaticText \"文件传输助手\" [id=session_item_文件传输助手 actions=[press]]"
    duplicateHelper["elements"] = (listFixture["elements"] as! [JSONObject]) + [["element_index": 15, "parent_index": 10, "role": "AXStaticText", "label": helper, "element_token": "s00000001:15"]]
    precondition(helperSessionToken(duplicateHelper) == nil)
    let sessionList = try dispatch(["op": "chats", "limit": 2], sessions: { listFixture })
    precondition(sessionList["chats"] as? [[String: String]] == [["name": "测试群"], ["name": "测试群"]])
    precondition(sessionList["scanned_count"] as? Int == 3 && sessionList["complete_sessions"] as? Bool == false)
    let emptyList = listFixture.merging(["elements": [["element_index": 10, "role": "AXList"]]]) { _, new in new }
    for request: JSONObject in [["op": "chats"], ["op": "resolve", "hint": helper]] {
        do {
            _ = try dispatch(request, sessions: { emptyList })
            preconditionFailure("unobservable rows were reported as an empty session list")
        } catch is Refused {}
    }
    let displayOnly = emptyList.merging(["tree_markdown": """
    - [10] AXList "会话" [id=session_list actions=[raise]]
      - AXStaticText "测试会话
    私人预览"
      - AXStaticText "文件传输助手"
    - AXStaticText "列表外内容"
    """]) { _, new in new }
    let badgeTree = """
    - [0] AXWindow "微信" [actions=[raise]]
      - AXButton "微信" (123条新消息)
      - AXButton "通讯录"
      - AXButton "发现" (1条新消息)
      - [12] AXList "会话" [id=session_list actions=[raise]]
        - AXButton "微信" (9条新消息)
    """
    func badge(_ tree: String) throws -> JSONObject {
        try dispatch(["op": "unread_badge"], sessions: { ["tree_markdown": tree, "truncated": false] })
    }
    let positiveBadge = try badge(badgeTree)
    precondition(positiveBadge["badge_count"] as? Int == 123 && positiveBadge["complete_unread"] as? Bool == false)
    let noBadge = try badge(badgeTree.replacingOccurrences(of: " (123条新消息)", with: ""))
    precondition(noBadge["badge_count"] is NSNull)
    for invalid in ["99+", "-1"] {
        do {
            _ = try badge(badgeTree.replacingOccurrences(of: "123", with: invalid))
            preconditionFailure("unsupported badge format accepted")
        } catch is Refused {}
    }
    let readiness = try dispatch(["op": "readiness"],
                                 sessions: { listFixture }, historyLabels: { throw Refused("filehelper is not selected") })
    precondition(readiness["main_window_readable"] as? Bool == true && readiness["sessions_readable"] as? Bool == true)
    precondition(readiness["filehelper_readable"] as? Bool == false && readiness["live_wechat"] as? Bool == false)
    precondition(readiness["chats"] == nil && readiness["items"] == nil)
    let blockedReadiness = try dispatch(["op": "readiness"],
                                        sessions: { throw Refused("no verified main window") },
                                        historyLabels: { throw Refused("no verified chat") })
    precondition(blockedReadiness["main_window_readable"] as? Bool == false && blockedReadiness["sessions_readable"] as? Bool == false)
    let displayList = try dispatch(["op": "chats"], sessions: { displayOnly })
    precondition(displayList["session_source"] as? String == "markdown_labels")
    precondition(displayList["chats"] as? [[String: String]] == [["name": "测试会话"], ["name": helper]])
    let displayMatch = try dispatch(["op": "resolve", "hint": helper], sessions: { displayOnly })
    precondition(displayMatch["match_count"] as? Int == 1 && helperSessionToken(displayOnly) == nil)
    let sidebarState = displayOnly.merging(["elements": [["element_index": 10, "role": "AXList", "element_token": "s00000001:10"]]]) { _, new in new }
    let sidebar = try navigationSidebar(sidebarState)
    precondition(sidebar.names == ["测试会话", helper] && sidebar.row["element_token"] as? String == "s00000001:10")
    let windowRect = CGRect(x: 66, y: 30, width: 946, height: 848)
    let sidebarRect = CGRect(x: 126, y: 82, width: 216, height: 792)
    precondition(sidebarPixel(CGPoint(x: 0.25, y: 0.5), window: windowRect, sidebar: sidebarRect, width: 1892, height: 1696) == CGPoint(x: 473, y: 848))
    precondition(sidebarPixel(CGPoint(x: 0.5, y: 0.5), window: windowRect, sidebar: sidebarRect, width: 1892, height: 1696) == nil)
    precondition(sidebarPixel(CGPoint(x: 0.25, y: 0.5), window: windowRect, sidebar: sidebarRect, width: 946, height: 1696) == nil)
    precondition(displaySessionNames(displayOnly.merging(["truncated": true]) { _, new in new }).isEmpty)
    precondition(displaySessionNames(displayOnly.merging(["tree_markdown": """
    - [10] AXList "会话" [id=session_list actions=[raise]]
      - AXStaticText "未闭合
      - AXStaticText "文件传输助手"
    """]) { _, new in new }).isEmpty)
    let contacts: JSONObject = ["truncated": false, "tree_markdown": """
    - [10] AXList "通讯录" [id=contact_list actions=[raise]]
      - AXStaticText "Alpha"
      - AXStaticText "beta"
    - AXStaticText "Alpha Outside"
    """]
    let contactMatch = try dispatch(["op": "contact_labels", "query": "alp", "limit": 1], sessions: { contacts })
    precondition(contactMatch["items"] as? [[String: String]] == [["label": "Alpha"]])
    precondition(contactMatch["match_count"] as? Int == 1 && contactMatch["scanned_count"] as? Int == 2)
    let contactMiss = try dispatch(["op": "contact_labels", "query": "absent"], sessions: { contacts })
    precondition(contactMiss["match_count"] as? Int == 0 && contactMiss["complete_contacts"] as? Bool == false)
    let momentsFixture: JSONObject = ["truncated": false, "tree_markdown": """
    - [10] AXList "朋友圈" [id=sns_list actions=[raise]]
      - AXStaticText "首行
    第二行"
    - AXStaticText "第二行 列表外"
    """]
    let momentsMatch = try dispatch(["op": "moments_labels", "query": "第二行"], sessions: { momentsFixture })
    precondition(momentsMatch["items"] as? [[String: String]] == [["label": "首行\n第二行"]])
    precondition(momentsMatch["match_count"] as? Int == 1 && momentsMatch["complete_moments"] as? Bool == false)
    for invalidContactSource in [displayOnly, contacts.merging(["truncated": true]) { _, new in new }] {
        do {
            _ = try dispatch(["op": "contact_labels"], sessions: { invalidContactSource })
            preconditionFailure("unavailable contact list accepted")
        } catch is Refused {}
    }
    for (hint, resolution, count) in [("测试群", "ambiguous", 2), (helper, "unique_in_snapshot", 1),
                                       ("测试", "not_found_in_snapshot", 0), ("无关窗口", "not_found_in_snapshot", 0)] {
        let resolved = try dispatch(["op": "resolve", "hint": hint, "limit": 1], sessions: { listFixture })
        precondition(resolved["resolution"] as? String == resolution && resolved["match_count"] as? Int == count)
        precondition((resolved["candidates"] as? [[String: String]])?.count == min(count, 1))
    }
    for invalid: JSONObject in [["op": "chats", "limit": true], ["op": "resolve", "hint": " "]] {
        do {
            _ = try dispatch(invalid, sessions: { preconditionFailure("invalid query reached the session reader") })
            preconditionFailure("invalid session query accepted")
        } catch is Refused {}
    }
    func view(_ draft: String, _ messages: [String] = []) -> Chat {
        Chat(window: w, token: "s00000001:4", draft: draft, messages: messages, photoDraft: false, canSend: !draft.isEmpty)
    }
    let recent: (Bool) throws -> Chat = { navigate in
        precondition(!navigate, "read-only operations must not navigate")
        return view("", ["旧消息", "Alpha 123", "图片", "图片"])
    }
    let recentLabels = { ["旧消息", "Alpha 123", "图片", "图片"] }
    let history = try dispatch(["op": "history", "recipient": "filehelper", "limit": 3], historyLabels: recentLabels)
    precondition((history["items"] as? [[String: String]])?.compactMap { $0["label"] } == ["Alpha 123", "图片", "图片"])
    precondition(history["complete_history"] as? Bool == false && history["visible_count"] as? Int == 4)
    let hits = try dispatch(["op": "search", "recipient": "filehelper", "query": "alpha"], historyLabels: recentLabels)
    precondition(hits["match_count"] as? Int == 1 && hits["scanned_count"] as? Int == 4)
    let missed = try dispatch(["op": "search", "recipient": "filehelper", "query": "Alpha", "limit": 2], historyLabels: recentLabels)
    precondition(missed["match_count"] as? Int == 0 && missed["scanned_count"] as? Int == 2)
    let counts = try dispatch(["op": "stats", "recipient": "filehelper", "limit": 3], historyLabels: recentLabels)
    precondition(counts["label_frequencies"] as? [Int] == [2, 1] && counts["distinct_label_count"] as? Int == 2 && counts["items"] == nil)
    let exported = try dispatch(["op": "export", "recipient": "filehelper", "limit": 3], historyLabels: recentLabels)
    precondition(exported["format"] as? String == "json" && exported["items"] as? [[String: String]] == history["items"] as? [[String: String]])
    let markdown = try dispatch(["op": "export", "recipient": "filehelper", "format": "markdown"], historyLabels: {
        ["```", "<script>data</script>"]
    })
    precondition((markdown["markdown"] as? String)?.contains("\n````text\n```\n\n<script>data</script>\n````\n") == true)
    let htmlExport = try dispatch(["op": "export", "recipient": "filehelper", "format": "html"], historyLabels: {
        ["<script>x</script>&", "普通"]
    })
    precondition((htmlExport["html"] as? String)?.contains("<li>&lt;script&gt;x&lt;/script&gt;&amp;</li><li>普通</li>") == true)
    let csv = try dispatch(["op": "export", "recipient": "filehelper", "format": "csv"], historyLabels: {
        [" =1+2", "a,\"b\"\n下一行", "\t文本"]
    })
    precondition(csv["csv"] as? String == "label\r\n\"' =1+2\"\r\n\"a,\"\"b\"\"\n下一行\"\r\n\"'\t文本\"\r\n")
    for invalid: JSONObject in [["op": "export", "recipient": "filehelper", "format": "pdf"],
                                 ["op": "history", "recipient": "other"], ["op": "history", "recipient": "filehelper", "limit": true],
                                 ["op": "stats", "recipient": "filehelper", "limit": 101], ["op": "search", "recipient": "filehelper", "query": "  "],
                                 ["op": "history", "recipient": "filehelper", "since": "today"]] {
        do {
            _ = try dispatch(invalid, historyLabels: { preconditionFailure("invalid input reached the reader") })
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
    do {
        let held = open(state.appendingPathComponent("sender.lock").path, O_WRONLY | O_NOFOLLOW)
        precondition(held >= 0)
        defer { close(held) }
        precondition(flock(held, LOCK_EX | LOCK_NB) == 0)
        requireStatus(try send("once"), "status_unknown")
        requireStatus(try dispatch(["op": "receipt", "request_id": "once"], stateDir: state.path), "submitted_unconfirmed")
    }
    do { _ = try send("once", text: "不同正文"); preconditionFailure("request conflict accepted") } catch is RequestConflict {}
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
    let beforeProbe = board.changeCount
    let photoProbe = try dispatch(["op": "probe"], target: recent, clipboard: { photoClipboardTypesSupported(board) })
    precondition(photoProbe["photo_clipboard_types_supported"] as? Bool == true && board.changeCount == beforeProbe)
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
    let unsupportedCount = board.changeCount
    let blockedProbe = try dispatch(["op": "probe"], target: recent, clipboard: { photoClipboardTypesSupported(board) })
    precondition(blockedProbe["photo_clipboard_types_supported"] as? Bool == false && board.changeCount == unsupportedCount)
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
        if count == 4 {
            precondition(result["draft_empty_after_submit"] as? Bool == true)
            precondition(result["visible_matching_rows_delta"] as? Int == (id == "same-history" ? 0 : 1))
            precondition(result["prepare_ms"] is Int && result["submit_and_readback_ms"] is Int)
        } else {
            precondition(result["draft_empty_after_submit"] == nil && result["prepare_ms"] == nil)
        }
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
    guard supportedBundle(bundle) else { throw Refused("unsupported WeChat bundle ID") }
    if bundle == testBundle, let op = req["op"] as? String, op == "send" || op == "receipt" {
        throw Refused("the 4.2.0 test clone is read-only; use the original clone and state directory for existing receipts")
    }
    output = try dispatch(req)
    if output["status"] as? String == "status_unknown" { code = 2 }
    else if output["status"] as? String == "failed" { code = 1 }
} catch {
    var failure: JSONObject = ["status": "failed", "diagnostic": (error as? Refused)?.reason ?? "sender failed; check the original receipt before reusing this request"]
    if error is RequestConflict {
        failure["diagnostic"] = "request_id already used for different contents"
        failure["error_code"] = "request_conflict"
    }
    if let id = originalID, id.range(of: #"\A[A-Za-z0-9_-]{1,128}\z"#, options: .regularExpression) != nil { failure["request_id"] = id }
    output = failure
    code = 1
}
if usedDriver {
    do { _ = try cua("end_session") } catch { FileHandle.standardError.write(Data("could not end Cua session\n".utf8)) }
}
FileHandle.standardOutput.write(try json(output) + Data([10]))
exit(code)
