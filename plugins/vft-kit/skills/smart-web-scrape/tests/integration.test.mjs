#!/usr/bin/env node
/**
 * 集成测试 - smart-web-scrape
 * 测试场景识别、工具选择、fallback 机制
 */

import { execSync } from 'child_process';
import { existsSync, rmSync, readFileSync } from 'fs';
import { join } from 'path';
import { fileURLToPath } from 'url';
import { dirname } from 'path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const SCRAPE_SCRIPT = join(__dirname, '../scripts/scrape.mjs');
const TEST_OUT_DIR = join(__dirname, '../../../../../../../other/scrape-test');

// 测试用例
const TEST_CASES = [
  {
    name: '文档站自动识别',
    url: 'https://docs.python.org/3/library/asyncio.html',
    intent: '',
    expectedTool: 'crawl4ai',
    skipIfMissing: ['crawl4ai'],
  },
  {
    name: 'Markdown 意图',
    url: 'https://example.com',
    intent: '转成 Markdown 喂给 LLM',
    expectedTool: 'crawl4ai',
    skipIfMissing: ['crawl4ai'],
  },
  {
    name: '反爬意图',
    url: 'https://example.com',
    intent: '这个站有 Cloudflare 反爬',
    expectedTool: 'scrapling',
    skipIfMissing: ['scrapling'],
  },
  {
    name: '资源抓取意图',
    url: 'https://example.com',
    intent: '需要截图和所有静态资源',
    expectedTool: 'playwright',
    skipIfMissing: ['playwright'],
  },
  {
    name: '强制指定工具',
    url: 'https://example.com',
    args: ['--tool', 'scrapling'],
    expectedTool: 'scrapling',
    skipIfMissing: ['scrapling'],
  },
];

// 颜色输出
const colors = {
  reset: '\x1b[0m',
  green: '\x1b[32m',
  red: '\x1b[31m',
  yellow: '\x1b[33m',
  cyan: '\x1b[36m',
};

function log(msg, color = 'reset') {
  console.log(`${colors[color]}${msg}${colors.reset}`);
}

// 检查 Python 依赖
function checkDependencies() {
  const deps = {
    python: false,
    scrapling: false,
    crawl4ai: false,
    playwright: false,
  };

  try {
    execSync('python3 --version', { stdio: 'pipe' });
    deps.python = true;
  } catch (e) {
    return deps;
  }

  try {
    const output = execSync('python3 -m pip list --format=json', {
      encoding: 'utf8',
      stdio: 'pipe',
    });
    const packages = JSON.parse(output).map(p => p.name.toLowerCase());

    deps.scrapling = packages.includes('scrapling');
    deps.crawl4ai = packages.includes('crawl4ai');
    deps.playwright = packages.includes('playwright');
  } catch (e) {
    // 无法检测
  }

  return deps;
}

