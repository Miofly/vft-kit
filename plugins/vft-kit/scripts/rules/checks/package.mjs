/**
 * package.json 自动检查（配合 rules/package-json.md）。
 * 依赖版本必须写精确版本；peerDependencies 描述兼容范围，不检查。
 */
import fs from 'node:fs';
import path from 'node:path';

import { lineAt } from './vue.mjs';

export const packageExts = ['package.json'];

const SECTIONS = ['dependencies', 'devDependencies', 'optionalDependencies'];

/** 精确版本：1.2.3、1.2.3-beta.1、1.2.3+build */
const EXACT = /^v?\d+\.\d+\.\d+(?:-[\w.-]+)?(?:\+[\w.-]+)?$/;

/** 不是 semver 范围的协议写法：workspace/catalog/本地路径/git/URL/GitHub 简写，原样放行 */
const PROTOCOL = /^(?:workspace:|catalog:|file:|link:|portal:|patch:|git(?:\+[\w]+)?:|https?:|github:|[\w.-]+\/[\w.-]+(?:#.*)?$)/;

/** 返回需要改的版本串；精确版本或协议写法返回 null。`npm:` 别名取 @ 后面的版本 */
function rangeOf(spec) {
  const value = spec.trim();
  const alias = /^npm:(?:@[^/]+\/)?[^@]+@(.+)$/.exec(value);
  const version = alias ? alias[1] : value;
  if (!alias && PROTOCOL.test(version)) return null;
  return EXACT.test(version) ? null : version;
}

/** 从 package.json 所在目录向上找已安装的版本，给出改法建议 */
function installedVersion(pkgFile, name) {
  let dir = path.dirname(pkgFile);
  while (true) {
    const file = path.join(dir, 'node_modules', name, 'package.json');
    if (fs.existsSync(file)) {
      try {
        return JSON.parse(fs.readFileSync(file, 'utf8')).version || null;
      } catch {
        return null;
      }
    }
    const parent = path.dirname(dir);
    if (parent === dir) return null;
    dir = parent;
  }
}

/** 定位 `"name": "spec"` 所在行：从对应 section 的起点往后找，找不到退回 section 行 */
function locate(src, section, name, spec) {
  const sectionAt = src.search(new RegExp(`"${section}"\\s*:\\s*\\{`));
  const from = Math.max(sectionAt, 0);
  const esc = s => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const re = new RegExp(`"${esc(name)}"\\s*:\\s*"${esc(spec)}"`, 'g');
  re.lastIndex = from;
  const m = re.exec(src);
  return lineAt(src, m ? m.index : from);
}

export const packageChecks = {
  'pin-exact-version': {
    level: 'error',
    run({ src, filePath }) {
      let json;
      try {
        json = JSON.parse(src);
      } catch {
        return []; // 写到一半的 JSON 不检查
      }
      const out = [];
      for (const section of SECTIONS) {
        const deps = json[section];
        if (!deps || typeof deps !== 'object') continue;
        for (const [name, spec] of Object.entries(deps)) {
          if (typeof spec !== 'string') continue;
          const range = rangeOf(spec);
          if (!range) continue;
          const installed = installedVersion(filePath, name);
          const hint = installed
            ? `改为已安装版本 "${spec.startsWith('npm:') ? spec.replace(range, installed) : installed}"`
            : '改为锁文件中的实际版本';
          out.push({
            line: locate(src, section, name, spec),
            message: `${section}.${name} 写了范围版本 "${spec}"，依赖一律写精确版本：${hint}`,
          });
        }
      }
      return out;
    },
  },
};
