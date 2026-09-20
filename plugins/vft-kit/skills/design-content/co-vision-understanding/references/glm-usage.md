# 智谱 GLM-4.6V-Flash 使用说明

真正免费的视觉理解模型（9B 参数，GLM-4.6V 的免费版），零成本场景的默认路线。
脚本：`scripts/glm_vision.py`，仅标准库，用 `python3` 运行。

## 1. 模型能力

| 项 | 值 |
|---|---|
| 模型名 (model id) | `glm-4.6v-flash` |
| 定价 | 免费 |
| 输入模态 | 图片、视频、文本、文件（pdf/doc/txt 等） |
| 输出模态 | 文本 |
| 上下文窗口 | 128K tokens（约 150 页文档 / 200 页 PPT / 1 小时视频） |
| 最大输出 | 32K tokens |
| 思考模式 | `thinking.type` 可 `enabled`/`disabled` |
| 其他能力 | 流式输出、原生多模态工具调用（Function Calling）、上下文缓存 |

擅长场景：OCR 信息提取（印刷/手写/楷体/艺术字）、复杂表格解析（多层表头、
合并单元格、跨页）、抗干扰识别（模糊/折痕/污渍/透视变形）、商品属性识别、
图像内容分析与打标、瑕疵检测、图片反推提示词（Image2Prompt）、目标检测与
计数（输出 `[[xmin,ymin,xmax,ymax]]` 坐标）、视频标签/摘要/时间轴/问答、
文档版式还原与智能问答。

关键限制（务必遵守）：
- **单次请求不能同时传图片、视频、文件三类媒体**，只能三选一（多图可以）。
  脚本已做校验，混传会直接报错，拆成多次调用即可。
- 视频、文件只接受**公网 URL**；本地图片可直传（脚本自动 Base64）。
- 并发上限按智谱用户权益等级动态分配，高峰期可能限流（错误码 1305），
  此时可路由到千问路线（见 SKILL.md 路由表）。

## 2. 常用调用配方

以下命令在 skill 目录下执行，或使用 `scripts/glm_vision.py` 的绝对路径。

**图片描述/理解**（本地图片直接传路径，自动 Base64 上传）：
```bash
python3 scripts/glm_vision.py "描述这张图片的内容" -i photo.jpg
```

**OCR 提取**（发票、证件、手写表单等；开启思考模式更稳）：
```bash
python3 scripts/glm_vision.py "提取发票的抬头、金额、日期、税号，输出 JSON" -i invoice.jpg --think enabled
```

**多图对比**（多张图片一次传入）：
```bash
python3 scripts/glm_vision.py "对比这两张截图的 UI 差异，逐条列出" -i before.png -i after.png
```

**目标检测/定位**（坐标归一化到图片宽高比例）：
```bash
python3 scripts/glm_vision.py "定位图中所有啤酒瓶，按 [[xmin,ymin,xmax,ymax]] 格式输出坐标" -i table.png
```

**视频理解**（只接受公网 URL）：
```bash
python3 scripts/glm_vision.py --video "https://example.com/demo.mp4" "总结视频内容并列出关键事件时间轴"
```

**文档问答**（pdf/doc/txt，公网 URL，可多文件；千问脚本不支持文件，文档类走这里）：
```bash
python3 scripts/glm_vision.py --file "https://example.com/report.pdf" "这份报告的核心结论和风险点是什么"
```

**流式输出**（长回答边生成边打印，思考过程走 stderr）：
```bash
python3 scripts/glm_vision.py "详细分析这张架构图" -i arch.png --stream
```

**结构化调试 / 拿 usage 信息**：
```bash
python3 scripts/glm_vision.py "识别图中文字" -i doc.png --json
```

**无 Key 自检**（只打印将要发送的请求体，不调用 API）：
```bash
python3 scripts/glm_vision.py "测试" -i a.png --dry-run
```

## 3. 可选参数

| 参数 | 说明 |
|---|---|
| `--think enabled\|disabled` | 思考模式，默认 `disabled`（快）；OCR/推理/数学题建议 `enabled` |
| `--stream` | 流式输出 |
| `--system "..."` | system 提示词 |
| `--max-tokens N` | 最大输出，上限 32768 |
| `--temperature / --top-p` | 采样参数 |
| `--model NAME` | 默认 `glm-4.6v-flash`，也可换成同接口的其他模型 |
| `--json` | 输出完整响应 JSON（含 usage） |
| `--dry-run` | 只打印请求体不发请求 |

## 4. 错误处理

| 错误码 | 含义 | 应对 |
|---|---|---|
| 1002 | API Key 无效 | 检查 Key 是否正确配置 |
| 1302 | 触发速率限制 | 降低并发、稍后重试（免费模型并发按权益等级） |
| 1305 | 平台过载 | 增大间隔重试 1-2 次，仍失败则路由到千问路线 |
| 1301 | 内容安全拦截 | 调整输入内容 |

脚本已内置这些错误码的友好提示；遇到 1305 这类瞬态错误可重试 1-2 次，
勿高频重试。

## 5. 协作提示

- 用户的**本地视频/文件**需要先换成公网 URL 才能调用，可借助本机的
  `fe-file-uploader` skill 上传到测试服务器拿链接。
- 模型免费且上下文大，适合批量处理截图、做低成本 OCR 管线；但批量并发
  受权益等级限制，批处理时控制并发数（建议 ≤5 起步）。
- 图片生成/图像编辑不是本模型能力（输出只有文本），这类需求走其他模型
  （如 `aliyun-qwen-image-edit`）。
- 原生 API 细节见官方文档: https://docs.bigmodel.cn/cn/guide/models/free/glm-4.6v-flash
