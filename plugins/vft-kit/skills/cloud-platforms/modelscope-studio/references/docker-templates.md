# Docker Studio Templates

Prerequisite: You must complete Alibaba Cloud account binding on the ModelScope platform and pass real-name verification.
See: https://modelscope.cn/docs/studios/docker

## Python app

```dockerfile
FROM python:3.10
WORKDIR /home/user/app
COPY ./ /home/user/app
RUN pip install -r requirements.txt
EXPOSE 7860
ENTRYPOINT ["python", "-u", "app.py"]
```

## Node.js app

```dockerfile
FROM node:18
WORKDIR /home/user/app
COPY ./ /home/user/app
RUN npm install
RUN npm run build
EXPOSE 7860
CMD ["npm", "start"]
```

## FastAPI app

```dockerfile
FROM python:3.10
WORKDIR /home/user/app
COPY ./ /home/user/app
RUN pip install -r requirements.txt
EXPOSE 7860
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "7860"]
```

## Golang app

```dockerfile
FROM golang:1.21 AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -o server .

FROM alpine:latest
WORKDIR /app
COPY --from=builder /app/server .
EXPOSE 7860
CMD ["./server"]
```

## Key requirements

1. **Port must be 7860** — listen on `0.0.0.0:7860`; do not use `8080` (occupied by the platform)
2. **HTTP Header restrictions** — do not use `Authorization`, `X-modelscope-*`, or `X-studio-*`
3. **Persistence** — by default data is lost on every restart; the persistent directory is `/mnt/workspace`
4. **Large files** — use Git LFS for files over 100MB
5. **First build** — approximately 3-5 minutes

## Docker Studio Reference

For applications that go beyond the scope of Gradio/Streamlit, such as FastAPI, Golang, and Node.js.
Prerequisite: you must complete Alibaba Cloud account binding and pass real-name verification on the ModelScope platform; see https://modelscope.cn/docs/studios/docker for details. See `references/docker-templates.md` for details.

**Key requirements:**

- The port must expose `0.0.0.0:7860`; using `8080` is prohibited (occupied by the platform)
- HTTP headers must not use `Authorization`, `X-modelscope-*`, or `X-studio-*`

### API 化进度：私有空间运行时回验（2026-09-30）

- 国内站私有空间的 SDK Token 请求使用 `https://studio-<owner>-<repo>.api-inference.modelscope.net`；
  普通 `*.ms.show` 页面地址会拒绝直接使用 SDK Token，并返回专用 API 地址。
- `GET /health` 用于已实现该端点的应用；请求的 `Authorization: Bearer <token>` 由平台认证处理，
  与上面“应用不要自定义保留请求头”的限制不同。控制面 `Running` 之后仍须验证真实推理结果。
- 已附只读脚本：`python3 scripts/probe-runtime.py owner/repo --token-file /absolute/path/account.json`，
  或从 `MODELSCOPE_API_KEY` 读取；自检：`python3 scripts/probe-runtime.py --selftest`。Token 不写入 argv、URL 或输出。
- Docker 大模型不要在端口监听前下载数 GB 权重：实际冷启动可能在 300 秒内被健康检查终止，
  多个实例也可能争用持久目录里的临时文件。优先在构建期下载并校验 SHA-256，运行时直接加载镜像内文件；
  覆盖基础镜像的 `HEALTHCHECK`，使其访问实际的 7860 端口。

## Data Persistence

- Container writable-layer data is lost on restart; `/mnt/workspace` is the persistence path to verify on the target runtime.
- 2026-10-10 private free CPU verification: SDK-authenticated WSS carried the MySQL protocol between two Studios, including 28 simultaneous JDBC connections. This was an application-defined WebSocket relay, not a platform-provided public MySQL TCP port.
- In that runtime, `/mnt/workspace` retained 2,000 test rows and their checksum after redeployment, but file permissions stayed `0777` after `chmod 0600`. MySQL 8.4 discarded `auto.cnf` and regenerated its UUID. Verify permission semantics, server UUID, crash recovery, and full-data readback before treating this path as a database disk; persistence alone does not establish production suitability.
- Data is still lost when transferring/renaming a Studio
- For high-reliability needs, use external storage (OSS, databases)
