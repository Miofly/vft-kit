---
name: plugin-refresh
description: 刷新 Claude Code 插件，把 marketplace 远端 / 本地源目录的最新内容（skill / hook / agent / SKILL.md 正文）落到本机 cache 并生效。涵盖本地目录插件（`uninstall + install` 重建 `~/.claude/plugins/cache/`）和远端 marketplace 插件（`marketplace update` + `plugin install`）。用户说"刷新插件"、"插件更新"、"拉最新 skill"、"plugin update"、"marketplace update"、"插件缓存不一致"、"插件装回来"、"重新安装插件"、"同步最新 skill 到本机"、"为啥新 skill 还没出现"、"为啥改了 SKILL.md 没生效"、"为啥 cc 看到的还是旧 skill"、"刷 cache"等场景时触发。**核心认知**：`plugin details` 的组件清单实时读源目录，但 cc 注入给 LLM 的 SKILL.md **正文**读的是 cache 拷贝——两者可以不一致，所以改完源必须刷 cache 再重启会话。**安全红线**：绝不能把 cache 目录做成指向源目录的软链（一种流行的"免刷新"偷懒做法）——CC 的 install/uninstall 写操作会穿透软链改写源码，实测导致源目录里的文件被静默增删。
---

# Claude Code 插件刷新

## 关键认知（必读）

Claude Code 的插件加载分两层，这两层可能不一致：

| 层 | 数据来源 | 改源后是否实时反映 |
|---|---|---|
| `claude plugin details <plugin>` 显示的**组件清单**（skill 名字、数量） | 源目录 | ✅ 实时 |
| cc 冷启动时注入 **LLM system prompt 的 SKILL.md 正文** | `~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/` | ❌ 不会，必须刷 cache |

危险之处在于：改了 SKILL.md 后 `plugin details` 里数量、名字全对，看起来生效了，但 LLM 拿到的指令可能还是旧版。

## 改完源要做两件事

```bash
# 1) 刷 cache（本地目录插件走下方脚本；远端插件见后文）
# 2) 重启 Claude Code 会话
```

缺一不可：不刷 cache，LLM 读到的 SKILL.md 正文是旧的；不重启会话，system prompt 是冷启动时注入的，当前会话里还是旧版。

## ⚠️ 不要把 cache 做成指向源目录的软链

有一种流行的"偷懒"做法：把 `~/.claude/plugins/cache/<mp>/<plugin>/<ver>` 换成指向源目录的软链，让源一改 cache 立即跟上，从此免刷。

**别这么做，它会损坏你的源码。**

`claude plugin uninstall / install` 会对 cache 目录做**删除和写入**。cache 若是软链，这些写操作会**穿透软链直接改写源目录**。实测后果：一个已经从 A 插件移走的 skill，被 install 从旧内容里写回了 A 的源目录，而 B 插件反而少了它——源码被静默改写，git 里凭空多出/少掉文件。

更阴险的是，软链方案和"改完刷 cache"的纪律**不能共存**：只要在软链生效时刷一次 cache，雷就炸了。

正确做法是让 cache 保持**真实副本**——CC 的读写只作用于副本，永远碰不到源码。刷新的代价（一条命令）远低于源码被污染的代价。

用这条命令确认 cache 是什么：

```bash
ls -ld ~/.claude/plugins/cache/<marketplace>/<plugin>/<version>
# 以 d 开头 → 真实副本（正确）
# 以 l 开头 → 软链（危险，删掉它重新 install）
```

## 本地目录插件（cache 是真副本时）

先确认来源类型：

```bash
claude plugin marketplace list
```

`Source:` 行有两类：

- `Source: Directory (/abs/path)` —— **本地目录插件**
- `Source: GitHub (org/repo)` / `Source: HTTP (...)` —— **远端 marketplace 插件**

本地目录插件直接跑封装脚本（幂等）：

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/plugin-refresh/scripts/refresh-local-plugin.sh -p <plugin-name>

