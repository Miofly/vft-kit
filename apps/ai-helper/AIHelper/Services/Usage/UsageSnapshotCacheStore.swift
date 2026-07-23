import Foundation

enum UsageSnapshotCacheStore {
    static let defaultDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".ai-helper", isDirectory: true)
        .appendingPathComponent("cache", isDirectory: true)

    private static let claudeFileName = "claude-usage.json"
    private static let codexFileName = "codex-usage.json"

    static func loadClaude(from directoryURL: URL = defaultDirectoryURL) -> ClaudeUsageSnapshot? {
        load(ClaudeUsageSnapshot.self, from: directoryURL.appendingPathComponent(claudeFileName))
    }

    static func saveClaude(_ snapshot: ClaudeUsageSnapshot, to directoryURL: URL = defaultDirectoryURL) {
        save(snapshot, to: directoryURL.appendingPathComponent(claudeFileName))
    }

    static func loadCodex(from directoryURL: URL = defaultDirectoryURL) -> CodexUsageSnapshot? {
        load(CodexUsageSnapshot.self, from: directoryURL.appendingPathComponent(codexFileName))
    }

    static func saveCodex(_ snapshot: CodexUsageSnapshot, to directoryURL: URL = defaultDirectoryURL) {
        save(snapshot, to: directoryURL.appendingPathComponent(codexFileName))
    }

    private static func load<T: Decodable>(_ type: T.Type, from fileURL: URL) -> T? {
        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }

        return try? JSONDecoder().decode(type, from: data)
    }

    private static func save<T: Encodable>(_ value: T, to fileURL: URL) {
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        guard let data = try? JSONEncoder().encode(value) else {
            return
        }

        try? data.write(to: fileURL, options: .atomic)
    }
}
