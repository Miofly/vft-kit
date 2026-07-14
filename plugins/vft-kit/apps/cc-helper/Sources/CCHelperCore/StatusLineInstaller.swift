import Foundation

public enum StatusLineInstaller {
    /// 生成 wrapper 脚本:tee stdin 给 island-statusline(取写文件副作用)+ 原命令(取显示)。
    public static func wrapperScript(originalCommand: String, islandStatuslinePath: String) -> String {
        """
        #!/bin/bash
        # 由 cc-notch-usage 生成:兼得 CC 用量落盘 + 原状态栏显示
        input=$(cat)
        printf '%s' "$input" | \(islandStatuslinePath) >/dev/null 2>&1
        printf '%s' "$input" | \(originalCommand)
        """
    }

    /// 把 settings 里的 statusLine.command 换成 wrapper,返回被替换掉的原命令(供备份)。
    public static func installed(
        into settings: [String: Any],
        wrapperCommand: String
    ) -> (updated: [String: Any], backupCommand: String?) {
        var updated = settings
        var statusLine = settings["statusLine"] as? [String: Any] ?? [:]
        let backup = statusLine["command"] as? String
        statusLine["type"] = "command"
        statusLine["command"] = wrapperCommand
        updated["statusLine"] = statusLine
        return (updated, backup)
    }

    /// 还原:把 statusLine.command 写回原命令。
    public static func restored(into settings: [String: Any], originalCommand: String) -> [String: Any] {
        var updated = settings
        var statusLine = settings["statusLine"] as? [String: Any] ?? [:]
        statusLine["type"] = "command"
        statusLine["command"] = originalCommand
        updated["statusLine"] = statusLine
        return updated
    }
}
