/**
 * render.mjs — 把一个 HTML 文件用 puppeteer 截图成 PNG。
 *
 * 设计要点：
 * - 浏览器依赖自给自足：按顺序找已有的 puppeteer（当前项目 / 全局 / mermaid-cli 自带 / 本脚本的私有缓存），
 *   全都没有时**自动装到 ~/.cache/vft-kit/render/**（不是 skill 目录——skill 跑的是 plugin cache 副本，
 *   刷新插件会连 node_modules 一起抹掉）。装一次，之后所有项目复用。
 * - chromium 缺失时回退到系统已装的 Chrome/Edge，避免重复下载 ~200MB。
 * - 默认只截取 id="shot" 的元素（信息图的根容器），3 倍分辨率高清；找不到该元素时退化为整页截图。
 * - 截图前自动检测内容溢出（scrollWidth > clientWidth），溢出会告警并提示调宽，不用靠肉眼看图找。
 *
 * 用法：
 *   node render.mjs <input.html> <output.png> [--selector "#shot"] [--scale 3] [--no-install]
 *
 * 注意：图片宽度由 HTML 里 `#shot { width }` 决定，不是命令行参数——想改图宽请改 HTML。
 */
import { createRequire } from 'module';
import { execFileSync } from 'child_process';
import { pathToFileURL } from 'url';
import path from 'path';
import os from 'os';
import fs from 'fs';

const require = createRequire(import.meta.url);

/** puppeteer 装不出来时的私有落脚点：用户级，不随 plugin cache 刷新蒸发 */
const FALLBACK_DIR = path.join(os.homedir(), '.cache', 'vft-kit', 'render');

/** 系统已装浏览器（按优先级），用于 chromium 未下载时兜底 */
const SYSTEM_BROWSERS = [
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  '/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge',
  '/Applications/Chromium.app/Contents/MacOS/Chromium',
  '/usr/bin/google-chrome',
  '/usr/bin/chromium',
  '/usr/bin/chromium-browser',
];

function tryResolve(base) {
  try {
    return require.resolve('puppeteer', { paths: [base] });
  } catch {
    return null;
  }
}

function npmRootGlobal() {
  try {
    return execFileSync('npm', ['root', '-g'], { encoding: 'utf8' }).trim();
  } catch {
    return null;
  }
}

function candidateDirs() {
  const dirs = [];
  if (process.env.PUPPETEER_DIR) dirs.push(process.env.PUPPETEER_DIR);
  dirs.push(path.join(process.cwd(), 'node_modules'));
  const gRoot = npmRootGlobal();
  if (gRoot) {
    dirs.push(gRoot);
    // mermaid-cli 自带一份 puppeteer，装了就白捡
    dirs.push(path.join(gRoot, '@mermaid-js', 'mermaid-cli', 'node_modules'));
  }
  dirs.push(path.join(FALLBACK_DIR, 'node_modules'));
  return dirs;
}

/** 把 puppeteer 装进私有缓存目录。只在所有探测都落空时调用。 */
function installPuppeteer() {
  fs.mkdirSync(FALLBACK_DIR, { recursive: true });
  const pkgJson = path.join(FALLBACK_DIR, 'package.json');
  if (!fs.existsSync(pkgJson)) {
    fs.writeFileSync(pkgJson, JSON.stringify({ name: 'vft-kit-render', private: true }, null, 2));
  }
  console.error('⏳ 未找到 puppeteer，正在装到 ~/.cache/vft-kit/render（一次性，之后复用）…');
  // 只装 JS 包，不下 chromium：浏览器一律走 pickBrowser() 的复用/兜底链，
  // 否则每次都要拉 ~110MB，而机器上通常早就有 chromium 或系统 Chrome 了。
  execFileSync('npm', ['install', 'puppeteer', '--silent', '--no-audit', '--no-fund'], {
    cwd: FALLBACK_DIR,
    stdio: ['ignore', 'inherit', 'inherit'],
    env: { ...process.env, PUPPETEER_SKIP_DOWNLOAD: 'true' },
  });
  console.error('✓ puppeteer 就绪');
}

function resolvePuppeteer(allowInstall) {
  for (const base of candidateDirs()) {
    const hit = tryResolve(base);
    if (hit) return hit;
  }
  if (!allowInstall) {
    throw new Error(
      '未找到 puppeteer，且指定了 --no-install。\n' +
        '手动装一次即可：npm install puppeteer --prefix ~/.cache/vft-kit/render',
    );
  }
  installPuppeteer();
  const hit = tryResolve(path.join(FALLBACK_DIR, 'node_modules'));
  if (!hit) throw new Error('puppeteer 安装后仍无法解析，请检查 npm 环境');
  return hit;
}

