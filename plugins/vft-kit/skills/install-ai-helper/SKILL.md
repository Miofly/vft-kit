---
name: install-ai-helper
description: 在 macOS 上安装、更新或检查 ai-helper 菜单栏应用，从 Miofly/vft-kit 的 GitHub Release 下载已签名并公证的 DMG，校验 SHA-256、Bundle ID、Developer ID 签名和 Gatekeeper 后安装到 Applications。用户说“安装 ai-helper”“更新 ai-helper”“装一下用量显示”“不用源码安装 ai-helper”“检查 ai-helper 版本”等场景时触发。不要从源码临时编译替代正式安装包，也不要在用户没有明确提出安装或更新时修改 Applications。
---

# 安装 ai-helper

使用本 skill 自带的 `scripts/install-ai-helper.mjs` 完成检查、下载、验证、安装和启动。插件安装本身不会运行第三方软件安装；用户明确提出安装或更新即视为本次操作授权。

## 工作流

1. 确认当前系统是 macOS。其他系统直接说明 ai-helper 仅支持 macOS。
2. 先运行只读检查：

   ```bash
   node "${VFT_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-${CODEX_PLUGIN_ROOT:-}}}/skills/install-ai-helper/scripts/install-ai-helper.mjs" --check
   ```

3. 如果用户只问版本或是否已安装，到此结束。
4. 如果用户明确要求安装或更新，运行：

   ```bash
   node "${VFT_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-${CODEX_PLUGIN_ROOT:-}}}/skills/install-ai-helper/scripts/install-ai-helper.mjs" --install
   ```

5. 报告安装版本、安装路径和应用是否已启动。若 Release 尚未发布、校验失败或 Gatekeeper 拒绝，原样说明错误并停止；不要降级到未经签名的本地构建，也不要绕过 Gatekeeper。

## 安全约束

- 只接受 `Miofly/vft-kit` 中标签以 `ai-helper-v` 开头的正式 Release。
- 必须同时存在 DMG 和同名 `.sha256` 资产。
- 必须验证 Bundle ID `com.wfly.ai-helper` 和 Team ID `K46RM9974S`。
- 更新时允许替换已有的 ai-helper；脚本会先退出应用并在替换失败时恢复旧版本。
- 不使用 `sudo`。`/Applications` 不可写时安装到当前用户的 `~/Applications`。
