---
name: fe-user-agent-resolver
description: "输入单条浏览器 User-Agent，输出全设备类型的结构化设备信息：设备类型（手机/平板/桌面/TV/爬虫等）、品牌、硬件型号代码、消费者型号名称、机型发布日期、操作系统与版本、浏览器与版本、渲染内核、WebView 容器与宿主 App。当用户粘贴 UA 并询问这是什么设备、什么手机、什么型号、哪年发布、什么系统、什么浏览器、是不是微信内嵌页，或从日志/埋点/排障途径取得一条 UA 需要还原设备画像时使用。批量埋点机型聚合分析应走数据分析平台，不适用本技能。"
---

# 1. fe-user-agent-resolver

对一条 User-Agent 做确定性的全维度解析。准确性优先：每个字段带置信度，有据则给、无据则明确 unknown，绝不猜测。

# 2. 执行流程

1. 从用户请求中取得一条完整 UA。没有 UA 时先请用户提供。
2. 确定本 SKILL.md 所在目录为 `SKILL_DIR`。Claude Code 中优先取 `${CLAUDE_SKILL_DIR}`；其他 Agent 使用已加载技能目录的绝对路径。
3. 通过标准输入调用解析脚本（避免 UA 进入命令行历史或 URL）：

```bash
printf '%s' "$UA" | python3 "$SKILL_DIR/scripts/parse_ua.py" --stdin
```

4. 读取输出 JSON，按第 4 节的字段语义整理成面向用户的结论。
5. 当 `flags.needs_web_lookup=true` 且用户关心消费者型号，或 `device.release_date` 为 null 且用户关心发布日期时，按 `$SKILL_DIR/references/authoritative-sources.md` 的规则网查确认：只用型号代码与品牌线索检索厂商官网，不提交完整 UA；权威页面同时出现型号代码与消费者型号（及上市时间）才可判定为确认。
6. 未能确认时，如实回复型号代码与"未能从权威来源确认消费者型号/发布日期"，不要用第三方站点的说法冒充确认结果。

# 3. 输出 JSON 结构

```json
{
  "device":    { "type": "mobile|tablet|desktop|tv|console|bot|unknown",
                 "type_confidence": "...", "brand": "...", "model_code": "...",
                 "consumer_name": "...", "release_date": "YYYY-MM 或 null",
                 "confidence": "..." },
  "os":        { "name": "...", "version": "...", "confidence": "..." },
  "browser":   { "name": "...", "version": "...", "confidence": "..." },
  "engine":    { "name": "Blink|WebKit|Gecko|ArkWeb|Trident", "version": "..." },
  "container": { "is_webview": false, "host_app": "微信|支付宝|..." },
  "flags":     { "is_bot": false, "ua_reduced": false, "needs_web_lookup": false },
  "notes":     [ "解析过程中的盲区与依据说明（中文）" ]
}
```

# 4. 字段语义与置信度

- `confidence` 三档：`certain`（UA 直接给出或权威映射命中）、`likely`（依据前缀规则/惯例推断）、`unknown`（UA 中不可见）。
- `consumer_name` 只在两种情况有值：内置映射表命中（certain），或型号本身就是营销名（如 Pixel 8 Pro，likely）。其余输出 `null` 并置 `needs_web_lookup=true`。
- `release_date` 是机型上市年月（`YYYY-MM`，取中国大陆上市时间）。UA 本身不含发布日期，仅映射表命中时有值（certain）；其余一律 `null`，需要时按第 2 节第 5 步网查确认，绝不凭型号代码猜年份。
- `notes` 数组解释所有盲区，转述给用户时保留关键结论。

# 5. UA 的固有盲区（必须如实转述，不要替 UA 编造）

- **iOS/iPadOS 不含具体机型**：所有 iPhone 报同一 UA，只能到 iPhone/iPad 粒度；网查也无法确认，不触发 `needs_web_lookup`。
- **Windows 10 与 11 同为 NT 10.0**，无法从 UA 区分。
- **macOS 版本冻结在 10.15.7**：真实系统可能更新；iPad 桌面模式也伪装成该 UA。
- **Chrome 缩减 UA**（`Android 10; K`）：真实机型与系统版本已被抹除（`ua_reduced=true`），需业务侧改用 Client Hints 采集。
- **鸿蒙**：UA 中的 Android 版本是兼容层版本；HarmonyOS NEXT 以 OpenHarmony/ArkWeb 标记识别。

# 6. 脚本调用参考

```bash
# Claude Code
SKILL_DIR="${CLAUDE_SKILL_DIR}"
printf '%s' "$UA" | python3 "$SKILL_DIR/scripts/parse_ua.py" --stdin

# 单行输出
printf '%s' "$UA" | python3 "$SKILL_DIR/scripts/parse_ua.py" --stdin --compact
```

零第三方依赖，Python 3.8+。Windows 将 `python3` 换成 `python` 或 `py`。标准输入只能传一条 UA；不要记录或持久化完整 UA。

# 7. 维护机型映射表

`data/device-models.json` 是精选映射（型号代码大写 → 品牌/消费者型号/上市年月 `released`）。新增条目必须先经权威来源核实（规则见 `references/authoritative-sources.md`），`released` 与型号名同源核实、精确到年月即可；不确定的机型不要加入，让解析走 `needs_web_lookup` 流程。
