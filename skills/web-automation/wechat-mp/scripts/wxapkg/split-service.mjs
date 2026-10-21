#!/usr/bin/env node
// Split app-service.js of an unpacked mini program into one file per module,
// and dump pure-data modules (module.exports = {...} without wx/Page calls) to JSON.
//
//   node split-service.mjs <unpacked-dir>
//   node split-service.mjs --selftest
//
// app-service.js concatenates define("path/x.js", function(require, module, exports, ...){...})
// blocks. Output:
//   <dir>/_modules/<path>   one file per define(), original path kept
//   <dir>/_data/<path>.json module.exports of modules that load with a shimmed define()
// Porting static data (cities, scripts, articles) from _data/*.json keeps every string
// verbatim; hand-copying long Chinese legal text through an LLM drops or alters lines.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

function splitModules(src) {
  const re = /define\("([^"]+)"/g;
  const hits = [];
  let m;
  while ((m = re.exec(src))) hits.push({ name: m[1], start: m.index });
  return hits.map((hit, i) => ({
    name: hit.name,
    code: src.slice(hit.start, i + 1 < hits.length ? hits[i + 1].start : src.length),
  }));
}

// Run one module with a fake define()/require(); returns module.exports or undefined.
function loadData(code) {
  const trimmed = code.replace(/\n(require|__wxRoute|__wxRouteBegin|__wxAppCurrentFile__)[^\n]*/g, '');
  let exported;
  const define = (_name, factory) => {
    const module = { exports: {} };
    const blocked = () => {
      throw new Error('not data');
    };
    factory(blocked, module, module.exports);
    exported = module.exports;
  };
  try {
    Function('define', 'Page', 'Component', 'App', 'wx', trimmed)(define, undefined, undefined, undefined, undefined);
  } catch {
    return undefined;
  }
  // modules exporting only functions (api wrappers, helpers) serialize to {} and are not data
  const json = exported === undefined ? '' : JSON.stringify(exported);
  return !json || json === '{}' || json === '[]' ? undefined : exported;
}

function run(dir) {
  const file = path.join(dir, 'app-service.js');
  if (!fs.existsSync(file)) throw new Error(`no app-service.js in ${dir}`);
  const modules = splitModules(fs.readFileSync(file, 'utf8'));
  let data = 0;
  for (const mod of modules) {
    const out = path.join(dir, '_modules', mod.name);
    fs.mkdirSync(path.dirname(out), { recursive: true });
    fs.writeFileSync(out, mod.code);
    if (mod.name.startsWith('@babel/')) continue;
    const value = loadData(mod.code);
    if (value === undefined) continue;
    const json = path.join(dir, '_data', `${mod.name}.json`);
    fs.mkdirSync(path.dirname(json), { recursive: true });
    fs.writeFileSync(json, JSON.stringify(value, null, 2));
    data++;
    console.log(`data  ${mod.name}`);
  }
  console.log(`split ${modules.length} module(s), ${data} data module(s)`);
  return { modules: modules.length, data };
}

if (process.argv[2] === '--selftest') {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'split-service-'));
  fs.writeFileSync(
    path.join(dir, 'app-service.js'),
    'define("utils/a.js", function(require, module, exports){ module.exports = { list: ["甲", 2] }; });\n'
      + 'define("pages/i/i.js", function(require, module, exports){ var d = require("../../utils/a.js"); Page({}); });\n'
      + 'require("pages/i/i.js");\n',
  );
  const res = run(dir);
  const json = JSON.parse(fs.readFileSync(path.join(dir, '_data/utils/a.js.json'), 'utf8'));
  const ok = res.modules === 2 && res.data === 1 && json.list[0] === '甲';
  fs.rmSync(dir, { recursive: true, force: true });
  console.log(ok ? 'selftest ok' : 'selftest FAILED');
  process.exit(ok ? 0 : 1);
}

const dir = process.argv[2];
if (!dir) {
  console.error('usage: node split-service.mjs <unpacked-dir> | --selftest');
  process.exit(2);
}
run(dir);
