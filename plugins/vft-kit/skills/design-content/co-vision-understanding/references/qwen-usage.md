# 千问AI平台视觉理解使用说明

千问AI平台（platform.qianwenai.com，与阿里云百炼同后端）的 qwen-vl 系列视觉模型，
走 OpenAI 兼容接口。新用户有免费额度，是 GLM 过载/不可用时的备选路线。
脚本：`scripts/qwen_vision.py`，仅标准库，用 `python3` 运行。

## 1. 模型与免费额度

**免费额度规则**（以平台实时政策为准）：
- 每个视觉模型新用户免费 **100 万 tokens**，有效期 **90 天**（华北2/北京地域）
- 新用户全模型累计可领超 7000 万 tokens
- 额度耗尽或到期后按量计费；**务必在控制台开启用完即停开关**，避免意外扣费
- 免费额度不是永久免费，与智谱 GLM-4.6V-Flash 的真免费不同

**可选模型**：

| 模型 | 定位 |
|---|---|
| `qwen-vl-max`（脚本默认） | 旗舰视觉理解，推理与指令遵循最强 |
| `qwen-vl-plus` | 高性价比，简单视觉任务 |
| `qwen3-vl-flash` | 新一代轻量，思考/非思考双模式，支持长视频、空间感知、2D/3D 定位 |
| `qwen3-vl-plus` | Qwen3 系列增强版 |
| `qwen-vl-ocr` / `qwen-vl-ocr-latest` | 文字提取专用：扫描文档、表格、票据、结构化抽取 |

能力覆盖：图像描述、视觉问答、多图对比、物体定位（`[[xmin,ymin,xmax,ymax]]`
坐标）、视频理解（公网 URL）、OCR。不支持 pdf/doc 文件理解（文档类走 GLM 脚本）。

## 2. API Key 配置

Key 在千问AI平台控制台（platform.qianwenai.com/home）或百炼控制台获取。
脚本读取顺序：`--key` 参数 > 本地 `.env`（先当前工作目录，后 skill 根目录，
认 `DASHSCOPE_API_KEY` 或 `QWEN_API_KEY`）> 同名环境变量 >
`~/.alibabacloud/credentials` 任意 section 的 `dashscope_api_key`。
模板见 skill 根目录 `.env.example`。

接口为 OpenAI 兼容：base_url `https://dashscope.aliyuncs.com/compatible-mode/v1`，
从 OpenAI 代码迁移只需改 base_url / api_key / model 三处。

## 3. 常用调用配方

以下命令在 skill 目录下执行，或使用 `scripts/qwen_vision.py` 的绝对路径。

**图片描述/理解**（本地图片直接传路径，自动 Base64 上传）：
```bash
python3 scripts/qwen_vision.py "描述这张图片的内容" -i photo.jpg
```

**OCR 提取**（票据/文档文字提取用专用模型）：
```bash
python3 scripts/qwen_vision.py "提取发票的抬头、金额、日期、税号，输出 JSON" -i invoice.jpg --model qwen-vl-ocr
```

**多图对比**：
```bash
python3 scripts/qwen_vision.py "对比这两张截图的 UI 差异，逐条列出" -i before.png -i after.png
```

**目标检测/定位**：
```bash
python3 scripts/qwen_vision.py "定位图中所有啤酒瓶，按 [[xmin,ymin,xmax,ymax]] 格式输出坐标" -i table.png
```

**深度推理**（仅 Qwen3-VL 系列支持思考模式）：
```bash
python3 scripts/qwen_vision.py "这张图表说明了什么趋势" -i chart.png --model qwen3-vl-flash --think enabled
```

**视频理解**（只接受公网 URL）：
```bash
python3 scripts/qwen_vision.py --video "https://example.com/demo.mp4" "总结视频内容并列出关键事件时间轴"
```

**流式输出 / 结构化调试 / 无 Key 自检**：
```bash
python3 scripts/qwen_vision.py "详细分析这张架构图" -i arch.png --stream
python3 scripts/qwen_vision.py "识别图中文字" -i doc.png --json
python3 scripts/qwen_vision.py "测试" -i a.png --dry-run
```

## 4. 可选参数

| 参数 | 说明 |
|---|---|
| `--think enabled\|disabled` | 思考模式，默认 `disabled`；仅 Qwen3-VL 系列生效 |
| `--stream` | 流式输出 |
| `--system "..."` | system 提示词 |
| `--max-tokens N` | 最大输出 tokens |
| `--temperature / --top-p` | 采样参数 |
| `--model NAME` | 默认 `qwen-vl-max`，可换 plus / qwen3-vl-flash / qwen-vl-ocr 等 |
| `--json` | 输出完整响应 JSON（含 usage） |
| `--dry-run` | 只打印请求体不发请求 |

## 5. 错误处理

OpenAI 兼容接口错误体为 `{"error": {"code", "type", "message"}}`，脚本按子串匹配提示：

| 错误码特征 | 含义 | 应对 |
|---|---|---|
| `invalid_api_key` | Key 无效 | 检查 --key / .env / 环境变量 / credentials |
| 含 `quota` | 免费额度耗尽或配额不足 | 控制台查额度与用完即停开关，或换模型/换 GLM |
| `arrearage` | 账户欠费 | 充值或改用 GLM 免费模型 |
| 含 `throttl` | 限流 | 降低并发、稍后重试 |
| 含 `datainspection` | 内容安全拦截 | 调整输入内容 |

## 6. 协作提示

- 本地视频需先换公网 URL，可借助 `fe-file-uploader` skill。
- 批量处理时留意免费额度消耗（`--json` 可看 usage 的 token 数）。
- 图片生成/编辑走 `aliyun-qwen-image-edit`，本脚本只做理解。
- 文档：视觉模型 https://platform.qianwenai.com/docs/developer-guides/getting-started/vision-models ，
  免费额度 https://platform.qianwenai.com/docs/resources/free-quota ，
  OpenAI 兼容 https://platform.qianwenai.com/docs/api-reference/toolkitframework/openai-compatible/overview
