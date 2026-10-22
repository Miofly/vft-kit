#!/usr/bin/env node
// 把某个 Claude Code 插件的部分 hook 「去插件化」：从上游 git 拉最新代码，只复制这些 hook 需要的文件到
// 固定 vendor 目录，再把对应 hook 条目写进 settings.json（用户级 hook，绝对路径，不依赖 ${CLAUDE_PLUGIN_ROOT}）。
// 用途：只用插件的一两个 hook（如 caveman 风格模式），不想为它的几十个 skill/agent 常驻上下文付 token。
//
// 目录：<vendor>/upstream  上游浅克隆；<vendor>/current  生效版本（hook 命令指向这里）；<vendor>/previous  上一版。
// 流程：git fetch <ref> → 复制 files + .claude-plugin/plugin.json 到暂存目录 → 自检（隔离 CLAUDE_CONFIG_DIR 跑一遍
//       选中的 hook，退出码 0 且输出含 expect）→ 换入 current → 按 current 的 plugin.json 重写 settings 里的条目。
// hook 命令 = `export CLAUDE_PLUGIN_ROOT='<vendor>/current'; <上游原命令>`，命令里的 ${CLAUDE_PLUGIN_ROOT} 换成字面路径
// （CC 拒跑引用该变量的非插件 hook），其余语义原样保留。
// 识别自己写的条目：命令里含 `<vendor>/current`；重写时先删掉这些条目，再把新条目插到该事件数组最前面，
// 其他 hook 不动、不重排（让后挂的 hook，例如回复语言钉子，仍排在后面）。
//
// 失败策略：拉取失败、上游缺文件/缺事件/命令引用的脚本不在 files 里、自检失败 → 保留旧 current，打印告警，退出码 0；
// 风格类 hook 宁可用旧版也不能坏掉。只有 --check 发现问题时退出码 1（给体检脚本用）。
// skipIfPluginEnabled：该插件仍装着且启用时只 vendor 不接线（并撤掉已接的条目），避免同一规则注入两次。
//
// commands{名字: md 文件}：插件 skill 卸掉后交互式 `/名字 参数` 会报 Unknown command 且不送出（hook 收不到），
// 所以给要保留的斜杠命令装一个用户级命令文件（$CLAUDE_CONFIG_DIR/commands/<名字>.md，建议 disable-model-invocation，
// 不占模型上下文）。只覆盖带 `managed-by: vft-kit vendor-plugin-hooks` 标记的同名文件。
//
// 用法：node vendor-plugin-hooks.mjs --config <json> [--repo URL] [--ref REF] [--vendor DIR] [--events A,B]
//         [--files a,b] [--settings FILE[#jsonKey]]... [--offline] [--check]
// 配置 JSON 字段同名：repo ref vendor events files expect{事件:子串} settings[] skipIfPluginEnabled commands{}
//   commandOverrides{事件: 命令}（只配置文件可用）：替换该事件上游唯一 hook 的命令（timeout 等字段保留），
//   可照常写 ${CLAUDE_PLUGIN_ROOT}；上游该事件不止一个 hook 时报问题、保留旧版本。
// 路径支持 ~；配置里的相对路径按配置文件所在目录解析。settings 缺省为 $CLAUDE_CONFIG_DIR/settings.json。
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';

const argv = process.argv.slice(2);
const flag = (n) => argv.includes(n);
const opt = (n) => { const i = argv.indexOf(n); return i >= 0 ? argv[i + 1] : undefined; };
const opts = (n) => argv.flatMap((a, i) => (a === n && argv[i + 1] ? [argv[i + 1]] : []));
const CHECK = flag('--check');
const OFFLINE = flag('--offline') || CHECK;
const claudeDir = process.env.CLAUDE_CONFIG_DIR || path.join(os.homedir(), '.claude');
const warn = (m) => console.log(`  ○ ${m}`);
const info = (m) => console.log(`  ✓ ${m}`);

function expand(p, base) {
  if (!p) return p;
  if (p === '~' || p.startsWith('~/')) return path.join(os.homedir(), p.slice(1));
  return base && !path.isAbsolute(p) ? path.resolve(base, p) : p;
}
const list = (v) => (Array.isArray(v) ? v : String(v || '').split(',')).map((s) => s.trim()).filter(Boolean);

