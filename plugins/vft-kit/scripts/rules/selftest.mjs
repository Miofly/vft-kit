#!/usr/bin/env node
/**
 * 规则模块自测：node scripts/rules/selftest.mjs
 * 在临时目录搭一个假项目，按钩子协议喂 stdin，校验注入、检查、项目继承与覆盖。
 */
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'vft-rules-selftest-'));
const dataDir = path.join(tmp, '.plugin-data');
const env = { ...process.env, CLAUDE_PLUGIN_DATA: dataDir, VFT_PLUGIN_ROOT: path.resolve(here, '../..') };

const write = (rel, content) => {
  const file = path.join(tmp, rel);
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, content);
  return file;
};

const run = (script, input, args = []) => {
  const r = spawnSync('node', [path.join(here, script), ...args], {
    input: input ? JSON.stringify(input) : undefined,
    env,
    cwd: tmp,
    encoding: 'utf8',
  });
  return { ...r, json: r.stdout.trim().startsWith('{') ? JSON.parse(r.stdout) : null };
};

let passed = 0;
const test = (name, fn) => {
  fn();
  passed++;
  console.log(`✓ ${name}`);
};

write('node_modules/vue/package.json', JSON.stringify({ version: '3.5.40' }));
const bad = write(
  'src/bad.vue',
  `<script setup lang="tsx">
const props = withDefaults(defineProps<{ a?: number }>(), { a: 1 });
const col = { render: () => <el-button v-auth="'x:y'">ok</el-button> };
</script>

<template>
  <div>
    <li v-for="i in list" v-if="i.ok" :key="i.id">{{ i }}</li>
    <span v-for="i in list">{{ i }}</span>
  </div>
</template>
`,
);
const good = write(
  'src/good.vue',
  `<script setup lang="ts">
const { a = 1 } = defineProps<{ a?: number }>();
</script>

<template>
  <ul>
    <template v-for="i in list" :key="i.id">
      <li v-if="i.ok">{{ i.a > a ? 1 : 2 }}</li>
    </template>
  </ul>
</template>
`,
);

test('bad.vue：error 级检查阻断，warn 一并列出', () => {
  const r = run('check.mjs', { session_id: 's1', cwd: tmp, tool_input: { file_path: bad } });
  assert.equal(r.json?.decision, 'block');
  for (const id of ['no-with-defaults', 'no-v-if-with-v-for', 'tsx-no-quoted-directive', 'tsx-no-kebab-component', 'v-for-needs-key'])
    assert.match(r.json.reason, new RegExp(id), `缺少 ${id}`);
  assert.match(r.json.reason, /bad\.vue:2 \(no-with-defaults\)/);
});

test('good.vue：无输出（属性值里的 > 不误判）', () => {
  const r = run('check.mjs', { session_id: 's1', cwd: tmp, tool_input: { file_path: good } });
  assert.equal(r.stdout.trim(), '');
});

test('CLI 模式：有 error 退出码 1', () => {
  const r = spawnSync('node', [path.join(here, 'check.mjs'), bad], { env, cwd: tmp, encoding: 'utf8' });
  assert.equal(r.status, 1);
  assert.match(r.stdout, /no-with-defaults/);
});

test('注入：首次命中注入规则正文，同会话第二次不重复', () => {
  const first = run('inject.mjs', { session_id: 's2', cwd: tmp, tool_input: { file_path: good } });
  assert.match(first.json.hookSpecificOutput.additionalContext, /<vft-rule name="vue-sfc">/);
  const second = run('inject.mjs', { session_id: 's2', cwd: tmp, tool_input: { file_path: bad } });
  assert.equal(second.stdout.trim(), '');
});

test('reset：压缩后重新注入', () => {
  run('reset.mjs', { session_id: 's2' });
  const again = run('inject.mjs', { session_id: 's2', cwd: tmp, tool_input: { file_path: good } });
  assert.ok(again.json);
});

test('非匹配文件不注入', () => {
  const ts = write('src/a.ts', 'export {}');
  const r = run('inject.mjs', { session_id: 's3', cwd: tmp, tool_input: { file_path: ts } });
  assert.equal(r.stdout.trim(), '');
});

