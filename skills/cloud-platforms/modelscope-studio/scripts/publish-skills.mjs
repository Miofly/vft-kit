#!/usr/bin/env node
// Publish every skill directory of a public GitHub repository to ModelScope Skills.
//
// ModelScope has no OpenAPI/SDK route for creating a skill: `POST /openapi/v1/skills`
// rejects SDK tokens, and the whole "create from GitHub" flow lives on internal
// `/api/v1/skills/*` routes that only accept a browser login session. So this script
// runs the calls inside an ego-lite task space (`page.fetch` = window.fetch with the
// page's cookies) and never touches tokens, cookies, or credentials itself.
//
// Endpoint contracts were captured from real create traffic on 2026-10-10; see
// ../references/skills-publish-api.md.
//
// Usage:
//   node publish-skills.mjs --repo https://github.com/<user>/<repo> --owner <modelscope-user> [--profile <egoProfileId>]
//   node publish-skills.mjs --config /path/to/config.json          # keys: repo, owner, profile, ...
//   node publish-skills.mjs ... --apply                            # actually create (default is dry-run)
//   node publish-skills.mjs ... --sync                             # re-pull already-published skills from GitHub
//   node publish-skills.mjs ... --only skill-a,skill-b             # restrict to some skills
//   node publish-skills.mjs ... --category developer-tools         # default ModelScope catalogue id
//   node publish-skills.mjs ... --space "my-publish-space"         # ego task space name
//   node publish-skills.mjs ... --report /path/to/report.json      # write a machine-readable result
//   node publish-skills.mjs --selftest                             # offline check of payload assembly

import { spawn } from 'node:child_process';
import { readFile, writeFile } from 'node:fs/promises';
import { homedir } from 'node:os';

const EGO = process.env.EGO_BROWSER_BIN || `${homedir()}/.local/bin/ego-browser`;
const CATALOGUES_URL = '/api/v1/catalogues?Business=skills';
const DEFAULTS = {
  category: 'developer-tools',
  license: 'Apache License 2.0',
  visibility: 5, // 5 = public; other values are unverified
  autoSync: true,
  profile: null, // null = ego default profile
  space: 'modelscope-skill-publish',
  delayMs: 1500,
  // Build artefacts that the GitHub tree may still carry; they would otherwise be synced verbatim.
  exclude: ['__pycache__/', '.pyc', '.DS_Store', '.pytest_cache/', 'node_modules/'],
};

function parseArgs(argv) {
  const out = { only: [], apply: false, selftest: false, overrides: {} };
  for (let i = 0; i < argv.length; i += 1) {
    const a = argv[i];
    const next = () => argv[++i];
    if (a === '--apply') out.apply = true;
    else if (a === '--sync') out.sync = true;
    else if (a === '--selftest') out.selftest = true;
    else if (a === '--repo') out.overrides.repo = next();
    else if (a === '--owner') out.overrides.owner = next();
    else if (a === '--profile') out.overrides.profile = next();
    else if (a === '--category') out.overrides.category = next();
    else if (a === '--license') out.overrides.license = next();
    else if (a === '--space') out.overrides.space = next();
    else if (a === '--delay-ms') out.overrides.delayMs = Number(next());
    else if (a === '--visibility') out.overrides.visibility = Number(next());
    else if (a === '--no-auto-sync') out.overrides.autoSync = false;
    else if (a === '--config') out.configPath = next();
    else if (a === '--only') out.only = next().split(',').map((s) => s.trim()).filter(Boolean);
    else if (a === '--report') out.reportPath = next();
    else if (a === '--help' || a === '-h') out.help = true;
    else throw new Error(`unknown argument: ${a}`);
  }
  return out;
}

/** skill name -> catalogue id. Exact skill name wins over its parent directory name. */
function categoryFor(skill, cfg) {
  const map = cfg.category_map || {};
  if (map[skill.Name]) return map[skill.Name];
  const dirs = String(skill.SkillPath || '').split('/');
  for (let i = dirs.length - 1; i >= 0; i -= 1) if (map[dirs[i]]) return map[dirs[i]];
  return cfg.category || DEFAULTS.category;
}

