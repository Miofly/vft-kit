---
name: ollama-local
description: >-
  Use when installing, configuring, updating, testing, or operating Ollama local models;
  choosing a model for available memory; diagnosing pull/proxy/API failures; or calling
  the local Ollama chat API. Also covers the boundary between Ollama text models and
  separate ComfyUI image workflows.
---

# Ollama 本地模型

## 基本原则

- 先检查 `ollama` 是否存在、服务是否可达、磁盘和内存，再下载模型；不要仅凭下载成功声称可推理。
- 模型名称、标签、体积和能力以当前 `ollama list` / `ollama show` 为准，不维护过时目录。
- 下载属于本地可逆操作；替换或删除已有模型前先确认目标和磁盘占用。
- Ollama 是本地运行时，不等于模型“无安全限制”或“什么都能回答”；模型自身的对齐、能力和许可证仍适用。
- 不打印 API key、Cookie 或配置文件中的秘密；命令输出只保留模型名、状态、大小和错误摘要。

## 安装与服务

macOS 推荐 Homebrew：

```bash
brew install ollama
ollama serve                 # 没有后台服务时启动；默认 http://127.0.0.1:11434
ollama list
ollama ps
```

已有桌面版时不要重复启动第二个服务。先用 `curl -fsS http://127.0.0.1:11434/api/tags` 检查服务；失败再查看前台 `ollama serve` 的错误。

## 模型操作

```bash
ollama pull <owner>/<model>:<tag>   # 下载/续传
ollama run <owner>/<model>:<tag>    # 交互聊天，Ctrl-D 或 /bye 退出
ollama show <owner>/<model>:<tag>   # 查看模板、参数和许可证
ollama rm <owner>/<model>:<tag>     # 删除前确认精确模型名
```

用 `ollama run` 进行最小可用性测试；脚本/API 测试使用本地接口：

```bash
curl -sS http://127.0.0.1:11434/api/chat \
  -H 'Content-Type: application/json' \
  -d '{"model":"<model>","messages":[{"role":"user","content":"只回复 OK"}],"stream":false}'
```

## 内存、速度和模型选择

- Apple Silicon 使用统一内存；模型权重、KV cache、上下文和系统进程共同占用内存。
- 16–18GB 机器优先 7–8B 量化模型；14B 量化模型通常可运行但要降低上下文并关闭其他大程序；20B 以上不要默认承诺稳定。
- 先下载一个模型验证，再按 `ollama ps` 的实际常驻内存和响应速度决定是否并装多个模型。
- “abliterated”“uncensored”等标签不是质量保证，也不代表没有任何限制；只按模型卡、许可证和实测行为描述。

## 代理与网络故障

只为下载/远端请求设置代理，localhost 必须绕过代理：

```bash
export HTTPS_PROXY=http://127.0.0.1:7890
export HTTP_PROXY=http://127.0.0.1:7890
export ALL_PROXY=http://127.0.0.1:7890
export NO_PROXY=127.0.0.1,localhost
ollama pull <model>
```

出现 `Forbidden`、解析超时或下载卡住时，先检查代理端口和 `NO_PROXY`，再重试；不要把代理错误误判为模型不可用。若本地 API 返回 `403`，先区分远端反代/网关与 `127.0.0.1:11434` 的 Ollama 服务。

## Ollama 与图片模型的边界

Ollama 主要负责文本/多模态模型的本地推理。ComfyUI、Z-Image、SDXL-Lightning 等扩散图像模型应使用独立的 ComfyUI 工作流；不要把 `ollama list` 当作图像模型清单，也不要用 Ollama API 调用 ComfyUI。

涉及图片生成或图生图时，先检查 ComfyUI 服务、模型目录和对应 workflow；涉及文本聊天时才使用 Ollama 的 `run` 或 `/api/chat`。

## 完成标准

报告必须区分：已安装（文件存在）、服务可达（API 返回）、模型已加载（`ollama ps`）和推理成功（实际返回非空文本）。下载失败、内存不足、代理不可达时如实停止在对应边界。
