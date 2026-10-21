/**
 * vft-kit 规则模块公共库：加载 rules/*.md、按路径匹配、读取项目覆盖配置、会话内去重状态。
 *
 * 规则文件格式（rules/<name>.md）：
 * ---
 * name: vue-sfc
 * description: 一句话说明
 * paths:
 *   - '**\/*.vue'
 * checks:
 *   - no-with-defaults
 * ---
 * 正文（注入给模型的规范）
 *
 * 插件不能直接提供 Claude Code 的 `.claude/rules/`（官方只加载项目/用户目录），
 * 所以用 PreToolUse 钩子按路径注入正文、PostToolUse 钩子跑 checks，达到同等效果。
 *
 * 项目扩展（钩子从被操作文件向上查找，所有层级由外到内合并，可在仓库根和子项目各放一份）：
 *   .claude/vft-rules.json        disable 规则 / 覆盖检查级别
 *   .claude/vft-rules/*.md        私有规则；`extends: vue-sfc` 表示继承并追加
 *   .claude/vft-rules/checks.mjs  私有自动检查（default export: { id: { level, run } }）
 */
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export const pluginRoot =
  process.env.VFT_PLUGIN_ROOT ||
  process.env.CLAUDE_PLUGIN_ROOT ||
  process.env.CODEX_PLUGIN_ROOT ||
  path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');

export const rulesDir = path.join(pluginRoot, 'rules');

/** 读取 stdin 的钩子输入；非钩子调用（TTY）返回 null */
export async function readHookInput() {
  if (process.stdin.isTTY) return null;
  let raw = '';
  for await (const chunk of process.stdin) raw += chunk;
  if (!raw.trim()) return null;
  return JSON.parse(raw);
}

/** 只支持规则文件用到的 YAML 子集：`key: value` 与 `key:` + `  - item` 列表 */
export function parseFrontmatter(text) {
  const m = /^---\r?\n([\s\S]*?)\r?\n---\r?\n?/.exec(text);
  if (!m) return { meta: {}, body: text };
  const meta = {};
  let listKey = null;
  for (const line of m[1].split(/\r?\n/)) {
    if (!line.trim() || line.trim().startsWith('#')) continue;
    const item = /^\s+-\s+(.*)$/.exec(line);
    if (item && listKey) {
      meta[listKey].push(unquote(item[1].trim()));
      continue;
    }
    const kv = /^([\w-]+):\s*(.*)$/.exec(line);
    if (!kv) continue;
    const [, key, value] = kv;
    if (value === '') {
      meta[key] = [];
      listKey = key;
    } else {
      meta[key] = unquote(value.trim());
      listKey = null;
    }
  }
  return { meta, body: text.slice(m[0].length) };
}

