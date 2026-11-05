# Lessons

实际操作中踩的坑，按「症状 / 原因 / 对策」记录。遇到新问题先查这里。

## 同仓库多个 Vercel 项目时部署错项目

- **症状**：给站点 B 部署新改动时跑 `vercel --prod`，构建成功，但站点 B 页面毫无变化。
- **原因**：本地仓库 `.vercel/project.json` link 的是项目 A；站点 B 是同团队下用同一仓库的**另一个 Vercel 项目**。若 B 没接 GitHub 集成，push 也不会触发它的部署。
- **对策**：部署 B 用环境变量覆盖 link，不改本地 `.vercel/`：
  ```bash
  cd <仓库> && CI=1 \
    VERCEL_ORG_ID=<team_id> \
    VERCEL_PROJECT_ID=<B 的 prj_id> \
    vercel --prod
  ```
  部署前先 `vercel ls <project>` 确认目标项目最近部署时间，别拿「部署成功」当上线成功。

## vercel CLI 交互与网络

- **症状**：`vercel whoami` / `vercel ls` 卡在「Would you like to upgrade now? (Y/n)」。
- **对策**：一律 `CI=1` 前缀（或 `export CI=1`），跳过升级提示等所有交互。

- **症状**：curl `*.vercel.app` 返回 HTTP 000（连不上）。
- **原因**：部分网络环境下 vercel.app 直连不通。
- **对策**：验收部署 URL 走本地代理（如 `-x http://127.0.0.1:7890`）；挂在其他 CDN（如 Cloudflare）后的自有生产域名通常可直连。

## 部署验收

- 生产域名页面有边缘缓存（s-maxage=300），READY 后立即 curl 可能命中旧缓存；带 cache-busting query（`?v=时间戳`）或等 5 分钟再验。
- CLI 慢构建放后台时别接 `| tail`（缓冲到进程结束才有输出）；日志重定向到文件再 `tail -f` 该文件。
