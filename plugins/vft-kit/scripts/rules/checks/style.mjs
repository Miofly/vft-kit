/**
 * 样式布局自动检查（配合 rules/style-layout.md）。
 * 对 .vue 看 <style> 块和模板里的内联 style，对 css/scss/sass/less/styl 看全文；注释先替换成等长空白，行号不变。
 */
import { blankComments, lineAt, splitSfc, vueVersion } from './vue.mjs';

export const styleExts = ['.vue', '.css', '.scss', '.sass', '.less', '.styl'];

/** 取出可检查的样式片段：[{ content, offset }]，offset 为片段在原文件中的起点 */
function styleBlocks(src, filePath) {
  if (!filePath.endsWith('.vue')) return [{ content: blankComments(src), offset: 0 }];
  const out = [];
  const re = /^<style(\s[^>]*)?>([\s\S]*?)^<\/style>/gm;
  let m;
  while ((m = re.exec(src)))
    out.push({ content: blankComments(m[2]), offset: m.index + m[0].indexOf('>') + 1 });
  return out;
}

/**
 * 逐层收集每个规则块「自身」的声明文本（不含嵌套子块），兼容 scss/less 嵌套。
 * 返回 [{ decls, start }]，start 为块内首字符在片段中的偏移。
 */
function ruleBlocks(css) {
  const blocks = [];
  const stack = [{ decls: '', start: 0 }];
  for (let i = 0; i < css.length; i++) {
    const c = css[i];
    if (c === '{') stack.push({ decls: '', start: i + 1 });
    else if (c === '}') {
      if (stack.length > 1) blocks.push(stack.pop());
    } else stack[stack.length - 1].decls += c;
  }
  return blocks;
}

/** 项目是否为 Vue 2（非 Vue 项目返回 false） */
function isVue2(filePath) {
  const m = /^(\d+)\./.exec(vueVersion(filePath) || '');
  return Boolean(m) && +m[1] < 3;
}

/**
 * Grid 声明：display: grid / inline-grid / -ms-grid，以及所有 grid-* 属性和 grid 简写
 * （grid-template-*、grid-area、grid-row/column(-start|-end|-gap)、grid-gap、grid-auto-*）。
 * 要求前面是行首、`;`、`{` 或空白，scss/less 变量 `$grid-gap:`、类名 `.grid-item:hover` 不算。
 */
const GRID_DECL = /(?:^|[;{\s])(display\s*:\s*(?:-ms-)?(?:inline-)?grid\b|grid(?:-[\w-]+)?\s*:)/g;
/** 内联 :style 对象里的驼峰写法：gridTemplateColumns:、display: 'grid' */
const GRID_INLINE_JS = /(?:^|[{,\s'"])(grid[A-Z]\w*\s*:|display\s*:\s*['"`](?:inline-)?grid\b)/g;

/** 模板里的 style="..." 与 :style="..." 属性值：[{ content, offset }] */
function inlineStyles(src, filePath) {
  if (!filePath.endsWith('.vue')) return [];
  const tpl = splitSfc(src).template;
  if (!tpl) return [];
  const out = [];
  const re = /(?:^|\s)(?::|v-bind:)?style\s*=\s*(["'])([\s\S]*?)\1/g;
  let m;
  while ((m = re.exec(tpl.content)))
    out.push({ content: m[2], offset: tpl.offset + m.index + m[0].lastIndexOf(m[2]) });
  return out;
}

/** 非零长度值：`top: 128px`、`left: 24rpx`；0、百分比、auto、calc 都不算写死坐标 */
const hardcoded = prop => new RegExp(`(?:^|[;\\s])${prop}\\s*:\\s*-?(?:[1-9]\\d*(?:\\.\\d+)?|0?\\.\\d*[1-9]\\d*)(?:px|rpx|rem|em|vw|vh)\\b`);
const hasTop = hardcoded('(?:top|bottom)');
const hasLeft = hardcoded('(?:left|right)');

/** 同一文件里「绝对定位 + 两个方向都写死坐标」的块达到该数量才提示，角标、关闭按钮这类少量用法不打扰 */
const ABSOLUTE_LAYOUT_THRESHOLD = 3;

export const styleChecks = {
  'vue2-no-grid': {
    level: 'error',
    run({ src, filePath }) {
      if (!isVue2(filePath)) return []; // 非 Vue 或 Vue 3+ 不限制
      const out = [];
      const report = (offset, decl) =>
        out.push({
          line: lineAt(src, offset),
          message: `Vue 2 项目不用 CSS Grid（${decl.replace(/\s*:\s*$/, '')}），改用 flex + flex-wrap + 百分比宽度`,
        });
      const scan = (blocks, re) => {
        for (const b of blocks) {
          let hit;
          re.lastIndex = 0;
          while ((hit = re.exec(b.content))) report(b.offset + hit.index + hit[0].indexOf(hit[1]), hit[1]);
        }
      };
      scan(styleBlocks(src, filePath), GRID_DECL);
      const inline = inlineStyles(src, filePath);
      scan(inline, GRID_DECL);
      scan(inline, GRID_INLINE_JS);
      return out.sort((a, b) => a.line - b.line);
    },
  },

  'vue2-flex-gap': {
    level: 'warn',
    run({ src, filePath }) {
      if (!isVue2(filePath)) return [];
      const out = [];
      for (const b of styleBlocks(src, filePath))
        for (const r of ruleBlocks(b.content)) {
          if (!/(?:^|[;\s])display\s*:\s*(?:inline-)?flex\b/.test(r.decls)) continue;
          const gap = /(?:^|[;\s])((?:row-|column-)?gap)\s*:/.exec(r.decls);
          if (!gap) continue;
          const at = b.content.indexOf(gap[1], r.start);
          out.push({
            line: lineAt(src, b.offset + (at === -1 ? r.start : at)),
            message: `Vue 2 项目的 flex 容器慎用 ${gap[1]}（iOS < 14.5、Chrome < 84 不支持），子元素间距改用 margin`,
          });
        }
      return out.sort((a, b) => a.line - b.line);
    },
  },

  'absolute-hardcoded-layout': {
    level: 'warn',
    run({ src, filePath }) {
      const hits = [];
      for (const b of styleBlocks(src, filePath))
        for (const r of ruleBlocks(b.content))
          if (/position\s*:\s*absolute\b/.test(r.decls) && hasTop.test(r.decls) && hasLeft.test(r.decls))
            hits.push(lineAt(src, b.offset + r.start));
      if (hits.length < ABSOLUTE_LAYOUT_THRESHOLD) return [];
      return hits.map(line => ({
        line,
        message: `本文件有 ${hits.length} 处绝对定位 + 写死 top/left 坐标，疑似按设计稿坐标拼布局：改用文档流 + flex，定位只留给角标、浮层、装饰层`,
      }));
    },
  },
};
