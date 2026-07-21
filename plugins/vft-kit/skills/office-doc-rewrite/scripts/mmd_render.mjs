// mermaid → 高清 PNG (playwright)。附带导出图内所有文字节点,供无法看图时验证内容完整。
// 依赖: 全局 playwright(本仓已装); 首次运行自动下载 mermaid.min.js 到 skill 的 assets/。
// 用法:
//   node mmd_render.mjs <input.mmd> <output.png> [scale=4]
//   node mmd_render.mjs --check <input.mmd>            # 只导出文字节点,不渲染(验证内容)
import { createRequire } from 'module';
import path from 'path';
import { fileURLToPath } from 'url';
import { readFileSync, existsSync, writeFileSync } from 'fs';
import { execSync } from 'child_process';

const require = createRequire(import.meta.url);
const __dir = path.dirname(fileURLToPath(import.meta.url));
const MERMAID_JS = path.join(__dir, '..', 'assets', 'mermaid.min.js');

function loadPlaywright() {
  const g = execSync('npm root -g').toString().trim();
  return require(path.join(g, 'playwright'));
}
function ensureMermaid() {
  if (existsSync(MERMAID_JS)) return;
  console.error('[mmd] 下载 mermaid.min.js ...');
  execSync(`mkdir -p "${path.dirname(MERMAID_JS)}" && curl -sL "https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js" -o "${MERMAID_JS}"`);
}

const args = process.argv.slice(2);
const checkOnly = args[0] === '--check';
const inFile = checkOnly ? args[1] : args[0];
const outFile = checkOnly ? null : args[1];
const scale = Number(args[2] || 4);

ensureMermaid();
const code = readFileSync(inFile, 'utf8');
const mermaidJs = readFileSync(MERMAID_JS, 'utf8');

const html = `<!DOCTYPE html><html><head><meta charset="utf-8"><style>
*{margin:0;padding:0;box-sizing:border-box}
body{background:#fff;padding:32px;font-family:"PingFang SC","Microsoft YaHei",sans-serif}
#d{display:inline-block}
</style></head><body><div id="d" class="mermaid">${code}</div>
<script>${mermaidJs}</script>
<script>
mermaid.initialize({startOnLoad:false,theme:'base',themeVariables:{
  fontFamily:'"PingFang SC","Microsoft YaHei",sans-serif',fontSize:'16px',
  primaryColor:'#eaf2ff',primaryBorderColor:'#4a7fe0',primaryTextColor:'#1a2b4a',
  lineColor:'#5a6b8c',secondaryColor:'#f0f4fa',tertiaryColor:'#fafbfe'},
  flowchart:{curve:'basis',htmlLabels:true,nodeSpacing:50,rankSpacing:60},
  sequence:{actorMargin:60,width:150,useMaxWidth:false}});
window.__done=false;
mermaid.run({querySelector:'.mermaid'}).then(()=>window.__done=true).catch(e=>window.__err=String(e));
</script></body></html>`;

const { chromium } = loadPlaywright();
const browser = await chromium.launch({ headless: true });
const page = await browser.newPage({ deviceScaleFactor: scale });
await page.setContent(html, { waitUntil: 'networkidle' });
await page.waitForFunction('window.__done===true || window.__err', { timeout: 20000 }).catch(() => {});
const err = await page.evaluate('window.__err');
if (err) { console.error('mermaid 渲染错误:', err); await browser.close(); process.exit(1); }

// 导出文字节点(验证内容完整,尤其在看不到图时)
const texts = await page.evaluate(() =>
  [...new Set([...document.querySelectorAll('.mermaid text,.mermaid .nodeLabel,.mermaid span.nodeLabel')]
    .map(t => t.textContent.trim()).filter(Boolean))]);
console.error(`[文字节点 ${texts.length}] ` + texts.join(' | '));

if (!checkOnly) {
  const el = await page.$('#d');
  await el.screenshot({ path: outFile });
  const box = await el.boundingBox();
  console.log(`✓ ${outFile} (${Math.round(box.width)}x${Math.round(box.height)} @${scale}x)`);
}
await browser.close();
