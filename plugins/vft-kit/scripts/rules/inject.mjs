#!/usr/bin/env node
/**
 * 规则注入：模型读写文件前，把路径匹配的规则正文作为 additionalContext 注入。
 *
 * 钩子模式（PreToolUse，matcher: Read|Edit|Write|MultiEdit）：
 *   - 同一会话每条规则只注入一次（记录在 CLAUDE_PLUGIN_DATA 或系统临时目录）
 *   - 上下文压缩 / clear 后由 reset 钩子清记录，下次命中重新注入
 *   - 不改变工具调用本身；任何异常静默放行
 *
 * CLI 模式：node scripts/rules/inject.mjs <file>   # 打印该文件适用的规则正文
 */
import { matchRules, readHookInput, readInjected, writeInjected } from './lib.mjs';

async function main() {
  const args = process.argv.slice(2);
  if (args.length) {
    const { rules } = matchRules(args[0]);
    console.log(rules.length ? rules.map(r => r.body).join('\n\n---\n\n') : '没有匹配的规则');
    return;
  }

  const input = await readHookInput();
  const filePath = input?.tool_input?.file_path;
  if (!filePath) return;

  const { rules } = matchRules(filePath, input.cwd || process.cwd());
  if (!rules.length) return;

  const injected = readInjected(input.session_id);
  const fresh = rules.filter(r => !injected.has(r.name));
  if (!fresh.length) return;

  fresh.forEach(r => injected.add(r.name));
  writeInjected(input.session_id, injected);

  const context = fresh
    .map(r => `<vft-rule name="${r.name}">\n${r.body}\n</vft-rule>`)
    .join('\n\n');
  process.stdout.write(
    JSON.stringify({
      hookSpecificOutput: {
        hookEventName: 'PreToolUse',
        additionalContext: `以下是 vft-kit 为 ${filePath} 注入的项目规范，本会话内处理同类文件都必须遵守：\n\n${context}`,
      },
    }),
  );
}

main().catch(err => {
  if (process.env.VFT_RULES_DEBUG) console.error(err);
  process.exit(0);
});
