# Lessons

实际操作中踩的坑，按「症状 / 原因 / 对策」记录。遇到新问题先查这里。

## 2026-10-13 wflyynn 工具站部署错项目（blog ≠ tools）

- **症状**：给 tools.wflynn.cn 部署新改动时跑 `vercel --prod`，构建 16 分钟成功，但 tools.wflynn.cn 页面毫无变化。
- **原因**：本机 blog 仓库 `.vercel/project.json` link 的是 **blog 项目（wflynn.cn 主站）**；tools.wflynn.cn 是同团队下**独立的 Vercel 项目 `tools`**（prj_5QsuMxjgmRMfmX61ivX1bRZS4jel），同仓库、Build Command `pnpm build:vercel`、**无 GitHub 集成**（push 不触发，历史部署全是 CLI 手动）。
- **对策**：部署 tools 用环境变量覆盖 link，不改本机 `.vercel/`：
  ```bash
  cd <blog 仓库> && CI=1 \
    VERCEL_ORG_ID=team_F7nimkcJjFHzSn6LepAgsDzW \
    VERCEL_PROJECT_ID=prj_5QsuMxjgmRMfmX61ivX1bRZS4jel \
    vercel --prod
  ```
  部署前先 `vercel ls <project>` 确认目标项目最近部署时间，别拿「部署成功」当上线成功。

## vercel CLI 交互与网络

- **症状**：`vercel whoami` / `vercel ls` 卡在「Would you like to upgrade now? (Y/n)」。
- **对策**：一律 `CI=1` 前缀（或 `export CI=1`），跳过升级提示等所有交互。

- **症状**：curl `*.vercel.app` 返回 HTTP 000（连不上）。
- **原因**：vercel.app 直连被墙。
- **对策**：验收部署 URL 走本地代理 `-x http://127.0.0.1:7890`；生产域名 tools.wflynn.cn / wflynn.cn（Cloudflare）可直连。

## blog 仓库本地 dev 跑 tools 单入口

- **症状**：`npm run dev` / `npm run dev:tools` 打开 `/aitools/github-trending` 全是 404（客户端路由也是 404 页）。
- **原因**：两种模式最终 mode 都是 development，`.env.development` 的 `VITE_APP_TYPE=['comp']`，tools 路由根本没注册（SEO shell 有 title 但无内容，SSR 返回 404 status）。
- **对策**：本地跑工具站必须 `npm run dev:solo`（`.env.solo` 的 `VITE_APP_TYPE=['tools']`）。dev server 首次请求触发全量编译可达 1 分钟，浏览器 `page.goto` 要放宽超时或先 curl 预热。

## 部署验收

- 生产域名页面有边缘缓存（s-maxage=300），READY 后立即 curl 可能命中旧缓存；带 cache-busting query（`?v=时间戳`）或等 5 分钟再验。
- CLI 慢构建放后台时别接 `| tail`（缓冲到进程结束才有输出）；日志重定向到文件再 `tail -f` 该文件。
