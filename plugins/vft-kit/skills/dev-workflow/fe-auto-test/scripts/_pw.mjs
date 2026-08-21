// 解析 playwright 的 chromium：本机项目多半没装 playwright，回退到全局安装。
// 这些 node 脚本用 Playwright 的编程式 API（非 MCP），适合批量逐路由 / 容错跑多页面。
import { execSync } from 'node:child_process';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);

let mod;
const candidates = [];
try { candidates.push(require.resolve('playwright')); } catch {}
try { candidates.push(execSync('npm root -g', { encoding:'utf8' }).trim() + '/playwright/index.js'); } catch {}
for (const p of candidates) {
  try { mod = require(p); break; } catch {}
}
if (!mod) {
  console.error('未找到 playwright。装浏览器内核：npx playwright install chromium');
  process.exit(1);
}
export const chromium = mod.chromium;
