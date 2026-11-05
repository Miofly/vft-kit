# 清理 cookie / 缓存 / 存储

**警告**：task space 建在某个 profile 上，该 profile 的 cookie 与 HTTP 缓存和用户自己的 tab、同 profile 的所有 space 共享。全 profile 清理无法撤销，会登出该 profile 上所有站点。

## 各命令影响范围

| 命令 | 影响范围 | 恢复 |
|---|---|---|
| `Network.deleteCookies` | 一个指定 cookie | 重新登录该站 |
| `Storage.clearDataForOrigin` | 一个 origin | 重新登录该站 |
| `Page.reload` + `ignoreCache: true` | 一次页面加载 | 无损失 |
| `Network.clearBrowserCookies` | **整个 profile** | **无法恢复** |
| `Network.clearBrowserCache` | **整个 profile** | **无法恢复** |
| `Storage.clearCookies`（不带 `browserContextId`） | **整个 profile** | **无法恢复** |

经 `page.cdp()` 发送不代表范围限于该页；`task.cdp()` 拒绝的命令换 `page.cdp()` 发同样危险。

## 常用做法

```js
// 只清当前站 cookie（想以匿名身份访问某站）
await page.cdp("Storage.clearDataForOrigin", { origin: new URL(await page.url()).origin, storageTypes: "cookies" });
// 只清当前站 Cache API 与 service worker
await page.cdp("Storage.clearDataForOrigin", { origin: new URL(await page.url()).origin, storageTypes: "cache_storage,service_workers" });
// 绕过缓存重载
await page.cdp("Page.reload", { ignoreCache: true });
// 删某站特定 cookie（含 httpOnly）
const { cookies } = await page.cdp("Network.getAllCookies");
for (const c of cookies.filter((c) => c.domain.includes("example.com")))
  await page.cdp("Network.deleteCookies", { name: c.name, domain: c.domain, path: c.path });
```

## 原则

- 复用登录态的任务不清 cookie。
- 要未登录环境：优先换一个未登录的 profile（见 [profiles.md](profiles.md)），其次清单站数据；不动整个 profile。
- 全 profile 清理必须先征得用户同意，并先告诉用户代价：`Network.getAllCookies` 的 cookie / 域名数，以及 `listTaskSpaces()` 里共享该 profile 的 space。
- 官方原文：ego-browser skill 目录下 `references/clearing-state.md`。
