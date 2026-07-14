import XCTest
@testable import CCHelperCore

final class NotificationDeciderTests: XCTestCase {
    func test_stop_with_tools_is_taskComplete() {
        let d = NotificationDecider()
        _ = d.decide(event: "PostToolUse", payload: ["tool_name": "Bash", "tool_response": [:]])
        let out = d.decide(event: "Stop", payload: [:])
        XCTAssertEqual(out?.kind, .taskComplete)
    }

    func test_stop_without_tools_is_conversationComplete() {
        let d = NotificationDecider()
        let out = d.decide(event: "Stop", payload: [:])
        XCTAssertEqual(out?.kind, .conversationComplete)
    }

    func test_tool_failure_is_taskError_and_suppresses_complete() {
        let d = NotificationDecider()
        let err = d.decide(event: "PostToolUse",
                           payload: ["tool_name": "Bash", "tool_response": ["is_error": true]])
        XCTAssertEqual(err?.kind, .taskError)
        XCTAssertTrue(err?.message.contains("Bash") ?? false)
        // 已报失败,Stop 不再报完成
        XCTAssertNil(d.decide(event: "Stop", payload: [:]))
    }

    func test_pretooluse_ask_and_plan() {
        let d = NotificationDecider()
        XCTAssertEqual(d.decide(event: "PreToolUse", payload: ["tool_name": "AskUserQuestion"])?.kind, .waitingForInput)
        XCTAssertEqual(d.decide(event: "PreToolUse", payload: ["tool_name": "ExitPlanMode"])?.kind, .waitingForInput)
        XCTAssertNil(d.decide(event: "PreToolUse", payload: ["tool_name": "Bash"]))
    }

    func test_permission_request() {
        XCTAssertEqual(NotificationDecider().decide(event: "PermissionRequest", payload: [:])?.kind, .waitingForInput)
    }

    func test_successful_tool_no_notification() {
        let d = NotificationDecider()
        XCTAssertNil(d.decide(event: "PostToolUse", payload: ["tool_name": "Bash", "tool_response": ["is_error": false]]))
    }

    func test_turn_resets_after_stop() {
        let d = NotificationDecider()
        _ = d.decide(event: "PostToolUse", payload: ["tool_name": "Bash", "tool_response": [:]])
        _ = d.decide(event: "Stop", payload: [:])
        // 新一轮无工具 → conversationComplete
        XCTAssertEqual(d.decide(event: "Stop", payload: [:])?.kind, .conversationComplete)
    }
}
