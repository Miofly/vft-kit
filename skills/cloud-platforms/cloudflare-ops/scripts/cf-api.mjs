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

  die(
    `未找到 CF_API_TOKEN。请 export CF_API_TOKEN=<token> 或创建配置文件 ${profile}.json`
  );
}

// --help / -h 在任意位置都短路,先于 token 解析(帮助不该要 token)
const WANT_HELP = process.argv.slice(2).some((a) => a === "--help" || a === "-h" || a === "help");

const TOKEN = WANT_HELP ? null : resolveToken();

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
  // 分页拉全,不再截断在 50
  const all = [];
  let page = 1;
  for (;;) {
    const d = await api("GET", `/zones?per_page=50&page=${page}`);
    all.push(...(d.result || []));
    const ti = d.result_info;
    if (!ti || page >= ti.total_pages || !d.result?.length) break;
    page++;
  }
  if (!all.length) return log("(无 zones)");
  log(`共 ${all.length} 个 zones:\n`);
  for (const z of all) {
    log(`  ${z.name.padEnd(30)} ${z.id}  ${z.status}`);
  }
}

// edge/browser TTL 策略字符串 → action_parameters TTL 对象
function parseTtl(val, kind) {
  if (val === "respect_origin") return { mode: "respect_origin" };
  if (val === "bypass")
    return kind === "browser"
      ? { mode: "bypass" }
      : { mode: "bypass_by_default" };
  const secs = parseInt(val, 10);
  if (isNaN(secs)) die(`无效的 ${kind} TTL 值: ${val}`);
  return { mode: "override_origin", default: secs };
}

// 取某 zone 指定 phase 的 ruleset(默认 cache phase)
async function getPhaseRuleset(zoneId, phase = "http_request_cache_settings") {
  const rsData = await api("GET", `/zones/${zoneId}/rulesets`);
  const rs = rsData.result?.find((r) => r.phase === phase);
  if (!rs) die(`未找到 phase=${phase} 的 ruleset`);
  // list 接口不返回 rules,需再 GET 单个 ruleset 拿全量规则
  const full = await api("GET", `/zones/${zoneId}/rulesets/${rs.id}`);
  return full.result;
}

async function cmdCacheAdd() {
  const zoneId = await resolveZone(flags.zone);
  const expr = flags.expr || die("缺少 --expr");
  const desc = flags.desc || "cache-rule";
  const edge = flags.edge || "respect_origin";

  const cache = {
    cache: true,
    edge_ttl: parseTtl(edge, "edge"),
  };
  if (flags.browser) cache.browser_ttl = parseTtl(flags.browser, "browser");
  if (flags["serve-stale"])
    cache.serve_stale = { disable_stale_while_updating: false };

  const cacheRs = await getPhaseRuleset(zoneId);
  const newRule = {
    action: "set_cache_settings",
    expression: expr,
    description: desc,
    action_parameters: cache,
  };

  const rules = flags.first
    ? [newRule, ...cacheRs.rules]
    : [...cacheRs.rules, newRule];
  const updated = await api("PUT", `/zones/${zoneId}/rulesets/${cacheRs.id}`, {
    rules,
  });
  const addedId = updated.result.rules.find((r) => r.description === desc)?.id;
  log(`✅ 已添加缓存规则: ${desc} (id=${addedId})`);
}

// parseTtl 返回的是内层 {mode,default},edge_ttl/browser_ttl 需要按字段名包一层
function wrapTtl(ttl) {
  // override_origin 用 default 秒数;其余用 mode
  return ttl.mode === "override_origin"
    ? { mode: ttl.mode, default: ttl.default }
    : { mode: ttl.mode };
}

async function cmdCacheUpdate() {
  const zoneId = await resolveZone(flags.zone);
  const ruleId = args[2] || die("缺少 rule_id 参数");
  const cacheRs = await getPhaseRuleset(zoneId);
  const rule = cacheRs.rules.find((r) => r.id === ruleId);
  if (!rule) die(`未找到 rule_id=${ruleId}`);

  // 就地改:只覆盖显式传入的字段
  if (flags.expr) rule.expression = flags.expr;
  if (flags.desc) rule.description = flags.desc;
  const ap = (rule.action_parameters ||= { cache: true });
  if (flags.edge) ap.edge_ttl = parseTtl(flags.edge, "edge");
  if (flags.browser) ap.browser_ttl = parseTtl(flags.browser, "browser");

  await api("PUT", `/zones/${zoneId}/rulesets/${cacheRs.id}`, {
    rules: cacheRs.rules,
  });
  log(`✅ 已更新缓存规则 ${ruleId}`);
}

