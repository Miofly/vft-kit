---
name: usage-alert-setup
description: 一键开通 vft-kit 的 Claude 用量阈值告警（5 小时 / 7 天窗口越过 70%/90% 时弹 macOS 通知）。自动装 jq、检测 claude-hud、并把 display.externalUsageWritePath 写进 claude-hud 的 config.json，把「用量数据管道」接上。用户说"开通用量告警"、"用量告警怎么设"、"用量到阈值提醒我"、"配置额度告警"、"usage-alert-setup"、"为什么用量告警不响"、"limit 提醒"、"5小时/7天额度通知"、"装了 vft-kit 用量告警怎么开"等场景时触发。仅 macOS，需订阅账号（Pro/Max）。会改 claude-hud 配置，改前自动备份。
---

# usage-alert-setup —— 开通 vft-kit 用量告警

装完 vft-kit 后跑一次，把用量阈值告警打通。**仅 macOS，需订阅账号（Pro/Max）**。

## 它解决什么

vft-kit 的 `usage-alert.sh` 会在 5 小时 / 7 天用量窗口越过 70% / 90% 时弹 macOS 通知。这个 hook **已由插件自动注册**（Stop 事件），不用你写 settings.json。但它**不自己读用量**——官方 hook payload 里没有用量数据，唯一能拿到 `rate_limits` 的是 statusline。

所以它读 **claude-hud 落盘的用量快照**。本 skill 负责把这条数据管道接上：

1. 装 `jq`（脚本本体和本向导都需要）；
2. 检测 **claude-hud** 是否安装（没装则引导安装，不自动装）；
3. 往 claude-hud 的 `~/.claude/plugins/claude-hud/config.json` 写 `display.externalUsageWritePath`，指向 `usage-alert.sh` 默认读取的快照路径 `~/.claude/usage-snapshot.json`（两者必须指同一文件）。

claude-hud 侧只要这个 path 非空就开始落盘（源码 `shouldWriteUsage = Boolean(externalUsageWritePath)`），无额外开关。

## 怎么用

直接跑脚本：

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/usage-alert-setup/scripts/setup.sh
```

**幂等**，反复跑安全：已配好就跳过。

跑完注意：

1. **重启会话**：claude-hud 才会重载 config、开始落盘快照（每 ~30s 节流写一次）；
2. **订阅账号**：仅 Pro/Max 有限额窗口才会告警，API key 账号快照为空 → 不告警（正常）；
3. **自定义**：见下。

## 自定义（阈值 / 声音 / 新鲜度 / 快照路径）

本 skill 首次运行会在 `~/.claude/vft-kit/usage-alert-config.json` **落一份填满默认值的模板**（已存在则不覆盖）。直接编辑它，改后重启会话生效：

```json
{
  "thresholds": [70, 75, 80, 85, 90, 95, 100],
  "sound": "Glass",
  "maxAgeSeconds": 600,
  "snapshotPath": "~/.claude/usage-snapshot.json"
}
```

- `thresholds`：越过哪些百分比时告警（每档只在**当前达到的最高档**告警一次，避免 92% 同时触发多条）。想少打扰就精简成 `[80, 95]`。
- `sound`：macOS 系统音名（Hero / Basso / Glass / Ping…）。
- `maxAgeSeconds`：快照超过这个秒数就视为过期、不告警（默认 600）。
- `snapshotPath`：与 claude-hud 的 `externalUsageWritePath` 必须一致；本 skill 已把两边都对齐到默认值。

**取值优先级**：环境变量（`CLAUDE_USAGE_THRESHOLDS` / `CLAUDE_USAGE_SNAPSHOT`）> 配置文件 > 内建默认。env 用于临时覆盖，长期自定义改配置文件即可。

## 验证

跑几个 turn 后：

```bash
cat ~/.claude/usage-snapshot.json   # 应能看到 five_hour / seven_day 的 used_percentage
```

有数据即管道通了；越过阈值时会弹「Claude 用量告警」通知（同阈值同窗口去重，窗口翻新后可再告警）。

## 边界与安全

- **非 macOS**：直接退出，不改动。
- **claude-hud 未装**：引导先 `/plugin install claude-hud`，不自动装（避免替用户装整个第三方插件）。
- **claude-hud config 保护**：改前自动备份（`config.json.bak-<时间戳>`）；坏 JSON 只备份不覆盖；用 jq 合并，保留 config 里其它 `display.*` 键。
- **路径已指向别处**：会备份后对齐到标准快照路径，并告警说明（usage-alert 与 claude-hud 必须指同一文件才能联动）。
