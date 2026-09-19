/**
 * 样式布局自动检查（配合 rules/style-layout.md）。
 * 对 .vue 只看 <style> 块，对 css/scss/sass/less/styl 看全文；注释先替换成等长空白，行号不变。
 */
import { blankComments, lineAt, vueVersion } from './vue.mjs';

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
      const m = /^(\d+)\./.exec(vueVersion(filePath) || '');
      if (!m || +m[1] >= 3) return []; // 非 Vue 或 Vue 3+ 不限制
      const out = [];
      for (const b of styleBlocks(src, filePath)) {
        const re = /(?:^|[;{\s])(display\s*:\s*(?:inline-)?grid\b|grid-template(?:-[\w-]+)?\s*:|grid-area\s*:|grid-(?:row|column)(?:-start|-end)?\s*:)/g;
        let hit;
        while ((hit = re.exec(b.content)))
          out.push({
            line: lineAt(src, b.offset + hit.index + hit[0].indexOf(hit[1])),
            message: `Vue 2 项目不用 CSS Grid（${hit[1].replace(/\s*:\s*$/, '')}），改用 flex + flex-wrap + 百分比宽度`,
          });
      }
      return out;
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