/** 扫 ~/.cache/puppeteer/chrome/*，捡一个已经下载过的 chromium（取版本号最大的） */
function cachedChromium() {
  const root = path.join(os.homedir(), '.cache', 'puppeteer', 'chrome');
  if (!fs.existsSync(root)) return null;
  const builds = fs
    .readdirSync(root)
    .filter((d) => !d.endsWith('.zip'))
    .sort((a, b) => b.localeCompare(a, undefined, { numeric: true }));
  for (const b of builds) {
    for (const rel of [
      'chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing',
      'chrome-mac-x64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing',
      'chrome-linux64/chrome',
    ]) {
      const p = path.join(root, b, rel);
      if (fs.existsSync(p)) return p;
    }
  }
  return null;
}

/** 选一个真实存在的浏览器：puppeteer 自带 → 已下载的 chromium → 系统 Chrome/Edge */
function pickBrowser(puppeteer) {
  try {
    const p = puppeteer.executablePath();
    if (p && fs.existsSync(p)) return undefined; // 自带的能用，交给 puppeteer 自己决定
  } catch {
    /* 拿不到路径，往下走兜底 */
  }
  const envPath = process.env.PUPPETEER_EXECUTABLE_PATH;
  if (envPath && fs.existsSync(envPath)) return envPath;

  const cached = cachedChromium();
  if (cached) {
    console.error(`ℹ️  复用已下载的 chromium：${path.relative(os.homedir(), cached)}`);
    return cached;
  }
  const sys = SYSTEM_BROWSERS.find((p) => fs.existsSync(p));
  if (sys) {
    console.error(`ℹ️  未找到 chromium，改用系统浏览器：${sys}`);
    return sys;
  }
  throw new Error(
    '没有可用的浏览器（puppeteer chromium / 系统 Chrome / Edge 都没找到）。\n' +
      '下载一次即可：npx --prefix ~/.cache/vft-kit/render puppeteer browsers install chrome',
  );
}

function parseArgs(argv) {
  const a = { selector: '#shot', scale: 3, install: true };
  const rest = [];
  for (let i = 0; i < argv.length; i++) {
    const t = argv[i];
    if (t === '--selector') a.selector = argv[++i];
    else if (t === '--scale') a.scale = Number(argv[++i]);
    else if (t === '--no-install') a.install = false;
    else rest.push(t);
  }
  a.input = rest[0];
  a.output = rest[1];
  return a;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (!args.input || !args.output) {
    console.error('用法: node render.mjs <input.html> <output.png> [--selector "#shot"] [--scale 3] [--no-install]');
    console.error('提示: 图宽由 HTML 里 #shot 的 width 决定，不是命令行参数。');
    process.exit(1);
  }
  if (!fs.existsSync(args.input)) {
    console.error(`输入文件不存在: ${args.input}`);
    process.exit(1);
  }
  fs.mkdirSync(path.dirname(path.resolve(args.output)), { recursive: true });

  const ppPath = resolvePuppeteer(args.install);
  const puppeteer = (await import(pathToFileURL(ppPath).href)).default;
  const executablePath = pickBrowser(puppeteer);

  const browser = await puppeteer.launch({
    headless: true,
    executablePath,
    args: ['--no-sandbox', '--font-render-hinting=none'],
  });
  try {
    const page = await browser.newPage();
    await page.setViewport({ width: 1400, height: 900, deviceScaleFactor: args.scale || 3 });
    await page.goto(pathToFileURL(path.resolve(args.input)).href, { waitUntil: 'load' });
    // 字体没就绪就截图会截到 fallback 字形（中文尤其明显）
    await page.evaluate(() => document.fonts.ready);

    const el = await page.$(args.selector);
    if (!el) {
      console.error(`⚠️  未找到 ${args.selector}，退化为整页截图（信息图应把内容包在 #shot 里）`);
      await page.screenshot({ path: args.output, fullPage: true });
    } else {
      const overflow = await page.$eval(args.selector, (n) => {
        const bad = [];
        const walk = (e) => {
          if (e.scrollWidth > e.clientWidth + 1) {
            bad.push(`${e.tagName.toLowerCase()}${e.className ? '.' + String(e.className).split(' ')[0] : ''} 超出 ${e.scrollWidth - e.clientWidth}px`);
          }
          for (const c of e.children) walk(c);
        };
        walk(n);
        return bad.slice(0, 5);
      });
      if (overflow.length) {
        console.error('⚠️  检测到内容横向溢出，图上会截断/错行，建议调宽 #shot 的 width 后重渲：');
        overflow.forEach((o) => console.error(`   - ${o}`));
      }
      await el.screenshot({ path: args.output });
    }
    console.log(`✓ 已生成: ${args.output}`);
  } finally {
    await browser.close();
  }
}

main().catch((e) => {
  console.error('❌ 渲染失败:', e?.message || e);
  process.exit(1);
});
