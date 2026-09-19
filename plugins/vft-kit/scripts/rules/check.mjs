#!/usr/bin/env node
/**
 * 规则检查：对刚写入的文件运行匹配规则里声明的 checks。
 *
 * 钩子模式（PostToolUse，matcher: Edit|Write|MultiEdit）：
 *   - 有 error → 输出 { decision: 'block', reason }，模型收到后必须修复
 *   - 只有 warn → 以 additionalContext 提示，不阻断
 *   - 任何内部异常都静默放行，绝不影响会话
 *
 * CLI 模式（Codex 或手动）：
 *   node scripts/rules/check.mjs <file...>   # 有 error 时退出码 1
 */
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

import { matchRules, readHookInput } from './lib.mjs';
import { splitSfc, vueChecks } from './checks/vue.mjs';
import { styleChecks, styleExts } from './checks/style.mjs';

/** 内置检查：vue 类检查只对 .vue 生效，样式类检查对 .vue 与样式文件生效 */
const builtinChecks = {
  ...Object.fromEntries(Object.entries(vueChecks).map(([id, c]) => [id, { ...c, exts: ['.vue'] }])),
  ...Object.fromEntries(Object.entries(styleChecks).map(([id, c]) => [id, { ...c, exts: styleExts }])),
};

/** 各级私有检查：<root>/.claude/vft-rules/checks.mjs 的 default export，由外到内合并，同名内层覆盖 */
async function loadProjectChecks(roots) {
  const merged = {};
  for (const root of roots) {
    const file = path.join(root, '.claude', 'vft-rules', 'checks.mjs');
    if (!fs.existsSync(file)) continue;
    const mod = await import(`${pathToFileURL(file).href}?t=${fs.statSync(file).mtimeMs}`);
    Object.assign(merged, mod.default || {});
  }
  return merged;
}

async function checkFile(filePath, cwd) {
  const { rules, config, roots, abs } = matchRules(filePath, cwd);
  const ids = [...new Set(rules.flatMap(r => r.checks))];
  if (!ids.length || !fs.existsSync(abs)) return [];

  const registry = { ...builtinChecks, ...(await loadProjectChecks(roots)) };
  const src = fs.readFileSync(abs, 'utf8');
  const blocks = abs.endsWith('.vue') ? splitSfc(src) : null;
  const levels = config.checks;
  const results = [];
  for (const id of ids) {
    const check = registry[id];
    if (!check) continue;
    const exts = check.exts || (check.ext ? [check.ext] : null); // ext 为旧写法，私有检查仍可用
    if (exts && !exts.some(ext => abs.endsWith(ext))) continue;
    const level = levels[id] || check.level || 'error';
    if (level === 'off') continue;
    for (const hit of check.run({ src, blocks, filePath: abs }) || [])
      results.push({ id, level, file: abs, ...hit });
  }
  return results;
}

function format(results, cwd) {
  return results
    .map(r => `- [${r.level}] ${path.relative(cwd, r.file) || r.file}:${r.line} (${r.id}) ${r.message}`)
    .join('\n');
}

async function main() {
  const args = process.argv.slice(2);
  const input = args.length ? null : await readHookInput();

  if (!input) {
    // CLI 模式
    const cwd = process.cwd();
    const results = (await Promise.all(args.map(f => checkFile(f, cwd)))).flat();
    if (results.length) console.log(format(results, cwd));
    else console.log('vft-kit rules: 没有发现问题');
    process.exit(results.some(r => r.level === 'error') ? 1 : 0);
  }

  const filePath = input.tool_input?.file_path;
  if (!filePath) return;
  const cwd = input.cwd || process.cwd();
  const results = await checkFile(filePath, cwd);
  if (!results.length) return;

  const errors = results.filter(r => r.level === 'error');
  const warns = results.filter(r => r.level !== 'error');
  const out = {};
  if (errors.length) {
    out.decision = 'block';
    out.reason = `vft-kit 规则检查未通过，请按规范修复后再继续：\n${format(errors, cwd)}${
      warns.length ? `\n\n同时注意：\n${format(warns, cwd)}` : ''
    }`;
  } else {
    out.hookSpecificOutput = {
      hookEventName: 'PostToolUse',
      additionalContext: `vft-kit 规则提示（不阻断，建议修正）：\n${format(warns, cwd)}`,
    };
  }
  process.stdout.write(JSON.stringify(out));
}

main().catch(err => {
  if (process.env.VFT_RULES_DEBUG) console.error(err);
  process.exit(0);
});