/** Build artefacts to keep out of a published skill; substring match on the repo-relative path. */
function keepFile(path, exclude) {
  const pats = exclude || DEFAULTS.exclude || [];
  return !pats.some((x) => String(path).includes(x));
}

/**
 * Assemble the `POST /api/v1/skills` body. Pure function so --selftest can verify it offline.
 * `info` is `Data.SkillInfo[0]` from /api/v1/skills/github/skillInfo (may be null).
 */
function buildPayload(skill, info, cfg) {
  return {
    Name: skill.Name,
    DisplayName: info?.DisplayName || skill.DisplayName || skill.Name,
    SourceUrl: skill.GithubUrl,
    Path: cfg.owner,
    License: info?.License || cfg.license || DEFAULTS.license,
    Visibility: cfg.visibility ?? DEFAULTS.visibility,
    Description: info?.Description || skill.Description || '',
    L1: categoryFor(skill, cfg),
    Tags: cfg.tags || [],
    SourceAvatar: info?.Avatar || '',
    AutoSyncEnabled: cfg.autoSync === false ? 0 : 1,
    Files: (skill.FileList || []).filter((f) => keepFile(f, cfg.exclude)).map((FilePath) => ({ FilePath })),
    SourceDeveloper: info?.Developer || cfg.source_developer || '',
    Source: 'github',
  };
}

