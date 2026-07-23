//
//  RecentInterventionResponseStore.swift
//  AIHelper
//
//  Caches very recent inline answers so duplicate hook retries can be auto-resolved.
//

import Foundation

struct RecentInterventionResponse: Sendable {
    let decision: String
    let reason: String?
    let updatedInput: [String: AnyCodable]?
    let cachedAt: Date
}

struct RecentInterventionResponseStore {
    private let ttl: TimeInterval
    private var responses: [String: RecentInterventionResponse] = [:]

    init(ttl: TimeInterval = 30) {
        self.ttl = ttl
    }

    mutating func record(
        event: HookEvent,
        decision: String,
        reason: String?,
        updatedInput: [String: AnyCodable]?,
        now: Date = Date()
    ) {
        guard decision == "answer", Self.shouldStoreAnswerReplay(for: event) else {
            return
        }

        prune(now: now)
        guard let key = Self.cacheKey(for: event, updatedInput: updatedInput) else { return }
        responses[key] = RecentInterventionResponse(
            decision: decision,
            reason: reason,
            updatedInput: updatedInput,
            cachedAt: now
        )
    }

    mutating func response(for event: HookEvent, now: Date = Date()) -> RecentInterventionResponse? {
        prune(now: now)
        guard Self.shouldReplayAnswer(for: event) else { return nil }
        guard let key = Self.cacheKey(for: event) else { return nil }
        return responses[key]
    }

    mutating func prune(now: Date = Date()) {
        responses = responses.filter { _, response in
            now.timeIntervalSince(response.cachedAt) <= ttl
        }
    }

    static func cacheKey(for event: HookEvent) -> String? {
        cacheKey(for: event, updatedInput: nil)
    }

    private static func cacheKey(for event: HookEvent, updatedInput: [String: AnyCodable]?) -> String? {
        guard shouldStoreAnswerReplay(for: event) else {
            return nil
        }

        let normalizedTool = event.tool?
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
        let effectiveTool = normalizedTool ?? (isCodeBuddyCLIQuestionNotification(event) ? "askuserquestion" : nil)
        guard effectiveTool == "askuserquestion" else { return nil }
        guard let signature = questionSignature(from: event.toolInput)
            ?? questionSignature(from: updatedInput),
              !signature.isEmpty else { return nil }

        return ([event.sessionId, effectiveTool ?? "askuserquestion"] + signature).joined(separator: "||")
    }

    private static func shouldStoreAnswerReplay(for event: HookEvent) -> Bool {
        if isCodeBuddyCLIQuestionNotification(event) {
            return true
        }

        if event.clientInfo.profileID == "qoderwork" || event.clientInfo.bundleIdentifier == "com.qoder.work" {
            return true
        }

        let normalizedTool = event.tool?
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
        let profileID = event.clientInfo.profileID?.lowercased()
        let bundleIdentifier = event.clientInfo.bundleIdentifier?.lowercased()
        let isPlainClaudeCode = profileID != "qoder"
            && profileID != "qoderwork"
            && bundleIdentifier != "com.qoder.ide"
            && bundleIdentifier != "com.qoder.work"
        return event.provider == .claude && normalizedTool == "askuserquestion" && isPlainClaudeCode
    }

    private static func shouldReplayAnswer(for event: HookEvent) -> Bool {
        if event.clientInfo.profileID == "qoderwork" || event.clientInfo.bundleIdentifier == "com.qoder.work" {
            return true
        }

        let normalizedTool = event.tool?
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
        let profileID = event.clientInfo.profileID?.lowercased()
        let bundleIdentifier = event.clientInfo.bundleIdentifier?.lowercased()
        let isPlainClaudeCode = profileID != "qoder"
            && profileID != "qoderwork"
            && bundleIdentifier != "com.qoder.ide"
            && bundleIdentifier != "com.qoder.work"
        return event.provider == .claude
            && event.event == "PermissionRequest"
            && normalizedTool == "askuserquestion"
            && isPlainClaudeCode
    }

    private static func isCodeBuddyCLIQuestionNotification(_ event: HookEvent) -> Bool {
        guard event.provider == .claude,
              event.event == "Notification",
              event.notificationType == "permission_prompt",
              event.clientInfo.profileID?.lowercased() == "codebuddy-cli" else {
            return false
        }

        let normalizedMessage = event.message?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            ?? ""
        return normalizedMessage.contains("askuserquestion")
            || normalizedMessage.contains("ask user question")
            || normalizedMessage.contains("ask_user_question")
    }

    static func questionSignature(from toolInput: [String: AnyCodable]?) -> [String]? {
        guard let rawQuestions = toolInput?["questions"]?.value as? [Any], !rawQuestions.isEmpty else {
            return nil
        }

        let questions = rawQuestions.compactMap { entry -> [String: Any]? in
            entry as? [String: Any]
        }
        guard !questions.isEmpty else { return nil }

        return questions.map { question in
            let prompt = SessionTextSanitizer.sanitizedDisplayText(
                (question["question"] as? String) ?? (question["prompt"] as? String)
            ) ?? ""
            let header = SessionTextSanitizer.sanitizedDisplayText(question["header"] as? String) ?? ""
            let identifier = SessionTextSanitizer.sanitizedDisplayText(question["id"] as? String) ?? ""
            return [identifier, header, prompt]
                .joined(separator: "|")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}
