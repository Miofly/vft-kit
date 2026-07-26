#!/usr/bin/env node
// Cloudflare API 通用封装 —— 多账号支持,token 从环境变量或配置文件读取。
// 零依赖(Node 18+ 内置 fetch)。公开、可开源、不含私有信息。
//
// Token 查找优先级:
//   1. 环境变量 CF_API_TOKEN(最高优先级)
//   2. 配置文件 <profile>.json 的 api_token 字段
//
// 子命令见文件底部 usage() 或 ../SKILL.md。

import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

const BASE = "https://api.cloudflare.com/client/v4";

// ── 解析命令行参数 ──────────────────────────────────────────────────────
function parseArgs(argv) {
  const args = [];
  const flags = {};
  let i = 2; // 跳过 node 和脚本路径
  while (i < argv.length) {
    const a = argv[i];
    if (a.startsWith("--")) {
      const key = a.slice(2);
      const next = argv[i + 1];
      if (next && !next.startsWith("--")) {
        flags[key] = next;
        i += 2;
      } else {
        flags[key] = true;
        i++;
      }
    } else {
      args.push(a);
      i++;
    }
  }
  return { args, flags };
}

const { args, flags } = parseArgs(process.argv);
const profile = flags.profile || "default";

// ── Token 查找:环境变量 → 配置文件 ────────────────────────────────────
function resolveToken() {
  // 1. 环境变量(最高优先级)
  if (process.env.CF_API_TOKEN) {
    return process.env.CF_API_TOKEN;
  }

  // 2. 配置文件 <profile>.json
  const searchPaths = [
    flags.config, // 用户明确指定
    join(process.cwd(), `${profile}.json`), // 当前目录
    join(process.cwd(), `.cloudflare/${profile}.json`), // 项目 .cloudflare/
    join(homedir(), `.config/cloudflare/${profile}.json`), // 用户全局
  ].filter(Boolean);

  for (const p of searchPaths) {
    try {
      const cfg = JSON.parse(readFileSync(p, "utf8"));
      if (cfg.api_token) return cfg.api_token;
    } catch {}
  }

  throw new Error(
    `未找到 CF_API_TOKEN。请 export CF_API_TOKEN=<token> 或创建配置文件 ${profile}.json`
  );
}

const TOKEN = resolveToken();

// ── 读取配置文件(可选,用于 known_zones 等) ──────────────────────────
function loadConfig() {
  const searchPaths = [
    flags.config,
    join(process.cwd(), `${profile}.json`),
    join(process.cwd(), `.cloudflare/${profile}.json`),
    join(homedir(), `.config/cloudflare/${profile}.json`),
  ].filter(Boolean);

  for (const p of searchPaths) {
    try {
      return JSON.parse(readFileSync(p, "utf8"));
    } catch {}
  }
  return {}; // 配置文件可选,没有就空对象
}

const config = loadConfig();
const KNOWN_ZONES = config.known_zones || {};

// ── Cloudflare API 调用封装 ─────────────────────────────────────────
async function api(method, path, body = null) {
  const url = path.startsWith("http") ? path : `${BASE}${path}`;
  const opts = {
    method,
    headers: { Authorization: `Bearer ${TOKEN}` },
  };
  if (body) {
    opts.headers["Content-Type"] = "application/json";
    opts.body = JSON.stringify(body);
  }
  const r = await fetch(url, opts);
  const d = await r.json();
  if (!d.success) {
    const errs = d.errors?.map((e) => e.message).join("; ") || "未知错误";
    throw new Error(`CF API 失败: ${errs}`);
  }
  return d;
}

function die(msg) {
  console.error(`\n❌ ${msg}\n`);
  process.exit(1);
}

function log(msg) {
  console.log(msg);
}

// ── 解析 zone 参数(域名 or zone_id) ────────────────────────────────
async function resolveZone(zoneArg) {
  if (!zoneArg) die("缺少 --zone 参数");
  // 如果是 32 位 hex,当 zone_id
  if (/^[0-9a-f]{32}$/.test(zoneArg)) return zoneArg;
  // 否则当域名,先查 known_zones
  if (KNOWN_ZONES[zoneArg]) return KNOWN_ZONES[zoneArg];
  // 最后调 API 解析
  log(`解析域名 ${zoneArg} → zone_id...`);
  const d = await api("GET", `/zones?name=${zoneArg}`);
  if (!d.result?.length) die(`未找到域名 ${zoneArg} 的 zone`);
  return d.result[0].id;
}

// ── 子命令实现 ──────────────────────────────────────────────────────

async function cmdVerify() {
  const d = await api("GET", "/user/tokens/verify");
  log(`✅ Token 有效:`);
  log(`  ID: ${d.result.id}`);
  log(`  Status: ${d.result.status}`);
  log(`  Expires: ${d.result.expires_on || "never"}`);
}

async function cmdZones() {
  const d = await api("GET", "/zones?per_page=50");
  if (!d.result?.length) return log("(无 zones)");
  log(`共 ${d.result.length} 个 zones:\n`);
  for (const z of d.result) {
    log(`  ${z.name.padEnd(30)} ${z.id}`);
  }
}