function browserScript(cfg, only, apply, sync) {
  // Runs inside the ego-lite Node runtime: no argv, no process.env passthrough, no cwd of the
  // caller — everything arrives inlined below, results leave via one EGO_RESULT line.
  // No top-level `return`: the runtime may evaluate this as a module, so the flow lives in run().
  return `
const CFG = ${JSON.stringify(cfg)};
const ONLY = ${JSON.stringify(only)};
const APPLY = ${JSON.stringify(apply)};
const SYNC = ${JSON.stringify(!!sync)};
const DEFAULTS = ${JSON.stringify(DEFAULTS)};
const CATALOGUES_URL = ${JSON.stringify(CATALOGUES_URL)};
${categoryFor.toString()}
${keepFile.toString()}
${buildPayload.toString()}

const spaces = await listTaskSpaces();
const existing = spaces.find((s) => s.name === CFG.space && (!CFG.profile || s.profileId === CFG.profile));
// taskSpace(name, {profileId}) throws when the name already exists, so resume by id in that case.
const task = existing ? await taskSpace(existing.id) : await taskSpace(CFG.space, CFG.profile ? { profileId: CFG.profile } : undefined);
const out = { owner: CFG.owner, repo: CFG.repo, apply: APPLY, results: [], spaceId: task.spaceId, reusedSpace: !!existing };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const run = async () => {
  const page = task.page("p1");
  await page.goto("https://modelscope.cn/skills", { waitUntil: "domcontentloaded", timeout: 60000 });
  await page.waitForTimeout(3000);

  const call = async (url, method, body) => {
    const r = await page.fetch(url, {
      method: method || "GET",
      headers: { "content-type": "application/json" },
      body: body === undefined ? undefined : JSON.stringify(body),
      timeout: 180000,
    });
    let j = null;
    try { j = JSON.parse(r.body); } catch (e) {}
    return { status: r.status, j, raw: String(r.body).slice(0, 300) };
  };

  const me = await call("/api/v1/users/login/info");
  out.login = me.j?.Data?.Name ?? null;
  if (out.login !== CFG.owner) {
    out.fatal = "browser session is logged in as " + JSON.stringify(out.login) + ", expected " + CFG.owner;
    return;
  }

  const cats = await call(CATALOGUES_URL);
  out.catalogues = ((cats.j?.Data?.Catalogues) || cats.j?.Data || []).map((c) => c.CatalogID);

  const parsed = await call("/api/v1/skills/github/parse", "POST", { GithubUrl: CFG.repo });
  if (parsed.status !== 200 || !parsed.j?.Success) {
    out.fatal = "github/parse failed: http=" + parsed.status + " " + parsed.raw;
    return;
  }
  out.commit = parsed.j.Data?.RepoInfo?.LatestCommitId ?? null;
  const all = parsed.j.Data?.SkillsInfo || [];
  out.found = all.length;
  const targets = ONLY.length ? all.filter((s) => ONLY.includes(s.Name)) : all;
  out.selected = targets.length;
  if (ONLY.length && targets.length !== ONLY.length) {
    out.missing = ONLY.filter((n) => !targets.some((s) => s.Name === n));
  }

  for (const skill of targets) {
    const rec = { name: skill.Name, files: (skill.FileList || []).length };
    try {
      const mine = await call("/api/v1/skills/user_repeat", "POST", {
        Source: "github", SourceURL: skill.GithubUrl, PageSize: 20, PageNumber: 1,
      });
      if ((mine.j?.Data?.Skills || []).length > 0) {
        if (!SYNC) { rec.state = "skip-exists-mine"; out.results.push(rec); continue; }
        // Same call the 手动同步 button makes; Status is up_to_date | updating | ...
        const cu = await call("/api/v1/skills/" + CFG.owner + "/" + skill.Name + "/check-update", "POST", {
          Path: CFG.owner, Name: skill.Name,
        });
        rec.state = "sync-" + (cu.j?.Data?.Status || ("http" + cu.status));
        if (cu.status !== 200 || cu.j?.Success !== true) rec.error = (cu.j?.Message || cu.raw || "").slice(0, 200);
        out.results.push(rec); continue;
      }
      if (SYNC) { rec.state = "not-published"; out.results.push(rec); continue; }

      const official = await call("/api/v1/skills/official_repeat", "POST", {
        Source: "github", SourceURL: skill.GithubUrl, PageSize: 20, PageNumber: 1,
      });
      if ((official.j?.Data?.Skills || []).length > 0) {
        rec.state = "skip-exists-official";
        rec.official = (official.j.Data.Skills || []).map((s) => s.Path + "/" + s.Name).slice(0, 5);
        out.results.push(rec); continue;
      }

      const info = await call("/api/v1/skills/github/skillInfo", "POST", {
        GithubUrl: skill.GithubUrl, FilePaths: [skill.SkillPath],
      });
      const meta = info.j?.Data?.SkillInfo?.[0] || null;
      const payload = buildPayload(skill, meta, CFG);
      rec.files = payload.Files.length;
      rec.category = payload.L1;
      rec.displayName = payload.DisplayName;
      rec.descriptionChars = (payload.Description || "").length;
      if (!payload.Description) rec.warn = "empty description (SKILL.md frontmatter?)";
      if (!out.catalogues.includes(payload.L1)) rec.warn = (rec.warn ? rec.warn + "; " : "") + "unknown catalogue id " + payload.L1;

      if (!APPLY) { rec.state = "planned"; rec.payload = payload; out.results.push(rec); continue; }

      const created = await call("/api/v1/skills", "POST", payload);
      rec.createStatus = created.status;
      rec.createCode = created.j?.Code ?? null;
      if (created.status !== 200 || created.j?.Success !== true) {
        rec.state = "create-failed";
        rec.error = (created.j?.Message || created.raw || "").slice(0, 300);
        out.results.push(rec); continue;
      }

      // Independent readback: the public detail route, not the create response.
      await sleep(2000);
      const detail = await call("/api/v1/skills/" + CFG.owner + "/" + skill.Name);
      const d = detail.j?.Data || {};
      const files = await call("/api/v1/skills/" + CFG.owner + "/" + skill.Name + "/repo/files?Revision=master&Recursive=true");
      rec.state = "created";
      rec.verify = {
        detailStatus: detail.status,
        sourceUrl: d.SourceURL || null,
        sourceMatches: (d.SourceURL || "") === skill.GithubUrl,
        autoSync: d.AutoSyncEnabled ?? null,
        visibility: d.Visibility ?? null,
        catalogue: d.L1?.CatalogID ?? null,
        readmeChars: (d.ReadMeContent || "").length,
        repoEntries: (files.j?.Data?.Files || []).length,
      };
      if (!rec.verify.sourceMatches || !rec.verify.readmeChars) rec.warn = (rec.warn ? rec.warn + "; " : "") + "readback mismatch";
    } catch (e) {
      rec.state = "error";
      rec.error = String(e && e.message ? e.message : e).slice(0, 300);
    }
    out.results.push(rec);
    await sleep(CFG.delayMs);
  }
};

try {
  await run();
} catch (e) {
  out.fatal = out.fatal || ("run failed: " + String(e && e.message ? e.message : e).slice(0, 400));
} finally {
  // Close only a space this script owns; a user-owned space that happens to share the name stays open.
  if (CFG.finishSpace !== false && (!existing || existing.ownership === "agent")) await task.finish({ keep: [] });
}
console.log("EGO_RESULT " + JSON.stringify(out));
`;
}

