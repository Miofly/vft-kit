---
name: co-vision-understanding
description: 调用免费/低成本多模态视觉模型，做图片理解、OCR 识别提取、表格解析、视频理解、文档问答和目标检测定位。双路线：智谱 GLM-4.6V-Flash（真免费）与千问AI平台 qwen-vl 系列（新用户免费额度）。当用户想用免费/零成本的多模态或视觉模型，提到智谱/GLM/Zhipu/bigmodel/千问/qwen-vl/DashScope 看图、识别截图、提取发票/证件/手写表单文字、解析复杂表格、总结视频、看图问答、检测图中物体位置坐标，或者说"用免费模型看下这张图"、"找个免费的 VL 模型"、"glm-4.6v-flash 怎么用"时，都应主动使用本 skill，即使用户没点名模型。注意：纯文本任务不需要视觉能力时不必触发；图像生成/编辑不是本模型能力，请勿误触发。
---

# 视觉理解（GLM 真免费 / 千问免费额度 双路线）

## 1. 路由

| 场景 | 路线 | 细则 |
|---|---|---|
| 默认零成本：图片理解/OCR/表格/视频 | `scripts/glm_vision.py` | `references/glm-usage.md` |
| GLM 返回 1305 过载、用户指定千问、或已有 DashScope Key | `scripts/qwen_vision.py` | `references/qwen-usage.md` |
| 专业 OCR（票据/扫描文档/表格抽取） | 两者皆可；千问有专用 `qwen-vl-ocr` | `references/qwen-usage.md` |
| pdf/doc 等文档理解 | 仅 GLM | `references/glm-usage.md` |
| 图片生成/编辑 | 超出本技能，走 `aliyun-qwen-image-edit` | — |

两个脚本 CLI 形态一致（`-i` 多图、`--video`、`--think`、`--stream`、
`--model`、`--json`、`--dry-run`），换路线不用改写命令。

## 2. Key 配置（两路线通用）

读取顺序：`--key` 参数 > 本地 `.env`（先当前工作目录，后 skill 根目录）>
环境变量（`ZHIPU_API_KEY` / `DASHSCOPE_API_KEY` / `QWEN_API_KEY`）；
千问路线额外回退 `~/.alibabacloud/credentials` 的 `dashscope_api_key`。
模板见 `.env.example`。
若运行报"未找到 API Key"，向用户要 Key：一次性用就传 `--key`。

## 3. 使用说明

- 智谱 GLM-4.6V-Flash：`references/glm-usage.md`（能力、调用配方、参数、错误码）
- 千问 qwen-vl 系列：`references/qwen-usage.md`（模型与免费额度、调用配方、参数、错误码）
