import Foundation

public final class FileWatcher: @unchecked Sendable {
    private let path: String
    private let onChange: @Sendable () -> Void
    private let queue = DispatchQueue(label: "cc-notch-usage.filewatcher")
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1

    public init(path: String, onChange: @escaping @Sendable () -> Void) {
        self.path = path
        self.onChange = onChange
    }

    public func start() {
        queue.async { [weak self] in self?.arm() }
    }

    public func stop() {
        queue.async { [weak self] in self?.disarm() }
    }

    private func arm() {
        disarm()
        fileDescriptor = open(path, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            // 文件还不存在:0.5s 后重试挂载
            queue.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.arm() }
            return
        }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .extend, .delete, .rename],
            queue: queue
        )
        src.setEventHandler { [weak self] in
            guard let self else { return }
            let flags = self.source?.data ?? []
            self.onChange()
            // 原子替换会触发 delete/rename,旧 fd 失效,需重新挂载
            if flags.contains(.delete) || flags.contains(.rename) {
                self.queue.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.arm() }
            }
        }
        src.setCancelHandler { [weak self] in
            guard let self, self.fileDescriptor >= 0 else { return }
            close(self.fileDescriptor)
            self.fileDescriptor = -1
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