function runInEgo(code, timeoutMs) {
  return new Promise((resolve) => {
    const child = spawn(EGO, ['nodejs'], { stdio: ['pipe', 'pipe', 'pipe'] });
    let buf = '';
    const timer = setTimeout(() => child.kill('SIGKILL'), timeoutMs);
    child.stdout.on('data', (d) => { buf += d; });
    child.stderr.on('data', (d) => { buf += d; });
    child.on('error', (e) => { clearTimeout(timer); resolve({ error: `cannot run ${EGO}: ${e.message}`, buffer: buf }); });
    child.on('close', (exitCode) => {
      clearTimeout(timer);
      const line = buf.split('\n').filter((l) => l.startsWith('EGO_RESULT ')).pop();
      if (line) {
        try { return resolve({ result: JSON.parse(line.slice('EGO_RESULT '.length)) }); } catch (e) { /* fall through */ }
      }
      resolve({ error: `ego exit ${exitCode}, no EGO_RESULT`, buffer: buf.trim().split('\n').slice(-6).join(' | ').slice(0, 1200) });
    });
    child.stdin.end(code);
  });
}

function selftest() {
  const skill = {
    Name: 'demo-skill',
    DisplayName: '',
    Description: '',
    SkillPath: 'plugins/kit/skills/web-automation/demo-skill/SKILL.md',
    GithubUrl: 'https://github.com/example/kit/tree/main/plugins/kit/skills/web-automation/demo-skill',
    FileList: ['SKILL.md', 'scripts/run.sh', 'scripts/__pycache__/run.cpython-312.pyc', '.DS_Store'],
  };
  const info = { DisplayName: 'demo-skill', Description: '前端 description', Avatar: 'https://x/a.png', License: '', Developer: 'example' };
  const cfg = { ...DEFAULTS, owner: 'someone', category_map: { 'web-automation': 'other', 'demo-skill': 'developer-tools' } };
  const p = buildPayload(skill, info, cfg);
  const checks = [
    ['Name', p.Name === 'demo-skill'],
    ['Path=owner', p.Path === 'someone'],
    ['Source=github', p.Source === 'github'],
    ['SourceUrl is tree url', p.SourceUrl === skill.GithubUrl],
    ['description from skillInfo', p.Description === '前端 description'],
    ['license falls back', p.License === DEFAULTS.license],
    ['avatar from skillInfo', p.SourceAvatar === 'https://x/a.png'],
    ['developer from skillInfo', p.SourceDeveloper === 'example'],
    ['autoSync -> 1', p.AutoSyncEnabled === 1],
    ['files mapped', JSON.stringify(p.Files) === '[{"FilePath":"SKILL.md"},{"FilePath":"scripts/run.sh"}]'],
    ['build artefacts excluded', p.Files.length === 2 && !JSON.stringify(p.Files).includes('pyc')],
    ['exclude overridable', buildPayload(skill, info, { ...cfg, exclude: [] }).Files.length === 4],
    ['skill-name category wins', p.L1 === 'developer-tools'],
    ['dir category used', buildPayload({ ...skill, Name: 'other-skill', SkillPath: 'plugins/kit/skills/web-automation/other-skill/SKILL.md' }, info, cfg).L1 === 'other'],
    ['default category', buildPayload(skill, info, { ...DEFAULTS, owner: 'o' }).L1 === 'developer-tools'],
    ['autoSync off -> 0', buildPayload(skill, info, { ...cfg, autoSync: false }).AutoSyncEnabled === 0],
    ['no info still builds', buildPayload(skill, null, cfg).DisplayName === 'demo-skill'],
  ];
  let bad = 0;
  for (const [name, ok] of checks) { if (!ok) { bad += 1; console.log(`FAIL ${name}`); } }
  console.log(bad === 0 ? `selftest OK (${checks.length} checks)` : `selftest FAILED (${bad}/${checks.length})`);
  return bad === 0;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.help) { console.log(await readFile(new URL(import.meta.url), 'utf8').then((s) => s.split('\n').filter((l) => l.startsWith('//')).join('\n'))); return; }
  if (args.selftest) { process.exitCode = selftest() ? 0 : 1; return; }

  const fileCfg = args.configPath ? JSON.parse(await readFile(args.configPath, 'utf8')) : {};
  const section = fileCfg.skill_publish && typeof fileCfg.skill_publish === 'object' ? fileCfg.skill_publish : fileCfg;
  const cfg = { ...DEFAULTS, ...section, ...args.overrides };
  if (!cfg.repo || !cfg.owner) {
    console.error('missing --repo/--owner (or a config with repo+owner). Try --help.');
    process.exitCode = 2;
    return;
  }

  const timeoutMs = Number(cfg.timeoutMs || 1_500_000);
  const mode = args.sync ? 'SYNC' : args.apply ? 'APPLY' : 'DRY-RUN';
  console.log(`${mode} repo=${cfg.repo} owner=${cfg.owner} profile=${cfg.profile ?? 'default'} space=${cfg.space}`);
  const { result, error, buffer } = await runInEgo(browserScript(cfg, args.only, args.apply, args.sync), timeoutMs);
  if (!result) { console.error('FAILED:', error); if (buffer) console.error('ego output tail:', buffer); process.exitCode = 1; return; }
  if (result.fatal) { console.error('FATAL:', result.fatal); process.exitCode = 1; return; }

  console.log(`login=${result.login} commit=${(result.commit || '').slice(0, 12)} found=${result.found} selected=${result.selected} catalogues=${(result.catalogues || []).length}`);
  if (result.missing?.length) console.log('WARNING not found in repo:', result.missing.join(', '));
  const counts = {};
  for (const r of result.results) {
    counts[r.state] = (counts[r.state] || 0) + 1;
    const extra = r.state === 'created' ? ` readme=${r.verify.readmeChars} repoEntries=${r.verify.repoEntries} cat=${r.verify.catalogue}` : '';
    console.log(` ${r.state.padEnd(20)} ${r.name.padEnd(30)} files=${r.files} cat=${r.category ?? '-'}${extra}${r.error ? ' err=' + r.error : ''}${r.warn ? ' warn=' + r.warn : ''}`);
  }
  console.log('summary:', JSON.stringify(counts));
  if (args.reportPath) { await writeFile(args.reportPath, JSON.stringify(result, null, 1)); console.log('report:', args.reportPath); }
  const failed = result.results.filter((r) => ['create-failed', 'error'].includes(r.state) || r.error);
  const mismatch = result.results.filter((r) => r.warn);
  if (failed.length || mismatch.length) process.exitCode = 1;
}

main().catch((e) => { console.error('fatal', e.stack || e.message); process.exitCode = 1; });