let cfg = {};
const cfgPath = opt('--config');
if (cfgPath) {
  try { cfg = JSON.parse(fs.readFileSync(cfgPath, 'utf8')); } catch (e) { console.error(`✗ 读不了配置 ${cfgPath}: ${e.message}`); process.exit(CHECK ? 1 : 0); }
}
const cfgDir = cfgPath ? path.dirname(path.resolve(cfgPath)) : process.cwd();
const repo = opt('--repo') || cfg.repo;
const ref = opt('--ref') || cfg.ref || 'main';
const vendorArg = opt('--vendor') || cfg.vendor;
const vendor = vendorArg ? path.resolve(expand(vendorArg, cfgDir)) : '';
const events = list(opt('--events') || cfg.events);
const files = list(opt('--files') || cfg.files);
const overrides = cfg.commandOverrides || {};
const expect = cfg.expect || {};
const skipPlugin = opt('--skip-if-plugin-enabled') || cfg.skipIfPluginEnabled || '';
const settingsTargets = (opts('--settings').length ? opts('--settings') : (cfg.settings || [path.join(claudeDir, 'settings.json')]))
  .map((s) => { const [f, key] = String(s).split('#'); return { file: path.resolve(expand(f, cfgDir)), key: key || null }; });
const current = path.join(vendor, 'current');
const scriptConfigDir = path.join(path.dirname(new URL(import.meta.url).pathname), '..', 'config');
const commands = Object.entries(cfg.commands || {}).map(([name, src]) => {
  const p = expand(src, cfgDir);
  return { name, src: fs.existsSync(p) ? p : path.join(scriptConfigDir, src) };
});
const MANAGED = 'managed-by: vft-kit vendor-plugin-hooks';

