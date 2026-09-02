#!/usr/bin/env node
/**
 * web-scrape - 智能网页抓取调度器
 * 根据场景自动选择 Scrapling / Crawl4AI / ego-lite / Playwright
 */

import { spawn, execSync } from 'child_process';
import { existsSync, mkdirSync, writeFileSync, readFileSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';
import https from 'https';
import http from 'http';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// ============== 配置 ==============

const CONFIG = {
  // 默认输出目录（相对 CWD）
  defaultOutDir: process.env.SCRAPE_OUT_DIR || 'other/scrape',

  // 代理列表（环境变量或配置）
  proxyList: (process.env.SCRAPE_PROXY_LIST || '').split(',').filter(Boolean),

  // 默认超时
  defaultTimeout: 60000,
  defaultWait: 1500,

  // Python 可执行文件路径
  pythonCmd: process.env.PYTHON_CMD || 'python3',

  // 工具优先级（fallback 顺序）
  fallbackChain: ['scrapling', 'ego', 'playwright', 'crawl4ai'],
};

// ============== 参数解析 ==============

function parseArgs() {
  const args = process.argv.slice(2);

  if (args.length === 0 || args.includes('--help') || args.includes('-h')) {
    printUsage();
    process.exit(0);
  }

  const options = {
    url: args[0],
    tool: null,
    intent: '',
    out: CONFIG.defaultOutDir,
    format: 'html',
    deep: false,
    maxPages: 10,
    strategy: 'bfs',
    adaptive: false,
    stealth: true,
    headless: true,
    wait: CONFIG.defaultWait,
    timeout: CONFIG.defaultTimeout,
    resources: true,
    screenshot: true,
    storageState: null,
    browser: 'chromium',
    userAgent: null,
    pdf: true,
  };

  for (let i = 1; i < args.length; i++) {
    const arg = args[i];
    const next = args[i + 1];

    switch (arg) {
      case '--tool':
        options.tool = next;
        i++;
        break;
      case '--intent':
        options.intent = next;
        i++;
        break;
      case '--out':
        options.out = next;
        i++;
        break;
      case '--format':
        options.format = next;
        i++;
        break;
      case '--deep':
        options.deep = true;
        break;
      case '--max-pages':
        options.maxPages = parseInt(next, 10);
        i++;
        break;
      case '--strategy':
        options.strategy = next;
        i++;
        break;
      case '--adaptive':
        options.adaptive = true;
        break;
      case '--stealth':
        options.stealth = next !== 'false';
        if (next === 'false') i++;
        break;
      case '--headless':
        options.headless = next !== 'false';
        if (next === 'false') i++;
        break;
      case '--wait':
        options.wait = parseInt(next, 10);
        i++;
        break;
      case '--timeout':
        options.timeout = parseInt(next, 10);
        i++;
        break;
      case '--storage-state':
        options.storageState = next;
        i++;
        break;
      case '--browser':
        options.browser = next;
        i++;
        break;
      case '--ua':
        options.userAgent = next;
        i++;
        break;
      case '--no-resources':
        options.resources = false;
        break;
      case '--no-screenshot':
        options.screenshot = false;
        break;
      case '--no-pdf':
        options.pdf = false;
        break;
      default:
        if (arg.startsWith('--')) {
          console.error(`❌ 未知选项: ${arg}`);
          process.exit(1);
        }
    }
  }

  if (!options.url) {
    console.error('❌ 缺少 URL 参数');
    printUsage();
    process.exit(1);
  }

  return options;
}

function printUsage() {
  console.log(`
用法: node scrape.mjs <url> [options]

选项:
  --tool <name>        强制使用工具: scrapling / crawl4ai / ego / playwright
  --intent <text>      用户意图描述（用于场景识别）
  --out <dir>          输出目录（默认: other/scrape）
  --format <type>      输出格式: html / markdown / json（默认: html）
  --deep               启用深度爬取
  --max-pages <n>      深度爬取最大页数（默认: 10）
  --strategy <s>       深度爬取策略: bfs / dfs / best-first（默认: bfs）
  --adaptive           启用自适应解析（仅 Scrapling）
  --stealth [bool]     启用隐蔽模式（默认: true）
  --headless [bool]    无头模式（默认: true）
  --wait <ms>          页面加载后等待时间（默认: 1500）
  --timeout <ms>       单页超时（默认: 60000）
  --storage-state <f>  Playwright storageState 文件
  --browser <name>     Playwright 浏览器: chromium / firefox / webkit
  --ua <text>          Playwright User-Agent
  --no-resources       不下载静态资源（仅 Playwright）
  --no-screenshot      不生成截图
  --no-pdf             不生成 PDF（仅 Playwright）

示例:
  # 自动选择工具
  node scrape.mjs https://docs.python.org --intent "转成 Markdown"

  # 深度爬取文档站
  node scrape.mjs https://example.com/docs --deep --max-pages 50

  # 强制使用 Scrapling 自适应模式
  node scrape.mjs https://example.com --tool scrapling --adaptive
`);
}

// ============== 工具选择算法 ==============

async function selectTool(url, intent, options) {
  // 1. 强制指定
  if (options.tool) {
    console.log(`🎯 强制使用工具: ${options.tool}`);
    return options.tool;
  }

  // 2. 意图关键词匹配
  const intentLower = intent.toLowerCase();

  if (/markdown|llm|喂给|训练|rag|总结|问答/.test(intentLower)) {
    console.log('🎯 检测到 LLM/Markdown 意图 → Crawl4AI');
    return 'crawl4ai';
  }

  if (/批量|深度|递归|whole\s*site|整站|多页/.test(intentLower)) {
    console.log('🎯 检测到深度爬取意图 → Crawl4AI');
    return 'crawl4ai';
  }

  if (/cloudflare|turnstile|反爬|被拦|403|bot.*detect/.test(intentLower)) {
    console.log('🎯 检测到反爬绕过需求 → Scrapling');
    return 'scrapling';
  }

  if (/自适应|网站改版|元素找不到|dom.*变化/.test(intentLower)) {
    console.log('🎯 检测到自适应需求 → Scrapling');
    return 'scrapling';
  }

  if (/资源|网络请求|接口|xhr|fetch|api.*调用/.test(intentLower)) {
    console.log('🎯 检测到资源/网络监控需求 → Playwright');
    return 'playwright';
  }

  if (/已登录|登录态|人工接管|单页.*交互|截图/.test(intentLower)) {
    console.log('🎯 检测到登录态/单页浏览器需求 → ego-lite');
    return 'ego';
  }

  // 3. URL 模式匹配
  if (/\/(docs?|documentation|wiki|blog|article|post|tutorial|guide)\//i.test(url)) {
    console.log('🎯 检测到文档站 URL 模式 → Crawl4AI');
    return 'crawl4ai';
  }

  // 4. 检测 Cloudflare 防护
  const hasCloudflare = await detectCloudflare(url);
  if (hasCloudflare) {
    console.log('🎯 检测到 Cloudflare 防护 → Scrapling');
    return 'scrapling';
  }

  // 5. 默认策略：快速抓取
  console.log('🎯 默认策略 → Scrapling（快速）');
  return 'scrapling';
}

async function detectCloudflare(url) {
  return new Promise((resolve) => {
    const urlObj = new URL(url);
    const client = urlObj.protocol === 'https:' ? https : http;

    const req = client.request(url, { method: 'HEAD', timeout: 5000 }, (res) => {
      const server = res.headers['server'] || '';
      const cfRay = res.headers['cf-ray'] || '';
      resolve(server.toLowerCase().includes('cloudflare') || !!cfRay);
    });

    req.on('error', () => resolve(false));
    req.on('timeout', () => {
      req.destroy();
      resolve(false);
    });
    req.end();
  });
}

// ============== 依赖检查 ==============

function checkDependencies(tool) {
  const checks = {
    python: false,
    scrapling: false,
    crawl4ai: false,
    playwright: false,
  };

  if (tool === 'ego') {
    try {
      execSync('command -v ego-browser', { stdio: 'ignore', shell: '/bin/sh' });
      return true;
    } catch {
      return false;
    }
  }

  // 检查 Python
  try {
    execSync(`${CONFIG.pythonCmd} --version`, { stdio: 'pipe' });
    checks.python = true;
  } catch (e) {
    // Python 不可用
  }

  if (!checks.python) {
    console.error(`❌ Python 不可用，请安装 Python ≥ 3.8`);
    return false;
  }

  // 检查 Python 包
  try {
    const installed = execSync(`${CONFIG.pythonCmd} -m pip list --format=json`, {
      encoding: 'utf8',
      stdio: 'pipe',
    });
    const packages = JSON.parse(installed).map(p => p.name.toLowerCase());

    checks.scrapling = packages.includes('scrapling');
    checks.crawl4ai = packages.includes('crawl4ai');
    checks.playwright = packages.includes('playwright');
  } catch (e) {
    console.error('⚠️  无法检测 Python 包');
  }

  // 根据工具检查依赖
  const required = [];
  if (tool === 'scrapling' && !checks.scrapling) required.push('scrapling');
  if (tool === 'crawl4ai' && !checks.crawl4ai) required.push('crawl4ai');
  if ((tool === 'playwright' || tool === 'crawl4ai') && !checks.playwright) {
    required.push('playwright');
  }

  if (required.length > 0) {
    console.error(`\n❌ 缺少 Python 依赖: ${required.join(', ')}\n`);
    console.error(`请运行:\n`);
    console.error(`  pip install ${required.join(' ')}`);
    if (required.includes('playwright')) {
      console.error(`  playwright install chromium`);
    }
    console.error(`\n或使用 venv:\n`);
    console.error(`  python3 -m venv ~/.scrape-venv`);
    console.error(`  source ~/.scrape-venv/bin/activate`);
    console.error(`  pip install ${required.join(' ')}`);
    if (required.includes('playwright')) {
      console.error(`  playwright install chromium`);
    }
    console.error();
    return false;
  }

  return true;
}

// ============== 工具执行 ==============

async function runScrapling(url, options, outDir) {
  console.log('\n🚀 使用 Scrapling 抓取...\n');

  const scriptPath = join(__dirname, 'scrapling-worker.py');
  const configPath = join(outDir, 'scrapling-config.json');

  // 写入配置
  writeFileSync(configPath, JSON.stringify({
    url,
    outDir,
    adaptive: options.adaptive,
    stealth: options.stealth,
    headless: options.headless,
    wait: options.wait,
    timeout: options.timeout,
    deep: options.deep,
    maxPages: options.maxPages,
    strategy: options.strategy,
    format: options.format,
  }));

  return new Promise((resolve, reject) => {
    const proc = spawn(CONFIG.pythonCmd, [scriptPath, configPath], {
      stdio: 'inherit',
    });

    proc.on('exit', (code) => {
      if (code === 0) {
        resolve({ tool: 'scrapling', outDir });
      } else {
        reject(new Error(`Scrapling 失败，退出码: ${code}`));
      }
    });

    proc.on('error', reject);
  });
}

async function runCrawl4AI(url, options, outDir) {
  console.log('\n🚀 使用 Crawl4AI 抓取...\n');

  const scriptPath = join(__dirname, 'crawl4ai-worker.py');
  const configPath = join(outDir, 'crawl4ai-config.json');

  writeFileSync(configPath, JSON.stringify({
    url,
    outDir,
    stealth: options.stealth,
    headless: options.headless,
    wait: options.wait,
    timeout: options.timeout,
    deep: options.deep,
    maxPages: options.maxPages,
    strategy: options.strategy,
    format: options.format,
    screenshot: options.screenshot,
  }));

  return new Promise((resolve, reject) => {
    const proc = spawn(CONFIG.pythonCmd, [scriptPath, configPath], {
      stdio: 'inherit',
    });

    proc.on('exit', (code) => {
      if (code === 0) {
        resolve({ tool: 'crawl4ai', outDir });
      } else {
        reject(new Error(`Crawl4AI 失败，退出码: ${code}`));
      }
    });

    proc.on('error', reject);
  });
}

async function runPlaywright(url, options, outDir) {
  console.log('\n🚀 使用 Playwright 抓取...\n');

  const scrapeScript = join(__dirname, 'playwright-worker.mjs');

  if (!existsSync(scrapeScript)) {
    throw new Error('Playwright worker 不可用（未找到脚本）');
  }

  const args = [
    scrapeScript,
    url,
    '--out', outDir,
    '--wait', String(options.wait),
    '--timeout', String(options.timeout),
  ];

  if (!options.resources) args.push('--no-assets');
  if (!options.screenshot) args.push('--no-screenshot');
  if (!options.pdf) args.push('--no-pdf');
  if (!options.headless) args.push('--headed');
  if (options.storageState) args.push('--storage-state', options.storageState);
  if (options.browser) args.push('--browser', options.browser);
  if (options.userAgent) args.push('--ua', options.userAgent);

  return new Promise((resolve, reject) => {
    const proc = spawn('node', args, { stdio: 'inherit' });

    proc.on('exit', (code) => {
      if (code === 0) {
        resolve({ tool: 'playwright', outDir });
      } else {
        reject(new Error(`Playwright 失败，退出码: ${code}`));
      }
    });

    proc.on('error', reject);
  });
}

function runEgoProcess(source) {
  return new Promise((resolve, reject) => {
    const proc = spawn('ego-browser', ['nodejs'], { stdio: ['pipe', 'inherit', 'inherit'] });
    proc.stdin.end(source);
    proc.on('exit', (code) => code === 0 ? resolve() : reject(new Error(`ego-lite 失败，退出码: ${code}`)));
    proc.on('error', reject);
  });
}

async function runEgo(url, options, outDir) {
  console.log('\n🚀 使用 ego-lite 抓取...\n');

  const taskName = `web-scrape ${new URL(url).hostname} ${process.pid}`;
  const htmlPath = join(outDir, 'index.html');
  const screenshotPath = join(outDir, 'screenshot.png');
  const waitSeconds = Math.max(0, Number(options.wait || 0) / 1000);
  const timeoutSeconds = Math.max(1, Math.ceil(Number(options.timeout || CONFIG.defaultTimeout) / 1000));
  const source = `
const { writeFileSync } = await import('node:fs')
const task = await useOrCreateTaskSpace(${JSON.stringify(taskName)})
await openOrReuseTab(${JSON.stringify(url)}, { wait: true, timeout: ${timeoutSeconds} })
await waitForLoad().catch(() => {})
${waitSeconds ? `await wait(${waitSeconds})` : ''}
const html = await js(String.raw\`document.documentElement.outerHTML\`)
writeFileSync(${JSON.stringify(htmlPath)}, html, 'utf8')
${options.screenshot ? `const shot = await cdp('Page.captureScreenshot', { format: 'png', captureBeyondViewport: true })
writeFileSync(${JSON.stringify(screenshotPath)}, Buffer.from(shot.data, 'base64'))` : ''}
cliLog('EGO_SCRAPE_OK task=' + task.id)
`;

  try {
    await runEgoProcess(source);
  } finally {
    await runEgoProcess(`await completeTaskSpace(${JSON.stringify(taskName)}, { keep: false })`).catch(() => {});
  }
  return { tool: 'ego', outDir };
}

// ============== Fallback 机制 ==============

async function executeWithFallback(url, options, outDir, selectedTool) {
  const fallbackChain = selectedTool === 'ego'
    ? ['playwright', 'scrapling', 'crawl4ai']
    : CONFIG.fallbackChain;
  const chain = [selectedTool, ...fallbackChain.filter(t => t !== selectedTool)];
  const errors = [];

  for (const tool of chain) {
    try {
      console.log(`\n┌─ 尝试工具: ${tool}`);

      if (!checkDependencies(tool)) {
        throw new Error(`依赖检查失败: ${tool}`);
      }

      let result;
      if (tool === 'scrapling') {
        result = await runScrapling(url, options, outDir);
      } else if (tool === 'crawl4ai') {
        result = await runCrawl4AI(url, options, outDir);
      } else if (tool === 'playwright') {
        result = await runPlaywright(url, options, outDir);
      } else if (tool === 'ego') {
        result = await runEgo(url, options, outDir);
      }

      console.log(`└─ ✅ ${tool} 成功\n`);
      return result;

    } catch (error) {
      console.error(`└─ ❌ ${tool} 失败: ${error.message}\n`);
      errors.push({ tool, error: error.message });
    }
  }

  // 所有工具都失败
  console.error('\n❌ 所有工具都失败了:\n');
  errors.forEach(({ tool, error }) => {
    console.error(`  - ${tool}: ${error}`);
  });
  throw new Error('所有抓取工具均失败');
}

// ============== 主流程 ==============

async function main() {
  const startTime = Date.now();
  const options = parseArgs();

  console.log(`\n🕷️  web-scrape\n`);
  console.log(`URL: ${options.url}`);
  if (options.intent) console.log(`意图: ${options.intent}`);
  console.log();

  // 选择工具
  const selectedTool = await selectTool(options.url, options.intent, options);

  // 准备输出目录
  const timestamp = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
  const domain = new URL(options.url).hostname.replace(/^www\./, '');
  const outDir = join(process.cwd(), options.out, `${domain}-${timestamp}`);

  if (!existsSync(outDir)) {
    mkdirSync(outDir, { recursive: true });
  }

  console.log(`输出目录: ${outDir}\n`);

  // 执行抓取（带 fallback）
  try {
    const result = await executeWithFallback(options.url, options, outDir, selectedTool);

    // 写入元信息
    const meta = {
      url: options.url,
      tool: result.tool,
      reason: `由场景识别引擎选择（原始: ${selectedTool}）`,
      timestamp: new Date().toISOString(),
      duration_ms: Date.now() - startTime,
      options: {
        format: options.format,
        deep: options.deep,
        adaptive: options.adaptive,
        stealth: options.stealth,
      },
    };

    writeFileSync(join(outDir, 'meta.json'), JSON.stringify(meta, null, 2));

    console.log(`\n✅ 抓取完成！`);
    console.log(`耗时: ${meta.duration_ms}ms`);
    console.log(`使用工具: ${result.tool}`);
    console.log(`输出: ${outDir}\n`);

    // 输出 JSON 供其他工具解析
    console.log(JSON.stringify({
      success: true,
      tool: result.tool,
      outDir,
      duration: meta.duration_ms,
    }));

  } catch (error) {
    console.error(`\n❌ 抓取失败: ${error.message}\n`);
    process.exit(1);
  }
}

main().catch((err) => {
  console.error('❌ 未捕获的错误:', err);
  process.exit(1);
});
