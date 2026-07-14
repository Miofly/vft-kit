import Foundation

public enum NotificationKind: String, Sendable, Equatable {
    case taskComplete, taskError, waitingForInput, conversationComplete
}

public struct NotificationDecision: Equatable, Sendable {
    public let kind: NotificationKind
    public let message: String
    public init(kind: NotificationKind, message: String) {
        self.kind = kind
        self.message = message
    }
}

/// 把 CC hook 事件 → 通知决策。移植自 notify.mjs 的 decide/turn 逻辑。
/// turn 状态(是否出错 / 调了几次工具)放内存,跨事件累计,Stop 时结算并清零。
public final class NotificationDecider {
    private var hasError = false
    private var toolCount = 0

    public init() {}

    public func decide(event: String, payload: [String: Any]) -> NotificationDecision? {
        switch event {
        case "Stop":
            let prevError = hasError
            let prevTools = toolCount
            hasError = false
            toolCount = 0
            if prevError { return nil }   // 已就失败弹过,不再报完成
            return prevTools > 0
                ? NotificationDecision(kind: .taskComplete, message: "任务已完成，可以开始下一步")
                : NotificationDecision(kind: .conversationComplete, message: "Claude 已回复，请查看")

        case "PostToolUse":
            toolCount += 1
            if Self.isToolFailure(payload["tool_response"]) {
                hasError = true
                let name = payload["tool_name"] as? String ?? "工具"
                return NotificationDecision(kind: .taskError, message: "\(name) 执行失败，请检查")
            }
            return nil

        case "PreToolUse":
            switch payload["tool_name"] as? String {
            case "AskUserQuestion":
                return NotificationDecision(kind: .waitingForInput, message: "Claude 需要您回答问题")
            case "ExitPlanMode":
                return NotificationDecision(kind: .waitingForInput, message: "计划已完成，等待您审批")
            default:
                return nil
            }

        case "PermissionRequest", "Notification":
            return NotificationDecision(kind: .waitingForInput, message: "需要您的授权才能继续")

        default:
            return nil
        }
    }

    /// 只认工具显式声明的失败信号(is_error/isError/interrupted)。
    /// 不看 stderr:git/npm 成功也往 stderr 写东西,会误报。
    static func isToolFailure(_ response: Any?) -> Bool {
        guard let dict = response as? [String: Any] else { return false }
        for key in ["is_error", "isError", "interrupted"] {
            if let b = dict[key] as? Bool, b { return true }
        }
        return false
    }
}