// 运行单个测试
function runTest(testCase, deps) {
  log(`\n━━━ ${testCase.name} ━━━`, 'cyan');

  // 检查依赖
  if (testCase.skipIfMissing) {
    const missing = testCase.skipIfMissing.filter(dep => !deps[dep]);
    if (missing.length > 0) {
      log(`⊘ 跳过（缺少依赖: ${missing.join(', ')}）`, 'yellow');
      return { status: 'skipped', reason: `缺少依赖: ${missing.join(', ')}` };
    }
  }

  try {
    // 构建命令
    const args = [
      SCRAPE_SCRIPT,
      testCase.url,
      '--out', TEST_OUT_DIR,
      '--timeout', '30000',
    ];

    if (testCase.intent) {
      args.push('--intent', testCase.intent);
    }

    if (testCase.args) {
      args.push(...testCase.args);
    }

    log(`命令: node ${args.join(' ')}`, 'reset');

    // 执行
    const output = execSync(`node ${args.map(a => JSON.stringify(a)).join(' ')}`, {
      encoding: 'utf8',
      stdio: 'pipe',
      timeout: 60000,
    });

    // 解析输出（最后一行是 JSON）
    const lines = output.trim().split('\n');
    const lastLine = lines[lines.length - 1];
    let result;

    try {
      result = JSON.parse(lastLine);
    } catch (e) {
      log(`⚠️  无法解析输出 JSON，可能不是预期格式`, 'yellow');
      log(`最后一行: ${lastLine}`, 'reset');
      return { status: 'warning', reason: '无法解析输出' };
    }

    // 验证工具选择
    if (testCase.expectedTool && result.tool !== testCase.expectedTool) {
      log(`❌ 失败：预期工具 ${testCase.expectedTool}，实际 ${result.tool}`, 'red');
      return {
        status: 'failed',
        reason: `工具不匹配：预期 ${testCase.expectedTool}，实际 ${result.tool}`,
      };
    }

    // 验证输出目录
    if (!existsSync(result.outDir)) {
      log(`❌ 失败：输出目录不存在 ${result.outDir}`, 'red');
      return { status: 'failed', reason: '输出目录不存在' };
    }

    log(`✅ 成功（工具: ${result.tool}, 耗时: ${result.duration}ms）`, 'green');
    return { status: 'passed', tool: result.tool, duration: result.duration };

  } catch (error) {
    log(`❌ 失败: ${error.message}`, 'red');
    return { status: 'failed', reason: error.message };
  }
}

// 主测试流程
function main() {
  log('\n🧪 smart-web-scrape 集成测试\n', 'cyan');

  // 检查依赖
  log('检查 Python 依赖...', 'reset');
  const deps = checkDependencies();

  if (!deps.python) {
    log('❌ Python 不可用，无法运行测试', 'red');
    process.exit(1);
  }

  log(`  Python: ✅`, 'green');
  log(`  Scrapling: ${deps.scrapling ? '✅' : '❌'}`, deps.scrapling ? 'green' : 'red');
  log(`  Crawl4AI: ${deps.crawl4ai ? '✅' : '❌'}`, deps.crawl4ai ? 'green' : 'red');
  log(`  Playwright: ${deps.playwright ? '✅' : '❌'}`, deps.playwright ? 'green' : 'red');

  // 清理旧测试输出
  if (existsSync(TEST_OUT_DIR)) {
    log(`\n清理旧测试输出: ${TEST_OUT_DIR}`, 'reset');
    rmSync(TEST_OUT_DIR, { recursive: true, force: true });
  }

  // 运行测试
  const results = [];
  for (const testCase of TEST_CASES) {
    const result = runTest(testCase, deps);
    results.push({ name: testCase.name, ...result });
  }

  // 汇总结果
  log('\n━━━ 测试结果汇总 ━━━\n', 'cyan');

  const passed = results.filter(r => r.status === 'passed').length;
  const failed = results.filter(r => r.status === 'failed').length;
  const skipped = results.filter(r => r.status === 'skipped').length;
  const warnings = results.filter(r => r.status === 'warning').length;

  results.forEach(r => {
    const symbol = {
      passed: '✅',
      failed: '❌',
      skipped: '⊘',
      warning: '⚠️',
    }[r.status];

    const color = {
      passed: 'green',
      failed: 'red',
      skipped: 'yellow',
      warning: 'yellow',
    }[r.status];

    const info = r.reason ? ` (${r.reason})` : r.tool ? ` (${r.tool})` : '';
    log(`${symbol} ${r.name}${info}`, color);
  });

  log(`\n总计: ${results.length} | 通过: ${passed} | 失败: ${failed} | 跳过: ${skipped} | 警告: ${warnings}\n`, 'cyan');

  // 退出码
  if (failed > 0) {
    log('❌ 测试失败', 'red');
    process.exit(1);
  } else if (passed === 0) {
    log('⚠️  没有测试通过（全部跳过）', 'yellow');
    process.exit(0);
  } else {
    log('✅ 所有测试通过', 'green');
    process.exit(0);
  }
}

main();
