/**
 * Vue SFC 自动检查。只收「能用文本规则可靠判断」的条目，语义类规范留在 rules/vue-sfc.md 由模型遵守。
 * 每个检查返回 [{ line, message }]；level 为默认级别，可被项目 .claude/vft-rules.json 覆盖。
 */
import fs from 'node:fs';
import path from 'node:path';

/** 行号（1 起） */
export const lineAt = (src, index) => src.slice(0, index).split('\n').length;

/** 按块切 SFC：返回 template 与各 script 块（保留原始偏移，用于算行号） */
export function splitSfc(src) {
  const blocks = { template: null, scripts: [] };
  const tplStart = /^<template(\s[^>]*)?>/m.exec(src);
  if (tplStart) {
    // 顶层 template 的结束标签在行首；取最后一个，兼容内部嵌套的 <template v-if>
    const re = /^<\/template>/gm;
    let end = -1;
    let m;
    while ((m = re.exec(src))) end = m.index;
    if (end > tplStart.index) {
      const start = tplStart.index + tplStart[0].length;
      blocks.template = { content: src.slice(start, end), offset: start };
    }
  }
  const scriptRe = /^<script(\s[^>]*)?>([\s\S]*?)^<\/script>/gm;
  let s;
  while ((s = scriptRe.exec(src))) {
    const attrs = s[1] || '';
    const offset = s.index + s[0].indexOf('>') + 1;
    blocks.scripts.push({
      attrs,
      lang: /lang=["']?(\w+)/.exec(attrs)?.[1] || 'js',
      content: s[2],
      offset,
    });
  }
  return blocks;
}

/** 把注释替换成等长空白，保持偏移与行号不变 */
export function blankComments(code) {
  return code
    .replace(/\/\*[\s\S]*?\*\//g, m => m.replace(/[^\n]/g, ' '))
    .replace(/(^|[^:'"`])\/\/[^\n]*/g, (m, p) => p + ' '.repeat(m.length - p.length));
}

/** 扫描模板开始标签，属性值里的 `>` 不会截断标签 */
function* scanTags(tpl) {
  for (let i = 0; i < tpl.length; i++) {
    if (tpl[i] !== '<' || !/[a-zA-Z]/.test(tpl[i + 1] || '')) continue;
    if (tpl.startsWith('<!--', i)) continue;
    let j = i + 1;
    let quote = null;
    for (; j < tpl.length; j++) {
      const c = tpl[j];
      if (quote) {
        if (c === quote) quote = null;
      } else if (c === '"' || c === "'") quote = c;
      else if (c === '>') break;
    }
    const raw = tpl.slice(i, j + 1);
    const name = /^<([\w-]+)/.exec(raw)?.[1] || '';
    yield { raw, name, index: i };
    i = j;
  }
}

/** 从文件向上找项目实际使用的 vue 版本：优先 node_modules 安装版本，其次 package.json 声明 */
export function vueVersion(filePath) {
  let dir = path.dirname(filePath);
  while (true) {
    const installed = path.join(dir, 'node_modules', 'vue', 'package.json');
    if (fs.existsSync(installed)) {
      try {
        return JSON.parse(fs.readFileSync(installed, 'utf8')).version;
      } catch {
        /* 继续向上 */
      }
    }
    const pkg = path.join(dir, 'package.json');
    if (fs.existsSync(pkg)) {
      try {
        const json = JSON.parse(fs.readFileSync(pkg, 'utf8'));
        const range = json.dependencies?.vue || json.devDependencies?.vue || json.peerDependencies?.vue;
        const v = range && /(\d+)\.(\d+)/.exec(range);
        if (v) return `${v[1]}.${v[2]}.0`;
      } catch {
        /* 继续向上 */
      }
    }
    const parent = path.dirname(dir);
    if (parent === dir) return null;
    dir = parent;
  }
}

const atLeast = (version, major, minor) => {
  const m = /(\d+)\.(\d+)/.exec(version || '');
  if (!m) return true; // 未知版本按新版本处理
  return +m[1] > major || (+m[1] === major && +m[2] >= minor);
};

export const vueChecks = {
  'no-with-defaults': {
    level: 'error',
    run({ src, blocks, filePath }) {
      if (!atLeast(vueVersion(filePath), 3, 5)) return [];
      const out = [];
      for (const s of blocks.scripts) {
        const code = blankComments(s.content);
        const re = /\bwithDefaults\s*\(/g;
        let m;
        while ((m = re.exec(code)))
          out.push({
            line: lineAt(src, s.offset + m.index),
            message:
              'Vue ≥3.5 用解构声明 props 默认值：`const { a = 1 } = defineProps<{ a?: number }>()`，不要用 withDefaults',
          });
      }
      return out;
    },
  },

  'no-v-if-with-v-for': {
    level: 'error',
    run({ src, blocks }) {
      if (!blocks.template) return [];
      const out = [];
      for (const tag of scanTags(blocks.template.content)) {
        if (/\sv-for\s*=/.test(tag.raw) && /\sv-if\s*=/.test(tag.raw))
          out.push({
            line: lineAt(src, blocks.template.offset + tag.index),
            message: `<${tag.name}> 同时使用 v-if 与 v-for：外层包 <template v-for>，或用 computed 先过滤列表`,
          });
      }
      return out;
    },
  },

  'v-for-needs-key': {
    level: 'warn',
    run({ src, blocks }) {
      if (!blocks.template) return [];
      const out = [];
      for (const tag of scanTags(blocks.template.content)) {
        if (/\sv-for\s*=/.test(tag.raw) && !/\s(:key|v-bind:key)\s*=/.test(tag.raw))
          out.push({
            line: lineAt(src, blocks.template.offset + tag.index),
            message: `<${tag.name} v-for> 缺少 :key，请用稳定的业务 id`,
          });
      }
      return out;
    },
  },

  'tsx-no-quoted-directive': {
    level: 'error',
    run({ src, blocks }) {
      const out = [];
      for (const s of blocks.scripts.filter(b => b.lang === 'tsx' || b.lang === 'jsx')) {
        const code = blankComments(s.content);
        const re = /\sv-[\w-]+(?::[\w-]+)?="'/g;
        let m;
        while ((m = re.exec(code)))
          out.push({
            line: lineAt(src, s.offset + m.index),
            message:
              'TSX 里指令值多套了一层引号（v-x="\'a\'" 收到的是带引号的字符串），改成 v-x="a" 或 v-x={\'a\'}',
          });
      }
      return out;
    },
  },

  'tsx-no-kebab-component': {
    level: 'warn',
    run({ src, blocks }) {
      const out = [];
      for (const s of blocks.scripts.filter(b => b.lang === 'tsx' || b.lang === 'jsx')) {
        const code = blankComments(s.content);
        const re = /<([a-z][a-z0-9]*(?:-[a-z0-9]+)+)(?=[\s/>])/g;
        let m;
        while ((m = re.exec(code)))
          out.push({
            line: lineAt(src, s.offset + m.index),
            message: `TSX 里 <${m[1]}> 不会被组件自动导入解析，改为 PascalCase 并显式 import`,
          });
      }
      return out;
    },
  },
};