async function cmdCacheList() {
  const zoneId = await resolveZone(flags.zone);
  const cacheRs = await getPhaseRuleset(zoneId);
  if (!cacheRs.rules?.length) return log("(无缓存规则)");

  log(`Zone ${zoneId} 的缓存规则:\n`);
  for (const r of cacheRs.rules) {
    log(`  [${r.id}] ${r.description || "(无描述)"}`);
    log(`    expr: ${r.expression}`);
    log(`    edge_ttl: ${JSON.stringify(r.action_parameters?.edge_ttl)}`);
    if (r.action_parameters?.browser_ttl)
      log(`    browser_ttl: ${JSON.stringify(r.action_parameters.browser_ttl)}`);
    log("");
  }
}

async function cmdCacheDelete() {
  const zoneId = await resolveZone(flags.zone);
  const ruleId = args[2] || die("缺少 rule_id 参数");

  const cacheRs = await getPhaseRuleset(zoneId);
  const filtered = cacheRs.rules.filter((r) => r.id !== ruleId);
  if (filtered.length === cacheRs.rules.length) die(`未找到 rule_id=${ruleId}`);

  await api("PUT", `/zones/${zoneId}/rulesets/${cacheRs.id}`, { rules: filtered });
  log(`✅ 已删除缓存规则 ${ruleId}`);
}

async function cmdPurge() {
  const zoneId = await resolveZone(flags.zone);
  const urls = args.slice(1).filter((a) => a.startsWith("http"));

  // by-tag / by-host / by-prefix 需企业版;逗号分隔
  const split = (v) => (typeof v === "string" ? v.split(",").map((s) => s.trim()) : null);
  const tags = split(flags.tags);
  const hosts = split(flags.hosts);
  const prefixes = split(flags.prefixes);

  let body;
  if (tags) body = { tags };
  else if (hosts) body = { hosts };
  else if (prefixes) body = { prefixes };
  else if (urls.length) body = { files: urls };
  else body = { purge_everything: true };

  await api("POST", `/zones/${zoneId}/purge_cache`, body);
  log(`✅ 已清缓存: ${JSON.stringify(body)}`);
}

// ── DNS 记录 CRUD ───────────────────────────────────────────────────
async function cmdDns() {
  const sub = args[1];
  const zoneId = await resolveZone(flags.zone);

  if (sub === "list") {
    const type = flags.type ? `&type=${flags.type}` : "";
    const d = await api("GET", `/zones/${zoneId}/dns_records?per_page=100${type}`);
    if (!d.result?.length) return log("(无 DNS 记录)");
    log(`Zone ${zoneId} 的 DNS 记录(${d.result.length}):\n`);
    for (const r of d.result) {
      const proxy = r.proxiable ? (r.proxied ? "🟠proxied" : "⚪dns-only") : "";
      log(`  [${r.id}] ${r.type.padEnd(6)} ${r.name.padEnd(28)} → ${r.content}  ttl=${r.ttl} ${proxy}`);
    }
    return;
  }

  if (sub === "get") {
    const id = args[2] || die("缺少 record_id");
    const d = await api("GET", `/zones/${zoneId}/dns_records/${id}`);
    return console.log(JSON.stringify(d.result, null, 2));
  }

  if (sub === "add" || sub === "update") {
    const type = flags.type || (sub === "add" ? die("缺少 --type") : undefined);
    const name = flags.name || (sub === "add" ? die("缺少 --name") : undefined);
    const content = flags.content || (sub === "add" ? die("缺少 --content") : undefined);
    const rec = {};
    if (type) rec.type = type;
    if (name) rec.name = name;
    if (content) rec.content = content;
    // TTL:1 = 自动;proxied 默认跟随 CF
    rec.ttl = flags.ttl ? parseInt(flags.ttl, 10) : 1;
    if (flags.proxied !== undefined) rec.proxied = flags.proxied === "true" || flags.proxied === true;
    if (flags.priority) rec.priority = parseInt(flags.priority, 10); // MX/SRV

    if (sub === "add") {
      const d = await api("POST", `/zones/${zoneId}/dns_records`, rec);
      return log(`✅ 已新增 DNS 记录 ${d.result.type} ${d.result.name} (id=${d.result.id})`);
    }
    const id = args[2] || die("缺少 record_id");
    const d = await api("PATCH", `/zones/${zoneId}/dns_records/${id}`, rec);
    return log(`✅ 已更新 DNS 记录 ${d.result.name} (id=${id})`);
  }

  if (sub === "delete") {
    const id = args[2] || die("缺少 record_id");
    await api("DELETE", `/zones/${zoneId}/dns_records/${id}`);
    return log(`✅ 已删除 DNS 记录 ${id}`);
  }

  die(`未知 dns 子命令: ${sub}(list/get/add/update/delete)`);
}

