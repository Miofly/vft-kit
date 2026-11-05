# 安装 / 升级 ego-lite

先探测：`command -v ego-browser`。存在则直接按 SKILL.md 主流程用；不存在按本节安装。

## macOS

```bash
ego-browser upgrade
```

若 `ego-browser` 命令不存在，看 ego 官方 skill `ego-browser` 的 `references/install.md`（`ego-browser skill` 会打印当前版本使用指南，末尾 `[ego-browser:skill] end of guide`）。

## 升级后

升级会改变 API/命令集。升级后重跑一次 `ego-browser skill` 取最新指南；指南任何一行提示版本变化时同样重跑。

## 验证

```bash
ego-browser --version
ego-browser import list   # 能列出 Chrome/Firefox profile 即服务连通
```

`import list` 返回 JSON `browser_sources`，每个含 `browser_source`/`profiles`/`source_version`；这是确认 ego 浏览器后端 CLI 服务在跑的快速探针。
