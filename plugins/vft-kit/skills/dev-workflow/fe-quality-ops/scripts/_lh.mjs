// 解析 lighthouse / chrome-launcher，供 lighthouse-audit.mjs 直接当库调用。
//
// 为什么不用 lighthouse MCP：新注册的 MCP 要重启会话才加载，装完当次用不了。
// 而 lighthouse 本身就是普通 npm 包（MCP 只是薄壳，它的 deps 里就躺着 lighthouse + chrome-launcher），
// 直接 import 就能跑，装完立即可用、无需重启。和 _pw.mjs 走编程式 Playwright 是同一个思路。
//
// 找包顺序：本项目 node_modules → 全局 node_modules → lighthouse-mcp 包内的 node_modules（复用它的依赖）。
import { execSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

const gRoot = (() => {
  try { return execSync('npm root -g', { encoding: 'utf8' }).trim(); } catch { return ''; }
})();

const SEARCH_DIRS = [
  `${process.cwd()}/node_modules`,
  gRoot,
  `${gRoot}/@danielsogl/lighthouse-mcp/node_modules`,
].filter(Boolean);

// lighthouse 是 exports-only 的纯 ESM 包，require.resolve 解析不了，
// 只能自己读 package.json 的 exports['.'] / module / main 找入口。
function entryOf(pkgDir) {
  let entry;
  try {
    const pkg = JSON.parse(readFileSync(`${pkgDir}/package.json`, 'utf8'));
    const exp = pkg.exports;
    if (typeof exp === 'string') entry = exp;
    else if (exp && typeof exp === 'object') {
      let dot = exp['.'] ?? exp;
      if (typeof dot === 'object') dot = dot.import ?? dot.default ?? dot.require;
      if (typeof dot === 'object') dot = dot.default ?? dot.import;
      entry = dot;
    }
    entry = entry ?? pkg.module ?? pkg.main ?? 'index.js';
  } catch { entry = 'index.js'; }
  return `${pkgDir}/${String(entry).replace(/^\.\//, '')}`;
}

async function load(name) {
  for (const dir of SEARCH_DIRS) {
    const pkgDir = `${dir}/${name}`;
    if (!existsSync(pkgDir)) continue;
    const full = entryOf(pkgDir);
    if (!existsSync(full)) continue;
    try { return await import(pathToFileURL(full).href); } catch { /* 换下一个候选 */ }
  }
  return null;
}

const lhMod = await load('lighthouse');
const clMod = await load('chrome-launcher');

if (!lhMod || !clMod) {
  console.error('未找到 lighthouse / chrome-launcher。装一下：npm i -g lighthouse chrome-launcher');
  process.exit(1);
}

export const lighthouse = lhMod.default ?? lhMod;
export const launch = clMod.launch ?? clMod.default?.launch;