// ── Zone settings 通用 get/set ──────────────────────────────────────
// 一对命令覆盖所有 zone 开关:ssl / min_tls_version / brotli / http3 /
// always_online / development_mode / early_hints / 0rtt / websockets ...
async function cmdSettings() {
  const sub = args[1];
  const zoneId = await resolveZone(flags.zone);

  if (sub === "get") {
    const name = args[2];
    if (name) {
      const d = await api("GET", `/zones/${zoneId}/settings/${name}`);
      return log(`${name} = ${JSON.stringify(d.result.value)}`);
    }
    const d = await api("GET", `/zones/${zoneId}/settings`);
    for (const s of d.result || []) {
      const editable = s.editable ? "" : " (只读)";
      log(`  ${s.id.padEnd(28)} = ${JSON.stringify(s.value)}${editable}`);
    }
    return;
  }

  if (sub === "set") {
    const name = args[2] || die("缺少 setting 名(如 ssl / brotli / min_tls_version)");
    const raw = args[3];
    if (raw === undefined) die("缺少 value");
    // value 可能是字符串("full"/"on")或 JSON(对象/数字);尝试 JSON 解析,失败当字符串
    let value;
    try {
      value = JSON.parse(raw);
    } catch {
      value = raw;
    }
    const d = await api("PATCH", `/zones/${zoneId}/settings/${name}`, { value });
    return log(`✅ ${name} = ${JSON.stringify(d.result.value)}`);
  }

  die(`未知 settings 子命令: ${sub}(get/set)`);
}

// ── Ruleset 通用命令:覆盖 Redirect/Transform/Origin/Config/WAF 等所有 phase ──
const PHASE_ALIAS = {
  cache: "http_request_cache_settings",
  redirect: "http_request_dynamic_redirect",
  transform: "http_request_transform",
  "late-transform": "http_response_headers_transform",
  origin: "http_request_origin",
  config: "http_config_settings",
  "waf-custom": "http_request_firewall_custom",
  ratelimit: "http_ratelimit",
};
function resolvePhase(p) {
  if (!p) die(`缺少 --phase(可用别名: ${Object.keys(PHASE_ALIAS).join("/")},或写全名)`);
  return PHASE_ALIAS[p] || p;
}

async function cmdRuleset() {
  const sub = args[1];
  const zoneId = await resolveZone(flags.zone);

  if (sub === "list") {
    const d = await api("GET", `/zones/${zoneId}/rulesets`);
    if (!d.result?.length) return log("(无 ruleset)");
    for (const rs of d.result) {
      log(`  [${rs.id}] ${rs.phase.padEnd(38)} ${rs.name || ""}`);
    }
    return;
  }

  if (sub === "get") {
    const rs = await getPhaseRuleset(zoneId, resolvePhase(flags.phase));
    return console.log(JSON.stringify(rs, null, 2));
  }

  if (sub === "rule") {
    const op = args[2];
    const phase = resolvePhase(flags.phase);

    if (op === "add") {
      const action = flags.action || die("缺少 --action(如 redirect/rewrite/route/skip)");
      const expr = flags.expr || die("缺少 --expr");
      const rule = { action, expression: expr, description: flags.desc || "" };
      // action_parameters 直接吃一段 JSON,不为每种 action 写死字段
      if (flags.params) {
        try {
          rule.action_parameters = JSON.parse(flags.params);
        } catch {
          die("--params 不是合法 JSON");
        }
      }
      // 该 phase 可能还没 ruleset,list 找不到就用 PUT phase entrypoint 创建
      const rsData = await api("GET", `/zones/${zoneId}/rulesets`);
      const existing = rsData.result?.find((r) => r.phase === phase);
      if (existing) {
        const full = await api("GET", `/zones/${zoneId}/rulesets/${existing.id}`);
        const rules = flags.first
          ? [rule, ...full.result.rules]
          : [...full.result.rules, rule];
        await api("PUT", `/zones/${zoneId}/rulesets/${existing.id}`, { rules });
      } else {
        // phase entrypoint:首次用 PUT 创建整个 phase ruleset
        await api("PUT", `/zones/${zoneId}/rulesets/phases/${phase}/entrypoint`, {
          rules: [rule],
        });
      }
      return log(`✅ 已在 phase=${phase} 添加规则 (${action})`);
    }

    if (op === "delete") {
      const ruleId = args[3] || die("缺少 rule_id");
      const rs = await getPhaseRuleset(zoneId, phase);
      const filtered = rs.rules.filter((r) => r.id !== ruleId);
      if (filtered.length === rs.rules.length) die(`未找到 rule_id=${ruleId}`);
      await api("PUT", `/zones/${zoneId}/rulesets/${rs.id}`, { rules: filtered });
      return log(`✅ 已删除规则 ${ruleId}`);
    }

    die(`未知 rule 操作: ${op}(add/delete)`);
  }

  die(`未知 ruleset 子命令: ${sub}(list/get/rule)`);
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
  if (WANT_HELP || cmd === "help") return printHelp();
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
      else if (sub === "update") await cmdCacheUpdate();
      else if (sub === "delete") await cmdCacheDelete();
      else die(`未知 cache 子命令: ${sub}(add/list/update/delete)`);
      break;
    case "dns":
      await cmdDns();
      break;
    case "settings":
      await cmdSettings();
      break;
    case "ruleset":
      await cmdRuleset();
      break;
    case "purge":
      await cmdPurge();
      break;
    case "api":
      await cmdApi();
      break;
    default:
      die(`未知子命令: ${cmd}`);
  }
})().catch((e) => die(e.message));