// ---- 项目继承 + 私有规则 ----
write(
  '.claude/vft-rules/vue.md',
  `---
name: my-vue
extends: vue-sfc
checks:
  - no-v-loading
---
- 加载态用 v-spin，不用 v-loading。
`,
);
write(
  '.claude/vft-rules/api.md',
  `---
name: my-api
paths:
  - 'src/apis/**/*.ts'
checks:
  - no-axios-direct
---
- 接口统一走 request 封装。
`,
);
write(
  '.claude/vft-rules/checks.mjs',
  `export default {
  'no-v-loading': {
    level: 'error',
    run: ({ src }) => (/\\sv-loading[\\s=>]/.test(src) ? [{ line: 1, message: '用 v-spin' }] : []),
  },
  'no-axios-direct': {
    level: 'warn',
    run: ({ src }) => (src.includes("from 'axios'") ? [{ line: 1, message: '走 request 封装' }] : []),
  },
};
`,
);
const loading = write('src/loading.vue', '<template>\n  <div v-loading="x"></div>\n</template>\n');
const api = write('src/apis/user.ts', "import axios from 'axios';\n");

test('项目 extends：正文追加到插件规则后面', () => {
  const r = run('inject.mjs', { session_id: 's4', cwd: tmp, tool_input: { file_path: good } });
  const ctx = r.json.hookSpecificOutput.additionalContext;
  assert.match(ctx, /Vue SFC 规范/);
  assert.match(ctx, /## 补充（[\s\S]*v-spin/);
});

test('项目私有检查：继承规则上追加的 check 生效', () => {
  const r = run('check.mjs', { session_id: 's4', cwd: tmp, tool_input: { file_path: loading } });
  assert.equal(r.json?.decision, 'block');
  assert.match(r.json.reason, /no-v-loading/);
});

test('项目新增规则：非 vue 文件也能注入与检查', () => {
  const inj = run('inject.mjs', { session_id: 's5', cwd: tmp, tool_input: { file_path: api } });
  assert.match(inj.json.hookSpecificOutput.additionalContext, /my-api/);
  const chk = run('check.mjs', { session_id: 's5', cwd: tmp, tool_input: { file_path: api } });
  assert.match(chk.json.hookSpecificOutput.additionalContext, /no-axios-direct/);
});

test('vft-rules.json：级别覆盖与 disable', () => {
  write('.claude/vft-rules.json', JSON.stringify({ checks: { 'no-with-defaults': 'off', 'tsx-no-quoted-directive': 'off', 'no-v-if-with-v-for': 'warn' } }));
  const r = run('check.mjs', { session_id: 's6', cwd: tmp, tool_input: { file_path: bad } });
  assert.equal(r.json.decision, undefined);
  assert.doesNotMatch(r.json.hookSpecificOutput.additionalContext, /no-with-defaults/);
  write('.claude/vft-rules.json', JSON.stringify({ disable: ['vue-sfc'] }));
  const d = run('inject.mjs', { session_id: 's7', cwd: tmp, tool_input: { file_path: good } });
  assert.equal(d.stdout.trim(), '');
});

test('逐级合并：子项目在仓库级规则上继续追加，仓库级规则不丢', () => {
  fs.rmSync(path.join(tmp, '.claude/vft-rules.json'));
  write(
    'packages/app/.claude/vft-rules/app.md',
    `---
name: app-vue
extends: vue-sfc
---
- 子项目：表单统一用 useForm。
`,
  );
  write('packages/app/.claude/vft-rules.json', JSON.stringify({ checks: { 'no-v-loading': 'warn' } }));
  const sub = write('packages/app/src/page.vue', '<template>\n  <div v-loading="x"></div>\n</template>\n');
  const inj = run('inject.mjs', { session_id: 's9', cwd: tmp, tool_input: { file_path: sub } });
  const ctx = inj.json.hookSpecificOutput.additionalContext;
  assert.match(ctx, /v-spin[\s\S]*useForm/, '仓库级补充在前、子项目补充在后');
  const chk = run('check.mjs', { session_id: 's9', cwd: tmp, tool_input: { file_path: sub } });
  assert.equal(chk.json.decision, undefined, '子项目把 no-v-loading 降为 warn');
  assert.match(chk.json.hookSpecificOutput.additionalContext, /no-v-loading/);
});

test('Vue < 3.5 不检查 withDefaults', () => {
  write('node_modules/vue/package.json', JSON.stringify({ version: '3.4.0' }));
  const r = run('check.mjs', { session_id: 's8', cwd: tmp, tool_input: { file_path: bad } });
  assert.doesNotMatch(r.json.reason, /no-with-defaults/);
});

test('异常输入静默放行', () => {
  const r = spawnSync('node', [path.join(here, 'check.mjs')], { input: 'not json', env, encoding: 'utf8' });
  assert.equal(r.status, 0);
  assert.equal(r.stdout, '');
});

fs.rmSync(tmp, { recursive: true, force: true });
console.log(`\n全部通过：${passed} 项`);
