//
//  RuntimeSupportPaths.swift
//  AIHelper
//
//  Native runtime storage paths isolated from the legacy implementation.
//

import Foundation

enum RuntimeSupportPaths {
    nonisolated static let directoryName = "AIHelper/native-runtime"

    nonisolated static var rootDirectoryURL: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent(directoryName, isDirectory: true)
            ?? URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support/\(directoryName)", isDirectory: true)
    }

    nonisolated static var sessionsFileURL: URL {
        rootDirectoryURL.appendingPathComponent("runtime-sessions.json", isDirectory: false)
    }
}