function printHelp() {
  console.log(`Cloudflare API 通用封装

用法:
  node cf-api.mjs verify [--profile <name>]
  node cf-api.mjs zones [--profile <name>]

  # DNS 记录
  node cf-api.mjs dns list --zone <zone> [--type A]
  node cf-api.mjs dns get <record-id> --zone <zone>
  node cf-api.mjs dns add --zone <zone> --type A --name sub.example.com --content 1.2.3.4 [--proxied true] [--ttl 300]
  node cf-api.mjs dns update <record-id> --zone <zone> --content 5.6.7.8
  node cf-api.mjs dns delete <record-id> --zone <zone>

  # 缓存规则
  node cf-api.mjs cache add --expr '<expression>' --edge <mode> --desc '<desc>' --zone <zone> [--browser <mode>] [--first]
  node cf-api.mjs cache list --zone <zone>
  node cf-api.mjs cache update <rule-id> --zone <zone> [--edge <mode>] [--browser <mode>] [--expr ...]
  node cf-api.mjs cache delete <rule-id> --zone <zone>

  # 清缓存
  node cf-api.mjs purge [<url>...] --zone <zone>
  node cf-api.mjs purge --zone <zone> [--tags a,b] [--hosts x.com,y.com] [--prefixes p1,p2]

  # Zone 设置(通用,覆盖所有开关)
  node cf-api.mjs settings get --zone <zone> [<name>]
  node cf-api.mjs settings set <name> <value> --zone <zone>

  # Ruleset(通用,覆盖 redirect/transform/origin/waf-custom 等所有 phase)
  node cf-api.mjs ruleset list --zone <zone>
  node cf-api.mjs ruleset get --phase <alias> --zone <zone>
  node cf-api.mjs ruleset rule add --phase <alias> --action <action> --expr '<expr>' [--params '<json>'] --zone <zone> [--first]
  node cf-api.mjs ruleset rule delete <rule-id> --phase <alias> --zone <zone>

  # 通用透传(任意 endpoint)
  node cf-api.mjs api <METHOD> <path> [jsonBody] [--profile <name>]

参数:
  --profile <name>  使用哪个配置文件(默认 default)
  --zone <zone>     域名或 zone_id(32位hex)
  --edge <mode>     边缘缓存 TTL:respect_origin / bypass / <秒数>
  --browser <mode>  浏览器缓存 TTL:respect_origin / bypass / <秒数>
  --phase <alias>   ruleset phase 别名:cache/redirect/transform/late-transform/origin/config/waf-custom/ratelimit,或写全名
  --params <json>   ruleset 规则的 action_parameters(JSON 字符串)
  --proxied <bool>  DNS 记录是否走 CF 代理(橙云)
  --first           把新规则排最前
  --config <path>   明确指定配置文件路径

示例:
  export CF_API_TOKEN=your-token
  node cf-api.mjs dns add --zone example.com --type CNAME --name www --content example.com --proxied true
  node cf-api.mjs settings set ssl full --zone example.com
  node cf-api.mjs settings set min_tls_version '"1.2"' --zone example.com
  node cf-api.mjs ruleset rule add --phase redirect --action redirect --expr '(http.host eq "old.com")' --params '{"from_value":{"target_url":{"value":"https://new.com"},"status_code":301}}' --zone example.com
  node cf-api.mjs cache add --expr '(http.request.method eq "GET")' --edge 86400 --desc cache-all-get --zone example.com
`);
}