function unquote(v) {
  return /^(['"]).*\1$/.test(v) ? v.slice(1, -1) : v;
}

/** glob → RegExp，支持 `**`、`*`、`?`、`{a,b}`；`**\/` 可匹配零层目录 */
export function globToRegExp(glob) {
  let re = '';
  for (let i = 0; i < glob.length; i++) {
    const c = glob[i];
    if (c === '*') {
      if (glob[i + 1] === '*') {
        const slash = glob[i + 2] === '/';
        re += slash ? '(?:.*/)?' : '.*';
        i += slash ? 2 : 1;
      } else {
        re += '[^/]*';
      }
    } else if (c === '?') re += '[^/]';
    else if (c === '{') {
      const end = glob.indexOf('}', i);
      re += `(?:${glob
        .slice(i + 1, end)
        .split(',')
        .map(s => s.replace(/[.+^$()|[\]\\]/g, '\\$&'))
        .join('|')})`;
      i = end;
    } else re += c.replace(/[.+^$()|[\]\\]/g, '\\$&');
  }
  return new RegExp(`^${re}$`);
}

/** 读取目录下的规则文件（`_` 开头的文件视为草稿，不加载） */
function readRuleDir(dir, source) {
  if (!fs.existsSync(dir)) return [];
  return fs
    .readdirSync(dir)
    .filter(f => f.endsWith('.md') && !f.startsWith('_'))
    .map(f => {
      const file = path.join(dir, f);
      const { meta, body } = parseFrontmatter(fs.readFileSync(file, 'utf8'));
      return {
        name: meta.name || path.basename(f, '.md'),
        description: meta.description || '',
        extends: meta.extends || null,
        paths: Array.isArray(meta.paths) ? meta.paths : [],
        checks: Array.isArray(meta.checks) ? meta.checks : [],
        body: body.trim(),
        file,
        source,
      };
    });
}

/**
 * 合并插件规则与项目规则：
 * - 项目规则写 `extends: <插件规则名>`：继承其 paths / checks / 正文，并在后面追加项目正文与 checks
 * - 项目规则与插件规则同名且不写 extends：整条替换
 * - 其余项目规则：新增
 */
export function loadRules(projectRoots = []) {
  const byName = new Map(readRuleDir(rulesDir, 'plugin').map(r => [r.name, r]));
  // 由外到内逐级合并：仓库级 → 子项目级，内层可以继续 extends 外层已合并的结果
  for (const root of projectRoots) {
    for (const r of readRuleDir(path.join(root, '.claude', 'vft-rules'), root)) {
      const base = r.extends && byName.get(r.extends);
      if (base) {
        byName.set(base.name, {
          ...base,
          paths: r.paths.length ? r.paths : base.paths,
          checks: [...new Set([...base.checks, ...r.checks])],
          body: `${base.body}\n\n## 补充（${path.basename(root)}/${path.relative(root, r.file)}）\n\n${r.body}`,
          source: `${base.source}+${root}`,
        });
      } else {
        byName.set(r.name, r);
      }
    }
  }
  return [...byName.values()].map(r => ({ ...r, matchers: r.paths.map(globToRegExp) }));
}

/**
 * 从文件所在目录向上收集所有含 `.claude/vft-rules.json` 或 `.claude/vft-rules/` 的目录。
 * 返回由外到内的 roots（仓库级在前、子项目级在后）与合并后的 config：
 * disable 取并集，checks 级别内层覆盖外层。
 */
export function findProjects(filePath) {
  const roots = [];
  let dir = path.dirname(path.resolve(filePath));
  while (true) {
    const claudeDir = path.join(dir, '.claude');
    if (
      fs.existsSync(path.join(claudeDir, 'vft-rules.json')) ||
      fs.existsSync(path.join(claudeDir, 'vft-rules'))
    )
      roots.unshift(dir);
    const parent = path.dirname(dir);
    if (parent === dir) break;
    dir = parent;
  }
  const config = { disable: [], checks: {} };
  for (const root of roots) {
    const cfgFile = path.join(root, '.claude', 'vft-rules.json');
    if (!fs.existsSync(cfgFile)) continue;
    try {
      const c = JSON.parse(fs.readFileSync(cfgFile, 'utf8'));
      config.disable.push(...(c.disable || []));
      Object.assign(config.checks, c.checks || {});
    } catch {
      /* 配置写坏了就忽略这一层，不影响会话 */
    }
  }
  return { roots, config };
}

/** 找出适用于该文件的规则（已排除 disable 的）。paths 相对最近一级规则根、cwd 与文件名匹配 */
export function matchRules(filePath, cwd = process.cwd()) {
  const abs = path.resolve(cwd, filePath);
  const { roots, config } = findProjects(abs);
  const disabled = new Set(config.disable);
  const candidates = [...roots.map(r => path.relative(r, abs)), path.relative(cwd, abs), path.basename(abs)]
    .filter(Boolean)
    .map(p => p.split(path.sep).join('/'))
    .filter(p => !p.startsWith('..'));
  const rules = loadRules(roots).filter(
    r => !disabled.has(r.name) && r.matchers.some(re => candidates.some(c => re.test(c))),
  );
  return { rules, config, roots, abs };
}

/** 会话内已注入的规则记录，避免每次读写同类文件都重复注入 */
function stateFile(sessionId) {
  const dir = process.env.CLAUDE_PLUGIN_DATA
    ? path.join(process.env.CLAUDE_PLUGIN_DATA, 'rules-state')
    : path.join(os.tmpdir(), 'vft-kit-rules-state');
  fs.mkdirSync(dir, { recursive: true });
  return path.join(dir, `${String(sessionId).replace(/[^\w-]/g, '_')}.json`);
}

export function readInjected(sessionId) {
  if (!sessionId) return new Set();
  try {
    return new Set(JSON.parse(fs.readFileSync(stateFile(sessionId), 'utf8')));
  } catch {
    return new Set();
  }
}

export function writeInjected(sessionId, names) {
  if (!sessionId) return;
  fs.writeFileSync(stateFile(sessionId), JSON.stringify([...names]));
}

/** 清掉会话注入记录（上下文压缩后规则正文已丢，需要重新注入） */
export function resetInjected(sessionId) {
  if (!sessionId) return;
  try {
    fs.rmSync(stateFile(sessionId));
  } catch {
    /* 没有记录就不用清 */
  }
}
