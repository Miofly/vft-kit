#!/usr/bin/env node
// Upload / preview a mini program with the official `miniprogram-ci` package.
// No WeChat DevTools, no QR login, no GUI: authenticates with the "code upload key" from
// mp.weixin.qq.com → 开发管理 → 开发设置 → 小程序代码上传.
//
// Usage:
//   MP_APPID=wx... MP_KEY=/abs/upload.key MP_PROJECT=/abs/dist-dir \
//     node mp-ci.mjs upload  <version> "<desc>"
//     node mp-ci.mjs preview "<desc>" <qr.png> [pagePath] [query]
//   node mp-ci.mjs --selftest
//
// MP_PROJECT is the directory that contains app.json (for Taro: dist/weapp).
// Optional: MP_ROBOT (1-30, default 1; each robot is a separate uploader slot in the backend).
// The package is installed once into ~/.cache/vft-kit/miniprogram-ci (override with MP_CI_HOME):
//   mkdir -p ~/.cache/vft-kit/miniprogram-ci && cd $_ && npm i miniprogram-ci
// The key is only read from the path; never print it.
import { createRequire } from 'node:module';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const CI_HOME = process.env.MP_CI_HOME || path.join(os.homedir(), '.cache/vft-kit/miniprogram-ci');

export function parseArgs(argv) {
  const [cmd, ...rest] = argv;
  if (cmd === 'upload') {
    const [version, desc] = rest;
    if (!version || !desc) throw new Error('usage: upload <version> "<desc>"');
    if (!/^\d+(\.\d+){1,3}$/.test(version)) throw new Error(`bad version: ${version}`);
    return { cmd, version, desc };
  }
  if (cmd === 'preview') {
    const [desc, qr, pagePath, query] = rest;
    if (!desc || !qr) throw new Error('usage: preview "<desc>" <qr.png> [pagePath] [query]');
    if (!path.isAbsolute(qr)) throw new Error('qr output must be an absolute path');
    return { cmd, desc, qr, pagePath, query };
  }
  throw new Error('command must be upload or preview');
}

export function readEnv(env) {
  const appid = env.MP_APPID;
  const key = env.MP_KEY;
  const project = env.MP_PROJECT;
  if (!appid || !/^wx[0-9a-f]{16}$/.test(appid)) throw new Error('MP_APPID missing or invalid');
  if (!key || !fs.existsSync(key)) throw new Error('MP_KEY missing or file not found');
  if (!project || !fs.existsSync(path.join(project, 'app.json'))) throw new Error('MP_PROJECT must contain app.json (build first)');
  const robot = Number(env.MP_ROBOT || 1);
  if (!(robot >= 1 && robot <= 30)) throw new Error('MP_ROBOT must be 1-30');
  return { appid, key, project, robot };
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const cfg = readEnv(process.env);
  let ci;
  try {
    ci = createRequire(path.join(CI_HOME, 'index.js'))('miniprogram-ci');
  } catch {
    throw new Error(`miniprogram-ci not installed in ${CI_HOME}; run: mkdir -p ${CI_HOME} && cd ${CI_HOME} && npm i miniprogram-ci`);
  }
  const project = new ci.Project({
    appid: cfg.appid,
    type: 'miniProgram',
    projectPath: cfg.project,
    privateKeyPath: cfg.key,
    ignores: ['node_modules/**/*'],
  });
  // Taro output is already compiled; let the platform only minify.
  const setting = { es6: false, es7: false, minify: true, minifyJS: true, minifyWXML: true, minifyWXSS: true, autoPrefixWXSS: false };
  const onProgressUpdate = () => {};
  if (args.cmd === 'upload') {
    const res = await ci.upload({ project, version: args.version, desc: args.desc, setting, robot: cfg.robot, onProgressUpdate });
    const size = res?.subPackageInfo?.find(p => p.name === '__FULL__')?.size;
    console.log(`✔ uploaded ${args.version} robot=${cfg.robot}${size ? ` size=${Math.round(size / 1024)}KB` : ''}`);
  } else {
    await ci.preview({
      project, desc: args.desc, setting, robot: cfg.robot, onProgressUpdate,
      qrcodeFormat: 'image', qrcodeOutputDest: args.qr,
      ...(args.pagePath ? { pagePath: args.pagePath, searchQuery: args.query || '' } : {}),
    });
    console.log(`✔ preview QR: ${args.qr}`);
  }
}

if (process.argv[2] === '--selftest') {
  const assert = (await import('node:assert/strict')).default;
  assert.deepEqual(parseArgs(['upload', '4.0.6', 'x']), { cmd: 'upload', version: '4.0.6', desc: 'x' });
  assert.throws(() => parseArgs(['upload', '2026-10-06', 'x']), /bad version/);
  assert.throws(() => parseArgs(['preview', 'x', 'rel.png']), /absolute/);
  assert.throws(() => parseArgs(['publish']), /upload or preview/);
  assert.throws(() => readEnv({ MP_APPID: 'bad' }), /MP_APPID/);
  console.log('selftest ok');
} else {
  main().catch(err => {
    // miniprogram-ci errors may embed request details; print only the message.
    console.error(`✖ ${String(err?.message || err).slice(0, 500)}`);
    process.exit(1);
  });
}