async function cmdCacheAdd() {
  const zoneId = await resolveZone(flags.zone);
  const expr = flags.expr || die("缺少 --expr");
  const desc = flags.desc || "cache-rule";
  const edge = flags.edge || "respect_origin";

  // 解析 edge TTL 策略
  let edgeAction = {};
  if (edge === "respect_origin") {
    edgeAction = { default_ttl: { mode: "respect_origin" } };
  } else if (edge === "bypass") {
    edgeAction = { default_ttl: { mode: "bypass_by_default" } };
  } else {
    const secs = parseInt(edge, 10);
    if (isNaN(secs)) die(`无效的 --edge 值: ${edge}`);
    edgeAction = { default_ttl: { mode: "override_origin", default: secs } };
  }

  // 先 GET ruleset,找到 cache phase 的 ruleset_id
  const rsData = await api("GET", `/zones/${zoneId}/rulesets`);
  const cacheRs = rsData.result?.find((rs) => rs.phase === "http_request_cache_settings");
  if (!cacheRs) die("未找到 cache phase ruleset");

  // 构造新规则
  const newRule = {
    action: "set_cache_settings",
    expression: expr,
    description: desc,
    action_parameters: {
      cache: true,
      edge_ttl: edgeAction,
    },
  };

  // position
  const position = flags.first ? { before: cacheRs.rules[0]?.id } : {};

  // PATCH ruleset:append 新规则
  const body = {
    rules: [...cacheRs.rules, newRule],
  };
  if (flags.first && position.before) {
    // 如果要排最前,需用 position API(这里简化,直接 unshift)
    body.rules = [newRule, ...cacheRs.rules];
  }

  const updated = await api("PUT", `/zones/${zoneId}/rulesets/${cacheRs.id}`, body);
  const addedId = updated.result.rules.find((r) => r.description === desc)?.id;
  log(`✅ 已添加缓存规则: ${desc} (id=${addedId})`);
}

async function cmdCacheList() {
  const zoneId = await resolveZone(flags.zone);
  const rsData = await api("GET", `/zones/${zoneId}/rulesets`);
  const cacheRs = rsData.result?.find((rs) => rs.phase === "http_request_cache_settings");
  if (!cacheRs || !cacheRs.rules?.length) return log("(无缓存规则)");

  log(`Zone ${zoneId} 的缓存规则:\n`);
  for (const r of cacheRs.rules) {
    log(`  [${r.id}] ${r.description || "(无描述)"}`);
    log(`    expr: ${r.expression}`);
    log(`    edge_ttl: ${JSON.stringify(r.action_parameters?.edge_ttl)}`);
    log("");
  }
}

async function cmdCacheDelete() {
  const zoneId = await resolveZone(flags.zone);
  const ruleId = args[1] || die("缺少 rule_id 参数");

  const rsData = await api("GET", `/zones/${zoneId}/rulesets`);
  const cacheRs = rsData.result?.find((rs) => rs.phase === "http_request_cache_settings");
  if (!cacheRs) die("未找到 cache ruleset");

  const filtered = cacheRs.rules.filter((r) => r.id !== ruleId);
  if (filtered.length === cacheRs.rules.length) die(`未找到 rule_id=${ruleId}`);

  await api("PUT", `/zones/${zoneId}/rulesets/${cacheRs.id}`, { rules: filtered });
  log(`✅ 已删除缓存规则 ${ruleId}`);
}

async function cmdPurge() {
  const zoneId = await resolveZone(flags.zone);
  const urls = args.slice(1); // purge 后的所有参数当 URL

  const body = urls.length ? { files: urls } : { purge_everything: true };
  await api("POST", `/zones/${zoneId}/purge_cache`, body);

  if (urls.length) {
    log(`✅ 已清缓存: ${urls.length} 个 URL`);
  } else {
    log(`✅ 已清整站缓存(purge_everything)`);
  }
}

async function cmdApi() {
  const method = args[1]?.toUpperCase() || die("缺少 METHOD 参数");
  const path = args[2] || die("缺少 path 参数");
  const bodyStr = args[3];
  const body = bodyStr ? JSON.parse(bodyStr) : null;

  const d = await api(method, path, body);
  console.log(JSON.stringify(d, null, 2));
}

// ── 主入口 ──────────────────────────────────────────────────────────
(async () => {
  const cmd = args[0];
  if (!cmd) die("缺少子命令。用 --help 查看用法");

  switch (cmd) {
    case "verify":
      await cmdVerify();
      break;
    case "zones":
      await cmdZones();
      break;
    case "cache":
      const sub = args[1];
      if (sub === "add") await cmdCacheAdd();
      else if (sub === "list") await cmdCacheList();
      else if (sub === "delete") await cmdCacheDelete();
      else die(`未知 cache 子命令: ${sub}`);
      break;
    case "purge":
      await cmdPurge();
      break;
    case "api":
      await cmdApi();
      break;
    case "--help":
    case "-h":
      console.log(`Cloudflare API 通用封装

用法:
  node cf-api.mjs verify [--profile <name>]
  node cf-api.mjs zones [--profile <name>]
  node cf-api.mjs cache add --expr '<expression>' --edge <mode> --desc '<desc>' --zone <zone> [--first]
  node cf-api.mjs cache list --zone <zone>
  node cf-api.mjs cache delete <rule-id> --zone <zone>
  node cf-api.mjs purge [<url>...] --zone <zone>
  node cf-api.mjs api <METHOD> <path> [jsonBody] [--profile <name>]

参数:
  --profile <name>  使用哪个配置文件(默认 default)
  --zone <zone>     域名或 zone_id(32位hex)
  --edge <mode>     缓存 TTL 策略:respect_origin / bypass / <秒数>
  --first           把新规则排最前
  --config <path>   明确指定配置文件路径

示例:
  export CF_API_TOKEN=your-token
  node cf-api.mjs zones
  node cf-api.mjs cache add --expr '(http.request.method eq "GET")' --edge 86400 --desc cache-all-get --zone example.com
  node cf-api.mjs purge https://example.com/ --zone example.com
  node cf-api.mjs api GET /zones/<zone-id>/rulesets
`);
      break;
    default:
      die(`未知子命令: ${cmd}`);
  }
})().catch((e) => die(e.message));
