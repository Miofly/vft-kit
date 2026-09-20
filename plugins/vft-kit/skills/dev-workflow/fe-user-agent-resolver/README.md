# fe-user-agent-resolver

输入单条浏览器 User-Agent，输出全设备类型的结构化设备信息。

## 1. 能力

| 维度 | 输出内容 |
| --- | --- |
| 设备 | 类型（mobile/tablet/desktop/tv/console/bot）、品牌、硬件型号代码、消费者型号名称、上市年月 |
| 系统 | Android / iOS / iPadOS / HarmonyOS（含 NEXT）/ Windows / macOS / Linux / ChromeOS / Tizen / webOS 及版本 |
| 浏览器 | Chrome / Safari / Edge / Firefox / IE 及小米、华为、OPPO、vivo、三星、UC、夸克、QQ 等国内浏览器与版本 |
| 内核 | Blink / WebKit / Gecko / ArkWeb / Trident |
| 容器 | 是否 WebView、宿主 App（微信/企业微信/QQ/支付宝/钉钉/抖音/头条/百度/微博） |

准确性原则：每个字段带置信度（certain/likely/unknown），UA 看不见的信息（iOS 具体机型、Windows 10/11 区分、缩减 UA 的真实版本）如实标注盲区原因，绝不猜测。

## 2. 使用

在 Claude Code 中粘贴 UA 并提问即可，例如：

> 这条 UA 是什么设备？Mozilla/5.0 (Linux; Android 13; SM-S9180 Build/...) ...

也可直接调用脚本（零第三方依赖，Python 3.8+）：

```bash
printf '%s' "$UA" | python3 scripts/parse_ua.py --stdin
```

输出为结构化 JSON，字段语义见 `SKILL.md` 第 3、4 节。

## 3. 消费者型号与发布日期如何保证精确

1. 命中 `data/device-models.json` 精选映射（每条均经权威来源核实）→ 型号名与上市年月（`release_date`，YYYY-MM）同时给出，certain；
2. 型号本身即营销名（Pixel 8 Pro、Redmi K70 等）→ 型号名直接采用，发布日期仍需网查；
3. 其余输出型号代码并置 `needs_web_lookup=true`，由技能按 `references/authoritative-sources.md` 的规则检索厂商官网确认型号名与上市时间，未确认就明说未知。UA 本身不含发布日期，绝不凭型号代码猜年份。

## 4. 目录结构

```
fe-user-agent-resolver/
├── SKILL.md                      # 技能定义与执行流程
├── README.md
├── scripts/parse_ua.py           # 离线解析器（零依赖单文件）
├── data/device-models.json       # 精选机型映射表（品牌/型号名/上市年月，可持续补充）
├── references/authoritative-sources.md  # 权威源与网查纪律
└── tests/test_parse_ua.py        # 24 个真实 UA 用例
```

## 5. 测试

```bash
python3 tests/test_parse_ua.py
```

## 6. 常见问题

- **为什么 iPhone 查不出具体型号？** 所有 iPhone 的 UA 完全相同，这是 UA 的固有限制，网查也无法弥补，需业务侧另行采集。
- **为什么安卓机型显示 K？** 新版 Chrome 缩减了 UA（Reduced UA），真实机型需改用 Client Hints（`Sec-CH-UA-Model`）采集。
- **映射表没有我的机型？** 按 `references/authoritative-sources.md` 核实后向 `data/device-models.json` 补充条目提 PR。
