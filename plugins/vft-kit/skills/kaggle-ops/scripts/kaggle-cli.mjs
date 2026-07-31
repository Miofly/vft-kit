#!/usr/bin/env node
// Kaggle CLI 完整封装 —— 覆盖所有官方 kaggle CLI 功能
// 多账号支持,credentials 从环境变量或配置文件读取。
// 零额外依赖(需系统有 kaggle CLI)。公开、可开源、不含私有信息。
//
// Credentials 查找优先级:
//   1. 环境变量 KAGGLE_USERNAME + KAGGLE_KEY(最高优先级)
//   2. ~/.kaggle/kaggle.json(Kaggle CLI 标准位置)
//   3. 配置文件 <account>.json
//
// 子命令见文件底部 usage() 或 ../SKILL.md。

import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";

// ── 解析命令行参数 ──────────────────────────────────────────────────────
function parseArgs(argv) {
  const args = [];
  const flags = {};
  let i = 2;
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
const account = flags.account || "default";

// ── Credentials 查找 ──────────────────────────────────────────────────
function resolveCredentials() {
  // 1. 环境变量(最高优先级)
  if (process.env.KAGGLE_USERNAME && process.env.KAGGLE_KEY) {
    return {
      username: process.env.KAGGLE_USERNAME,
      key: process.env.KAGGLE_KEY,
    };
  }

  // 2. 显式配置必须覆盖本机默认账号
  if (flags.config) {
    const cfg = JSON.parse(readFileSync(flags.config, "utf8"));
    if (cfg.username && (cfg.api_token || cfg.key)) {
      return { username: cfg.username, key: cfg.api_token || cfg.key };
    }
  }

  // 3. ~/.kaggle/kaggle.json(Kaggle CLI 标准)
  const stdPath = join(homedir(), ".kaggle", "kaggle.json");
  try {
    const std = JSON.parse(readFileSync(stdPath, "utf8"));
    if (std.username && std.key) return { username: std.username, key: std.key };
  } catch {}

  // 4. 配置文件 <account>.json
  const searchPaths = [
    join(process.cwd(), `${account}.json`),
    join(process.cwd(), `.kaggle/${account}.json`),
    join(homedir(), `.config/kaggle/${account}.json`),
  ].filter(Boolean);

  for (const p of searchPaths) {
    try {
      const cfg = JSON.parse(readFileSync(p, "utf8"));
      if (cfg.username && cfg.api_token) {
        return { username: cfg.username, key: cfg.api_token };
      }
      // 也支持 Kaggle 标准格式(key 字段)
      if (cfg.username && cfg.key) {
        return { username: cfg.username, key: cfg.key };
      }
    } catch {}
  }

  throw new Error(
    `未找到 Kaggle credentials。请 export KAGGLE_USERNAME/KAGGLE_KEY 或创建配置文件 ${account}.json`
  );
}

const creds = resolveCredentials();

// ── Kaggle CLI 调用封装 ──────────────────────────────────────────────
function findKaggleCli() {
  // 优先级:--kaggle 参数 > 环境变量 kaggle > 常见路径
  if (flags.kaggle) return [flags.kaggle];

  if (spawnSync("kaggle", ["--version"], { encoding: "utf8" }).status === 0) {
    return ["kaggle"];
  }

  const home = homedir();
  const candidates = [
    join(home, ".local/bin/kaggle"),
    "/opt/homebrew/bin/kaggle",
    "/usr/local/bin/kaggle",
  ];

  for (const c of candidates) {
    try {
      if (spawnSync(c, ["--version"], { encoding: "utf8" }).status === 0) return [c];
    } catch {}
  }

  throw new Error("未找到 kaggle CLI。请 pipx install kaggle 或 pip install kaggle");
}

const KAGGLE = findKaggleCli();

function execKaggle(args, opts = {}) {
  const env = {
    ...process.env,
    KAGGLE_USERNAME: creds.username,
    KAGGLE_KEY: creds.key,
    KAGGLE_API_TOKEN: creds.key,
  };

  const result = spawnSync(KAGGLE[0], args, {
    encoding: "utf8",
    env,
    cwd: opts.cwd || process.cwd(),
  });

  return {
    status: result.status,
    stdout: result.stdout || "",
    stderr: result.stderr || "",
  };
}

function die(msg) {
  console.error(`\n❌ ${msg}\n`);
  process.exit(1);
}

function log(msg) {
  console.log(msg);
}

// ── 重试逻辑 ──────────────────────────────────────────────────────────
function isTransientError(output) {
  const transient = [
    /connection.*reset/i,
    /timeout/i,
    /502 bad gateway/i,
    /503 service unavailable/i,
    /500 internal server error/i,
  ];
  return transient.some((re) => re.test(output));
}

function runWithRetry(args, opts = {}) {
  const maxRetries = parseInt(flags.retries || "3", 10);
  const retryDelay = parseInt(flags["retry-delay"] || "2000", 10);

  for (let i = 0; i <= maxRetries; i++) {
    const r = execKaggle(args, opts);
    const output = r.stdout + r.stderr;

    if (r.status === 0) return r;

    if (i < maxRetries && isTransientError(output)) {
      log(`⚠️ 瞬断错误,${retryDelay}ms 后重试(${i + 1}/${maxRetries})...`);
      const start = Date.now();
      while (Date.now() - start < retryDelay) {}
      continue;
    }

    // 非瞬断错误或重试耗尽
    console.error(output);
    die(`Kaggle CLI 失败(exit ${r.status})`);
  }
}

// ── 通用命令代理(直接转发给 kaggle CLI) ──────────────────────────────
function proxyCommand(kaggleArgs) {
  const r = execKaggle(kaggleArgs);
  if (r.stdout) process.stdout.write(r.stdout);
  if (r.stderr) process.stderr.write(r.stderr);
  process.exit(r.status);
}

// ── Kernels 子命令 ────────────────────────────────────────────────────

async function cmdKernelList() {
  const kaggleArgs = ["kernels", "list"];
  if (flags.mine) kaggleArgs.push("--mine");
  if (flags.user) kaggleArgs.push("--user", flags.user);
  if (flags.page) kaggleArgs.push("--page", flags.page);
  if (flags["page-size"]) kaggleArgs.push("--page-size", flags["page-size"]);
  if (flags.search) kaggleArgs.push("--search", flags.search);
  if (flags.sort) kaggleArgs.push("--sort-by", flags.sort);
  proxyCommand(kaggleArgs);
}

async function cmdKernelFiles() {
  const kernel = args[2] || die("缺少 <username>/<kernel-slug> 参数");
  proxyCommand(["kernels", "files", kernel]);
}

async function cmdKernelGet() {
  const kernel = args[2] || die("缺少 <username>/<kernel-slug> 参数");
  const kaggleArgs = ["kernels", "pull", kernel];
  if (flags.path) kaggleArgs.push("--path", flags.path);
  if (flags.metadata) kaggleArgs.push("--metadata");
  proxyCommand(kaggleArgs);
}

async function cmdKernelInit() {
  const kaggleArgs = ["kernels", "init"];
  if (flags.path) kaggleArgs.push("--path", flags.path);
  proxyCommand(kaggleArgs);
}

async function cmdKernelPush() {
  const dir = flags.dir || process.cwd();
  log(`Push kernel from ${dir}...`);
  const r = runWithRetry(["kernels", "push", "-p", dir], { cwd: dir });
  if (/kernel push error:/i.test(r.stdout + r.stderr)) die((r.stdout + r.stderr).trim());
  log(r.stdout);
  log(`✅ Kernel pushed`);
}

async function cmdKernelStatus() {
  const kernel = args[2] || die("缺少 <username>/<kernel-slug> 参数");
  const r = execKaggle(["kernels", "status", kernel]);
  if (r.status !== 0) die(`查询失败: ${r.stderr}`);
  log(r.stdout.trim());
}

async function cmdKernelLogs() {
  const kernel = args[2] || die("缺少 <username>/<kernel-slug> 参数");
  const r = execKaggle(["kernels", "logs", kernel]);
  if (r.status !== 0) die(`拉取日志失败: ${r.stderr}`);

  if (flags.save) {
    const fs = await import("node:fs/promises");
    await fs.writeFile(flags.save, r.stdout, "utf8");
    log(`✅ 日志已保存到 ${flags.save}`);
  } else {
    console.log(r.stdout);
  }
}

async function cmdKernelOutput() {
  const kernel = args[2] || die("缺少 <username>/<kernel-slug> 参数");
  const kaggleArgs = ["kernels", "output", kernel];
  if (flags.path) kaggleArgs.push("--path", flags.path);
  if (flags.force) kaggleArgs.push("--force");
  proxyCommand(kaggleArgs);
}

async function cmdKernelDelete() {
  const kernel = args[2] || die("缺少 <username>/<kernel-slug> 参数");
  log(`⚠️ 删除 kernel: ${kernel}`);
  const r = execKaggle(["kernels", "delete", kernel, "-y"]);
  if (r.status !== 0) die(`删除失败: ${r.stderr}`);
  log(`✅ Kernel 已删除`);
}

// ── Datasets 子命令 ───────────────────────────────────────────────────

async function cmdDatasetList() {
  const kaggleArgs = ["datasets", "list"];
  if (flags.mine) kaggleArgs.push("--mine");
  if (flags.user) kaggleArgs.push("--user", flags.user);
  if (flags.page) kaggleArgs.push("--page", flags.page);
  if (flags["page-size"]) kaggleArgs.push("--page-size", flags["page-size"]);
  if (flags.search) kaggleArgs.push("--search", flags.search);
  if (flags.sort) kaggleArgs.push("--sort-by", flags.sort);
  proxyCommand(kaggleArgs);
}

async function cmdDatasetFiles() {
  const dataset = args[2] || die("缺少 <username>/<dataset-slug> 参数");
  proxyCommand(["datasets", "files", dataset]);
}

async function cmdDatasetDownload() {
  const dataset = args[2] || die("缺少 <username>/<dataset-slug> 参数");
  const kaggleArgs = ["datasets", "download", dataset];
  if (flags.path) kaggleArgs.push("--path", flags.path);
  if (flags.file) kaggleArgs.push("--file", flags.file);
  if (flags.unzip) kaggleArgs.push("--unzip");
  proxyCommand(kaggleArgs);
}

async function cmdDatasetCreate() {
  const dir = flags.dir || process.cwd();
  log(`Create dataset from ${dir}...`);
  const r = runWithRetry(["datasets", "create", "-p", dir], { cwd: dir });
  log(r.stdout);
  log(`✅ Dataset created`);
}

async function cmdDatasetVersion() {
  const dir = flags.dir || process.cwd();
  const kaggleArgs = ["datasets", "version", "-p", dir];
  if (flags.message) kaggleArgs.push("--dir-mode", flags.message);
  log(`Create new dataset version from ${dir}...`);
  const r = runWithRetry(kaggleArgs, { cwd: dir });
  log(r.stdout);
  log(`✅ New version created`);
}

async function cmdDatasetInit() {
  const kaggleArgs = ["datasets", "init"];
  if (flags.path) kaggleArgs.push("--path", flags.path);
  proxyCommand(kaggleArgs);
}

async function cmdDatasetMetadata() {
  const dataset = args[2] || die("缺少 <username>/<dataset-slug> 参数");
  const kaggleArgs = ["datasets", "metadata", dataset];
  if (flags.path) kaggleArgs.push("--path", flags.path);
  proxyCommand(kaggleArgs);
}

async function cmdDatasetStatus() {
  const dataset = args[2] || die("缺少 <username>/<dataset-slug> 参数");
  proxyCommand(["datasets", "status", dataset]);
}

async function cmdDatasetDelete() {
  const dataset = args[2] || die("缺少 <username>/<dataset-slug> 参数");
  log(`⚠️ 删除 dataset: ${dataset}`);
  const r = execKaggle(["datasets", "delete", dataset]);
  if (r.status !== 0) die(`删除失败: ${r.stderr}`);
  log(`✅ Dataset 已删除`);
}

// ── Competitions 子命令 ───────────────────────────────────────────────

async function cmdCompetitionList() {
  const kaggleArgs = ["competitions", "list"];
  if (flags.page) kaggleArgs.push("--page", flags.page);
  if (flags.search) kaggleArgs.push("--search", flags.search);
  if (flags.category) kaggleArgs.push("--category", flags.category);
  if (flags.sort) kaggleArgs.push("--sort-by", flags.sort);
  proxyCommand(kaggleArgs);
}

async function cmdCompetitionFiles() {
  const competition = args[2] || die("缺少 <competition> 参数");
  proxyCommand(["competitions", "files", competition]);
}

async function cmdCompetitionDownload() {
  const competition = args[2] || die("缺少 <competition> 参数");
  const kaggleArgs = ["competitions", "download", competition];
  if (flags.path) kaggleArgs.push("--path", flags.path);
  if (flags.file) kaggleArgs.push("--file", flags.file);
  proxyCommand(kaggleArgs);
}

async function cmdCompetitionSubmit() {
  const competition = args[2] || die("缺少 <competition> 参数");
  const file = flags.file || die("缺少 --file 参数");
  const message = flags.message || "Submission via kaggle-ops";
  const kaggleArgs = ["competitions", "submit", competition, "-f", file, "-m", message];
  log(`Submit to ${competition}...`);
  const r = runWithRetry(kaggleArgs);
  log(r.stdout);
  log(`✅ Submitted`);
}

async function cmdCompetitionSubmissions() {
  const competition = args[2] || die("缺少 <competition> 参数");
  proxyCommand(["competitions", "submissions", competition]);
}

async function cmdCompetitionLeaderboard() {
  const competition = args[2] || die("缺少 <competition> 参数");
  const kaggleArgs = ["competitions", "leaderboard", competition];
  if (flags.path) kaggleArgs.push("--path", flags.path);
  proxyCommand(kaggleArgs);
}

// ── Models 子命令 ─────────────────────────────────────────────────────

async function cmdModelList() {
  const kaggleArgs = ["models", "list"];
  if (flags.search) kaggleArgs.push("--search", flags.search);
  if (flags.sort) kaggleArgs.push("--sort-by", flags.sort);
  proxyCommand(kaggleArgs);
}

async function cmdModelGet() {
  const model = args[2] || die("缺少 <owner>/<model-name> 参数");
  proxyCommand(["models", "get", model]);
}

async function cmdModelInit() {
  const kaggleArgs = ["models", "init"];
  if (flags.path) kaggleArgs.push("--path", flags.path);
  proxyCommand(kaggleArgs);
}

async function cmdModelCreate() {
  const dir = flags.dir || process.cwd();
  log(`Create model from ${dir}...`);
  const r = runWithRetry(["models", "create", "-p", dir], { cwd: dir });
  log(r.stdout);
  log(`✅ Model created`);
}

async function cmdModelDelete() {
  const model = args[2] || die("缺少 <owner>/<model-name> 参数");
  log(`⚠️ 删除 model: ${model}`);
  const r = execKaggle(["models", "delete", model]);
  if (r.status !== 0) die(`删除失败: ${r.stderr}`);
  log(`✅ Model 已删除`);
}

// ── Config & Auth 子命令 ──────────────────────────────────────────────

async function cmdConfigView() {
  proxyCommand(["config", "view"]);
}

async function cmdConfigSet() {
  const key = args[2] || die("缺少 <key> 参数");
  const value = args[3] || die("缺少 <value> 参数");
  proxyCommand(["config", "set", key, value]);
}

async function cmdConfigUnset() {
  const key = args[2] || die("缺少 <key> 参数");
  proxyCommand(["config", "unset", key]);
}

// ── Quota 子命令 ──────────────────────────────────────────────────────

async function cmdQuota() {
  const r = execKaggle(["quota"]);
  if (r.status !== 0) die(`查询配额失败: ${r.stderr}`);
  console.log(r.stdout);
}

// ── 主路由 ────────────────────────────────────────────────────────────

function usage() {
  console.log(`Kaggle CLI 完整封装 (覆盖所有官方功能)

用法:
  node kaggle-cli.mjs <command> <subcommand> [args...] [flags...]

全局参数:
  --account <name>      使用哪个配置文件(默认 default)
  --config <path>       明确指定配置文件路径
  --kaggle <path>       明确指定 kaggle CLI 路径
  --retries <n>         最大重试次数(默认 3)
  --retry-delay <ms>    重试间隔毫秒(默认 2000)

═══════════════════════════════════════════════════════════════════════

KERNELS 命令:
  kernels list [--mine] [--user <user>] [--page <n>] [--search <term>] [--sort <field>]
  kernels files <username>/<kernel-slug>
  kernels get <username>/<kernel-slug> [--path <dir>] [--metadata]
  kernels init [--path <dir>]
  kernels push [--dir <path>]
  kernels status <username>/<kernel-slug>
  kernels logs <username>/<kernel-slug> [--save <file>]
  kernels output <username>/<kernel-slug> [--path <dir>] [--force]
  kernels delete <username>/<kernel-slug>

DATASETS 命令:
  datasets list [--mine] [--user <user>] [--page <n>] [--search <term>] [--sort <field>]
  datasets files <username>/<dataset-slug>
  datasets download <username>/<dataset-slug> [--path <dir>] [--file <name>] [--unzip]
  datasets create [--dir <path>]
  datasets version [--dir <path>] [--message <msg>]
  datasets init [--path <dir>]
  datasets metadata <username>/<dataset-slug> [--path <dir>]
  datasets status <username>/<dataset-slug>
  datasets delete <username>/<dataset-slug>

COMPETITIONS 命令:
  competitions list [--page <n>] [--search <term>] [--category <cat>] [--sort <field>]
  competitions files <competition>
  competitions download <competition> [--path <dir>] [--file <name>]
  competitions submit <competition> --file <path> [--message <msg>]
  competitions submissions <competition>
  competitions leaderboard <competition> [--path <dir>]

MODELS 命令:
  models list [--search <term>] [--sort <field>]
  models get <owner>/<model-name>
  models init [--path <dir>]
  models create [--dir <path>]
  models delete <owner>/<model-name>

CONFIG 命令:
  config view
  config set <key> <value>
  config unset <key>

其他:
  quota                 查询 GPU/TPU 配额

示例:
  # 使用环境变量
  export KAGGLE_USERNAME=your-name KAGGLE_KEY=KGAT_xxx
  node kaggle-cli.mjs kernels push --dir /path/to/kernel

  # 使用多账号
  node kaggle-cli.mjs datasets list --mine --account backup

  # 竞赛提交
  node kaggle-cli.mjs competitions submit titanic --file submission.csv --message "Random Forest v2"

  # 下载数据
  node kaggle-cli.mjs datasets download username/dataset-name --unzip --path ./data
`);
}

(async () => {
  const cmd = args[0];
  if (!cmd || cmd === "--help" || cmd === "-h") {
    usage();
    process.exit(0);
  }

  const sub = args[1];

  // Kernels
  if (cmd === "kernels" || cmd === "kernel") {
    if (sub === "list") await cmdKernelList();
    else if (sub === "files") await cmdKernelFiles();
    else if (sub === "get" || sub === "pull") await cmdKernelGet();
    else if (sub === "init") await cmdKernelInit();
    else if (sub === "push") await cmdKernelPush();
    else if (sub === "status") await cmdKernelStatus();
    else if (sub === "logs") await cmdKernelLogs();
    else if (sub === "output") await cmdKernelOutput();
    else if (sub === "delete") await cmdKernelDelete();
    else die(`未知 kernels 子命令: ${sub}。用 --help 查看用法`);
  }
  // Datasets
  else if (cmd === "datasets" || cmd === "dataset") {
    if (sub === "list") await cmdDatasetList();
    else if (sub === "files") await cmdDatasetFiles();
    else if (sub === "download") await cmdDatasetDownload();
    else if (sub === "create" || sub === "push") await cmdDatasetCreate();
    else if (sub === "version") await cmdDatasetVersion();
    else if (sub === "init") await cmdDatasetInit();
    else if (sub === "metadata") await cmdDatasetMetadata();
    else if (sub === "status") await cmdDatasetStatus();
    else if (sub === "delete") await cmdDatasetDelete();
    else die(`未知 datasets 子命令: ${sub}。用 --help 查看用法`);
  }
  // Competitions
  else if (cmd === "competitions" || cmd === "competition") {
    if (sub === "list") await cmdCompetitionList();
    else if (sub === "files") await cmdCompetitionFiles();
    else if (sub === "download") await cmdCompetitionDownload();
    else if (sub === "submit") await cmdCompetitionSubmit();
    else if (sub === "submissions") await cmdCompetitionSubmissions();
    else if (sub === "leaderboard") await cmdCompetitionLeaderboard();
    else die(`未知 competitions 子命令: ${sub}。用 --help 查看用法`);
  }
  // Models
  else if (cmd === "models" || cmd === "model") {
    if (sub === "list") await cmdModelList();
    else if (sub === "get") await cmdModelGet();
    else if (sub === "init") await cmdModelInit();
    else if (sub === "create") await cmdModelCreate();
    else if (sub === "delete") await cmdModelDelete();
    else die(`未知 models 子命令: ${sub}。用 --help 查看用法`);
  }
  // Config
  else if (cmd === "config") {
    if (sub === "view") await cmdConfigView();
    else if (sub === "set") await cmdConfigSet();
    else if (sub === "unset") await cmdConfigUnset();
    else die(`未知 config 子命令: ${sub}。用 --help 查看用法`);
  }
  // Quota
  else if (cmd === "quota") {
    await cmdQuota();
  }
  // 未知命令
  else {
    die(`未知命令: ${cmd}。用 --help 查看用法`);
  }
})().catch((e) => die(e.message));
