import Foundation

/// 监听一个目录的内容变化(新事件文件落入)。kqueue 对目录 fd 的 .write 会在增删子项时触发。
final class DirectoryWatcher: @unchecked Sendable {
    private let path: String
    private let onChange: @Sendable () -> Void
    private let queue = DispatchQueue(label: "cc-helper.dirwatcher")
    private var source: DispatchSourceFileSystemObject?
    private var fd: Int32 = -1

    init(path: String, onChange: @escaping @Sendable () -> Void) {
        self.path = path
        self.onChange = onChange
    }

    func start() { queue.async { [weak self] in self?.arm() } }
    func stop() { queue.async { [weak self] in self?.disarm() } }

    private func arm() {
        disarm()
        fd = open(path, O_EVTONLY)
        guard fd >= 0 else {
            queue.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.arm() }
            return
        }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .delete, .rename], queue: queue)
        src.setEventHandler { [weak self] in
            guard let self else { return }
            let flags = self.source?.data ?? []
            self.onChange()
            if flags.contains(.delete) || flags.contains(.rename) {
                self.queue.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.arm() }
            }
        }
        src.setCancelHandler { [weak self] in
            guard let self, self.fd >= 0 else { return }
            close(self.fd); self.fd = -1
        }
        source = src
        src.resume()
    }

    private func disarm() {
        source?.cancel()
        source = nil
    }

    deinit { disarm() }
}