# marketplace 名与 plugin 名不同时
bash ${CLAUDE_PLUGIN_ROOT}/skills/plugin-refresh/scripts/refresh-local-plugin.sh -p <plugin> -m <marketplace>
```

脚本做的事：

1. 校验 marketplace 是 `Directory` 来源（非本地拒绝跑，引导用远端流程）
2. `claude plugin uninstall <plugin>@<marketplace>`
3. `claude plugin install <plugin>@<marketplace>`
4. 比对源目录与 cache 下 SKILL.md **数量**
5. 抽一份 SKILL.md 比 **size**，提早抓"个数对但内容旧"

### 为什么 `marketplace update` / 单跑 `plugin install` 都不行（实测）

| 命令 | 是否刷 cache |
|---|---|
| `claude plugin marketplace update <mp>` | ❌ 只更新 marketplace 索引 manifest，不动 cache |
| `claude plugin install <plugin>@<mp>`（已装） | ❌ 跳过：`Plugin is already installed` |
| `uninstall` 然后 `install` | ✅ 完整重建 cache |

所以脚本走 uninstall + install 这条路。

## 远端 marketplace 插件

```bash
# 1) 更新 marketplace 索引（拉远端最新 manifest）
claude plugin marketplace update <marketplace-name>

# 2) 重装插件（CLI 读 manifest 后落最新版到 cache，通常不用先 uninstall）
claude plugin install <plugin-name>@<marketplace-name>

# 3) 验证
claude plugin details <plugin-name>
```

若 `plugin install` 提示 `already installed` 但你确认远端有更新，走 uninstall + install 兜底。

## 排查与诊断

### 步骤 1 — 看现状

```bash
claude plugin marketplace list   # 每个 marketplace 是 Directory 还是远端
claude plugin list               # 已装的 plugin
claude plugin details <plugin>   # 组件清单（skill 名字 + 数量）
```

`details` 列出了期望的新 skill，**只能说明组件清单读源正常**，不代表 LLM 看到的 SKILL.md 正文是新的。

### 步骤 2 — 兜底重置（marketplace 注册坏了才用）

```bash
claude plugin marketplace remove <marketplace-name>
claude plugin marketplace add <git-url-或-绝对路径>
claude plugin install <plugin-name>@<marketplace-name>
```

`marketplace remove` 对本地插件只解绑注册，不动磁盘源目录，可放心。

> 注：若 marketplace 是在 `settings.json` 的 `extraKnownMarketplaces` 里声明的，`marketplace add` 会提示 "declared in user settings" 并跳过实际注册——它要等**下次会话启动**时 reconcile 才真正生效。想立刻生效，先把该条目从 settings 里摘掉再 add。

## 常见诊断对照

| 现象 | 大概率原因 | 处理 |
|---|---|---|
| 改了 SKILL.md，cc 看到的还是旧版 | cache 是真副本且没刷 | 刷 cache + 重启会话 |
| 刷了 cache 还是旧版 | 没重启会话（system prompt 是冷启动加载的） | 重启会话 |
| 新加了 skill 目录，cc 调用时找不到 | cache 没刷 + 没重启 | 先刷，再重启 |
| `details` 数量对得上，但 skill 行为还是老的 | 经典陷阱：组件清单读源、SKILL.md 正文读 cache | 刷 cache |
| 源目录里凭空多出/少掉文件 | cache 被做成了软链，CC 的写操作穿透到了源目录 | 删掉软链、重新 install，让 cache 回到真副本 |
| `details` 数量对不上 | marketplace 索引或注册损坏 | 步骤 2 兜底 |
| `marketplace update` 报 404 | 远端仓库地址变了 / 删了 | 步骤 2 兜底 |
| `plugin install` 报已装 | install 幂等会跳过 | 用 `refresh-local-plugin.sh`，它先 uninstall |
| 改了本地源但 `details` 数量也没变 | marketplace 注册路径不对，或源目录被移动过 | 步骤 2 重新 add |

## 操作原则

- **确保 cache 是真实副本，不是软链**——软链会让 CC 的写操作穿透到源目录，损坏源码。
- 命令幂等，重复跑无副作用。
- 别用 `claude plugin update`（不同 CLI 版本行为不一致）。
- 跑完把 SKILL.md 数量与具体名字回报给用户，方便对账。
- 无论刷不刷，都要提示用户**重启会话**——cache 对了但 cc 已把旧版加载进 system prompt，必须冷启。
- `marketplace remove` 这类破坏性动作先确认；本地插件的 remove 可逆（只解绑），仍要提醒。
