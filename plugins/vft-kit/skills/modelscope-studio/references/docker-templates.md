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