if (!repo || !vendor || !events.length || !files.length) {
  console.error('✗ 缺参数：需要 repo、vendor、events、files（命令行或 --config）');
  process.exit(CHECK ? 1 : 0);
}
if (/['"$`\\\n]/.test(current)) { console.error(`✗ vendor 路径不能含引号、$、反引号、反斜杠或换行：${current}`); process.exit(CHECK ? 1 : 0); }

const git = (args, cwd) => spawnSync('git', args, { cwd, encoding: 'utf8', timeout: 180000, env: { ...process.env, GIT_TERMINAL_PROMPT: '0' } });

function readJson(f) { try { return JSON.parse(fs.readFileSync(f, 'utf8')); } catch { return null; } }
function writeAtomic(file, text) {
  const tmp = `${file}.${process.pid}.${Date.now()}.tmp`;
  const mode = fs.existsSync(file) ? fs.statSync(file).mode & 0o7777 : 0o644;
  try { fs.writeFileSync(tmp, text, { flag: 'wx', mode }); fs.renameSync(tmp, file); } finally { if (fs.existsSync(tmp)) fs.unlinkSync(tmp); }
}

/** 读插件清单里的 hooks（内联对象，或指向 hooks.json 的路径，或默认 hooks/hooks.json）。 */
function manifestHooks(root) {
  const m = readJson(path.join(root, '.claude-plugin', 'plugin.json')) || {};
  let h = m.hooks;
  if (typeof h === 'string') h = readJson(path.join(root, h))?.hooks;
  if (!h) h = readJson(path.join(root, 'hooks', 'hooks.json'))?.hooks;
  return h && typeof h === 'object' ? h : null;
}

const prefix = (root) => `export CLAUDE_PLUGIN_ROOT='${root}'; `;
// Claude Code 拒跑「非插件 hook 里引用 ${CLAUDE_PLUGIN_ROOT}」的命令（Failed to run: ... not associated with a plugin），
// 所以命令文本里的引用一律换成字面路径；export 仍保留，给脚本内部读环境变量用。
const inline = (cmd, root) => String(cmd).replace(/\$\{CLAUDE_PLUGIN_ROOT\}|\$CLAUDE_PLUGIN_ROOT\b/g, root);

/** 选中事件的 hook 组（命令已加 CLAUDE_PLUGIN_ROOT 前缀）；有问题返回 { problems }。 */
function buildGroups(root) {
  const hooks = manifestHooks(root);
  if (!hooks) return { problems: ['上游没有可读的 hooks 清单（.claude-plugin/plugin.json 或 hooks/hooks.json）'] };
  const problems = [];
  const groups = {};
  for (const ev of events) {
    if (!Array.isArray(hooks[ev]) || !hooks[ev].length) { problems.push(`上游缺 ${ev} hook`); continue; }
    const override = overrides[ev];
    if (override && hooks[ev].flatMap((g) => g.hooks || []).length !== 1) { problems.push(`上游 ${ev} 不止一个 hook，commandOverrides 对不上`); continue; }
    groups[ev] = hooks[ev].map((g) => {
      const src = (g.hooks || []).map((h) => ({ ...h, command: override || h.command }));
      const out = { ...g, hooks: src.map((h) => ({ ...h, command: prefix(root) + inline(h.command, root) })) };
      for (const h of src) {
        for (const [, rel] of String(h.command).matchAll(/(?:\$\{?CLAUDE_PLUGIN_ROOT\}?|\$\{?HOOK_ROOT\}?)\/([^"'\s;]+)/g)) {
          if (!fs.existsSync(path.join(root, rel))) problems.push(`${ev} 引用的 ${rel} 不在 vendor 文件里`);
        }
      }
      return out;
    });
  }
  return { problems, groups };
}

/** 隔离 CLAUDE_CONFIG_DIR 依次跑选中的 hook：SessionStart 先跑（建会话状态），其余随后。 */
function selftest(root) {
  const { problems, groups } = buildGroups(root);
  if (problems.length) return problems;
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'vendor-hooks-selftest-'));
  fs.writeFileSync(path.join(tmp, 'settings.json'), '{"statusLine":{"type":"command","command":"true"}}\n');
  const order = Object.keys(groups).sort((a, b) => (a === 'SessionStart' ? -1 : b === 'SessionStart' ? 1 : 0));
  try {
    for (const ev of order) {
      for (const g of groups[ev]) for (const h of g.hooks) {
        const payload = JSON.stringify({ session_id: 'vendor-selftest', transcript_path: '', cwd: tmp, hook_event_name: ev,
          source: 'startup', prompt: 'selftest ping', agent_id: 'selftest', agent_type: 'general-purpose' });
        const r = spawnSync('bash', ['-c', h.command], { input: payload, encoding: 'utf8', cwd: tmp, timeout: 20000,
          env: { ...process.env, CLAUDE_CONFIG_DIR: tmp } });
        if (r.status !== 0) problems.push(`${ev} 自检退出码 ${r.status}${r.error ? ` (${r.error.code})` : ''}: ${(r.stderr || '').trim().split('\n')[0]}`);
        else if (expect[ev] && !String(r.stdout).includes(expect[ev])) problems.push(`${ev} 自检输出不含「${expect[ev]}」`);
      }
    }
  } finally { fs.rmSync(tmp, { recursive: true, force: true }); }
  return problems;
}

/** 拉上游 → 暂存 → 自检 → 换入 current。任何失败都保留旧 current。 */
function pullAndVendor() {
  const up = path.join(vendor, 'upstream');
  fs.mkdirSync(up, { recursive: true });
  if (!fs.existsSync(path.join(up, '.git'))) git(['init', '-q'], up);
  if (git(['remote', 'get-url', 'origin'], up).status !== 0) git(['remote', 'add', 'origin', repo], up);
  else git(['remote', 'set-url', 'origin', repo], up);
  const f = git(['fetch', '-q', '--depth', '1', 'origin', ref], up);
  if (f.status !== 0) return warn(`拉取 ${repo}@${ref} 失败，保留旧版本：${(f.stderr || f.error?.message || '').trim().split('\n')[0]}`);
  const co = git(['checkout', '-q', '-f', 'FETCH_HEAD'], up);
  if (co.status !== 0) return warn(`检出 ${ref} 失败，保留旧版本：${co.stderr.trim().split('\n')[0]}`);
  const commit = git(['rev-parse', 'HEAD'], up).stdout.trim();
  const old = readJson(path.join(current, 'VENDOR.json'));
  if (old?.commit === commit && JSON.stringify(old.files) === JSON.stringify(files) && fs.existsSync(path.join(current, '.claude-plugin'))) {
    return info(`上游无变化（${commit.slice(0, 7)}）`);
  }
  const missing = files.filter((rel) => !fs.existsSync(path.join(up, rel)));
  if (missing.length) return warn(`上游结构变了，缺 ${missing.join(', ')}；保留旧版本`);
  const stage = path.join(vendor, `.staging-${process.pid}`);
  fs.rmSync(stage, { recursive: true, force: true });
  try {
    for (const rel of [...files, '.claude-plugin']) {
      fs.cpSync(path.join(up, rel), path.join(stage, rel), { recursive: true, filter: (s) => path.basename(s) !== '.git' });
    }
    fs.writeFileSync(path.join(stage, 'VENDOR.json'), `${JSON.stringify({ repo, ref, commit, files, events, syncedAt: new Date().toISOString() }, null, 2)}\n`);
    const problems = selftest(stage);
    if (problems.length) return warn(`新版本 ${commit.slice(0, 7)} 自检失败，保留旧版本：${problems.join('；')}`);
    const prev = path.join(vendor, 'previous');
    fs.rmSync(prev, { recursive: true, force: true });
    if (fs.existsSync(current)) fs.renameSync(current, prev);
    fs.renameSync(stage, current);
    info(`已同步 ${repo}@${ref} → ${commit.slice(0, 7)}（${current}）`);
  } finally { fs.rmSync(stage, { recursive: true, force: true }); }
}

function pluginActive(id) {
  if (!id) return false;
  const installed = readJson(path.join(claudeDir, 'plugins', 'installed_plugins.json'))?.plugins || {};
  const settings = readJson(path.join(claudeDir, 'settings.json')) || {};
  return Boolean(installed[id]) && settings.enabledPlugins?.[id] !== false;
}

/** 在一个 hooks 对象里删掉自己的旧条目、插入新条目；返回是否有变化。 */
function rewire(hooks, groups) {
  const before = JSON.stringify(hooks);
  for (const ev of Object.keys(hooks)) {
    if (!Array.isArray(hooks[ev])) continue;
    hooks[ev] = hooks[ev].map((g) => (Array.isArray(g?.hooks) ? { ...g, hooks: g.hooks.filter((h) => !String(h?.command).includes(current)) } : g))
      .filter((g) => !Array.isArray(g?.hooks) || g.hooks.length);
    if (!hooks[ev].length) delete hooks[ev];
  }
  for (const [ev, gs] of Object.entries(groups || {})) hooks[ev] = [...gs, ...(hooks[ev] || [])];
  return JSON.stringify(hooks) !== before;
}

if (!CHECK && !OFFLINE) pullAndVendor();

const problems = [];
let groups = null;
if (!fs.existsSync(path.join(current, '.claude-plugin'))) problems.push(`没有可用的 vendor 版本（${current}）`);
else {
  const built = buildGroups(current);
  if (built.problems.length) problems.push(...built.problems);
  else groups = built.groups;
  if (CHECK) problems.push(...selftest(current));
}
const skip = pluginActive(skipPlugin);
if (skip) warn(`插件 ${skipPlugin} 仍启用：只 vendor 不接线（避免重复注入）；卸载插件后重跑本脚本`);

for (const t of settingsTargets) {
  const label = t.key ? `${path.basename(t.file)}#${t.key}` : t.file;
  const json = readJson(t.file);
  if (!json || (t.key && typeof json[t.key] !== 'object')) { if (!t.key) problems.push(`读不了 ${label}`); continue; }
  const holder = t.key ? json[t.key] : json;
  holder.hooks = holder.hooks && typeof holder.hooks === 'object' ? holder.hooks : {};
  const want = skip || !groups ? {} : groups;
  if (!groups && !skip) continue; // 没有可用版本时不动 settings，保留旧条目
  const copy = JSON.parse(JSON.stringify(holder.hooks));
  const changed = rewire(copy, want);
  if (!changed) { info(`${label} hook 已是最新`); continue; }
  if (CHECK) { problems.push(`${label} 的 hook 条目与 vendor 版本不一致`); continue; }
  const backupDir = process.env.VENDOR_HOOKS_BACKUP_DIR;
  const stamp = new Date().toISOString().replace(/[:.]/g, '').slice(0, 15);
  const backup = backupDir ? path.join(backupDir, `${path.basename(t.file)}.bak-${stamp}`) : `${t.file}.bak-vendor-hooks-${stamp}`;
  if (backupDir) fs.mkdirSync(backupDir, { recursive: true });
  fs.copyFileSync(t.file, backup);
  holder.hooks = copy;
  writeAtomic(t.file, `${JSON.stringify(json, null, 2)}\n`);
  info(`${label} hook 已${skip ? '撤下' : '写入'} ${Object.keys(want).join(', ') || '(无)'}（备份 ${backup}）`);
}

for (const c of skip ? [] : commands) {
  const dest = path.join(claudeDir, 'commands', `${c.name}.md`);
  let want;
  try { want = fs.readFileSync(c.src, 'utf8'); } catch { problems.push(`读不了命令源文件 ${c.src}`); continue; }
  const have = fs.existsSync(dest) ? fs.readFileSync(dest, 'utf8') : null;
  if (have === want) continue;
  if (have !== null && !have.includes(MANAGED)) { warn(`${dest} 已存在且不是本脚本管理的，不覆盖`); continue; }
  if (CHECK) { problems.push(`用户级命令 /${c.name} 缺失或过期`); continue; }
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  writeAtomic(dest, want);
  info(`已写入用户级命令 /${c.name}（${dest}）`);
}

if (problems.length) {
  for (const p of problems) (CHECK ? console.error(`  ✗ ${p}`) : warn(p));
  process.exit(CHECK ? 1 : 0);
}
if (CHECK) info(`vendor hook 在位且自检通过（${readJson(path.join(current, 'VENDOR.json'))?.commit?.slice(0, 7) || '?'}）`);
process.exit(0);
