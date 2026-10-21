#!/usr/bin/env node

import { execFile } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);
const perCheckTimeoutMs = Number(process.env.CODEX_VERSION_AUDIT_TIMEOUT_MS || 10000);
const deadline = Date.now() + Number(process.env.CODEX_VERSION_AUDIT_TOTAL_TIMEOUT_MS || 45000);

const resolveExecutable = (command) => {
  if (command.includes(path.sep)) return command;
  const directories = [
    ...(process.env.PATH || "").split(path.delimiter),
    process.env.HOME && path.join(process.env.HOME, ".volta", "bin"),
    process.env.HOME && path.join(process.env.HOME, ".local", "bin"),
  ].filter(Boolean);
  return directories.map((directory) => path.join(directory, command)).find((file) => {
    try {
      fs.accessSync(file, fs.constants.X_OK);
      return true;
    } catch {
      return false;
    }
  }) || command;
};

const remainingTimeout = () => {
  const remaining = deadline - Date.now();
  if (remaining <= 0) throw new Error("总超时");
  return Math.min(perCheckTimeoutMs, remaining);
};

const run = async (command, args) => {
  const { stdout } = await execFileAsync(resolveExecutable(command), args, {
    encoding: "utf8",
    timeout: remainingTimeout(),
    maxBuffer: 4 * 1024 * 1024,
  });
  return stdout.trim();
};

export const parseSemver = (value) => {
  const match = String(value || "").match(/(?:^|\s|v)(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?(?:\+[0-9A-Za-z.-]+)?(?:$|\s)/);
  if (!match) return null;
  return {
    major: Number(match[1]),
    minor: Number(match[2]),
    patch: Number(match[3]),
    prerelease: match[4]?.split(".") || [],
    raw: `${match[1]}.${match[2]}.${match[3]}${match[4] ? `-${match[4]}` : ""}`,
  };
};

const comparePrerelease = (left, right) => {
  if (!left.length && !right.length) return 0;
  if (!left.length) return 1;
  if (!right.length) return -1;
  for (let index = 0; index < Math.max(left.length, right.length); index += 1) {
    if (left[index] === undefined) return -1;
    if (right[index] === undefined) return 1;
    if (left[index] === right[index]) continue;
    const leftNumber = /^\d+$/.test(left[index]) ? Number(left[index]) : null;
    const rightNumber = /^\d+$/.test(right[index]) ? Number(right[index]) : null;
    if (leftNumber !== null && rightNumber !== null) return Math.sign(leftNumber - rightNumber);
    if (leftNumber !== null) return -1;
    if (rightNumber !== null) return 1;
    return left[index].localeCompare(right[index]);
  }
  return 0;
};

export const compareSemver = (leftValue, rightValue) => {
  const left = parseSemver(leftValue);
  const right = parseSemver(rightValue);
  if (!left || !right) return null;
  for (const key of ["major", "minor", "patch"]) {
    if (left[key] !== right[key]) return Math.sign(left[key] - right[key]);
  }
  return comparePrerelease(left.prerelease, right.prerelease);
};

const readJson = (file) => JSON.parse(fs.readFileSync(file, "utf8"));
const readFixtureOrCommand = async (fixtureEnv, command, args) => {
  const fixture = process.env[fixtureEnv];
  return fixture ? readJson(fixture) : JSON.parse(await run(command, args));
};

const fetchJson = async (url, fixtureEnv) => {
  const fixture = process.env[fixtureEnv];
  if (fixture) return readJson(fixture);
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), remainingTimeout());
  try {
    const response = await fetch(url, { signal: controller.signal });
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    return response.json();
  } finally {
    clearTimeout(timer);
  }
};

const manifestFor = (plugin, marketplace) => {
  const roots = [plugin.source?.path, plugin.source?.url].filter((value) => value && path.isAbsolute(value));
  const candidates = [
    ...roots.map((root) => path.join(root, ".codex-plugin", "plugin.json")),
    marketplace?.root && path.join(marketplace.root, "plugins", plugin.name, ".codex-plugin", "plugin.json"),
    marketplace?.root && path.join(marketplace.root, ".codex-plugin", "plugin.json"),
  ].filter(Boolean);
  for (const file of candidates) {
    try {
      const manifest = readJson(file);
      if (manifest.version && (!manifest.name || manifest.name === plugin.name)) return { file, version: String(manifest.version) };
    } catch {
      // Try the next standard Codex plugin manifest location.
    }
  }
  return null;
};

const originFor = async (marketplace) => {
  const configured = marketplace?.marketplaceSource;
  if (configured?.sourceType === "git" && configured.source) return configured.source;
  if (!marketplace?.root) return null;
  try {
    return await run(process.env.CODEX_VERSION_AUDIT_GIT_BIN || "git", ["-C", marketplace.root, "remote", "get-url", "origin"]);
  } catch {
    return null;
  }
};

const githubRepo = (remote) => {
  const match = String(remote || "").match(/github\.com[/:]([^/]+)\/([^/]+?)(?:\.git)?$/);
  return match ? `${match[1]}/${match[2]}` : null;
};

const remoteVersion = async (remote, manifestPath) => {
  const repo = githubRepo(remote);
  if (!repo || !manifestPath) throw new Error("无可读取的公开上游 manifest");
  const refs = await run(process.env.CODEX_VERSION_AUDIT_GIT_BIN || "git", ["ls-remote", "--symref", remote, "HEAD"]);
  const branch = refs.match(/ref:\s+refs\/heads\/(\S+)\s+HEAD/)?.[1];
  if (!branch) throw new Error("无法判断上游默认分支");
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), remainingTimeout());
  try {
    const response = await fetch(`https://raw.githubusercontent.com/${repo}/${branch}/${manifestPath}`, { signal: controller.signal });
    if (!response.ok) throw new Error(`上游 manifest HTTP ${response.status}`);
    const manifest = await response.json();
    if (!manifest.version) throw new Error("上游 manifest 无版本");
    return String(manifest.version);
  } finally {
    clearTimeout(timer);
  }
};

const versionState = (current, latest) => {
  if (!latest) return "无法判断";
  if (current === latest) return "已是最新";
  const comparison = compareSemver(current, latest);
  if (comparison === null) return "无法判断";
  if (comparison < 0) return "可更新";
  if (comparison > 0) return "本地较新";
  return "已是最新";
};

const printRow = (type, item, current, latest, state, note = "") => {
  console.log([type, item, current || "无法判断", latest || "无法判断", state, note].join(" | "));
};

const commandVersion = (command, args = ["--version"]) => run(command, args)
  .then((value) => parseSemver(value)?.raw || null)
  .catch(() => null);

const auditExternalTools = async () => {
  const npmBin = process.env.CODEX_VERSION_AUDIT_NPM_BIN || "npm";
  const [rtkCurrent, rtkLatest, codegraphCurrent, codegraphLatest, reviewGraphCurrent, reviewGraphLatest] = await Promise.all([
    commandVersion(process.env.CODEX_VERSION_AUDIT_RTK_BIN || "rtk", ["--version"]),
    run(process.env.CODEX_VERSION_AUDIT_BREW_BIN || "brew", ["info", "--json=v2", "rtk"])
      .then((value) => parseSemver(JSON.parse(value).formulae?.[0]?.versions?.stable)?.raw || null)
      .catch(() => null),
    commandVersion(process.env.CODEX_VERSION_AUDIT_CODEGRAPH_BIN || "codegraph"),
    commandVersion(npmBin, ["view", "@colbymchenry/codegraph", "version", "--registry=https://registry.npmjs.org"]),
    commandVersion(process.env.CODEX_VERSION_AUDIT_CODE_REVIEW_GRAPH_BIN || "code-review-graph"),
    fetchJson("https://pypi.org/pypi/code-review-graph/json", "CODEX_VERSION_AUDIT_CODE_REVIEW_GRAPH_PYPI_JSON")
      .then((value) => parseSemver(value.info?.version)?.raw || null)
      .catch(() => null),
  ]);

  return [
    ["CLI", "rtk", rtkCurrent, rtkLatest, versionState(rtkCurrent, rtkLatest), "Homebrew"],
    ["CLI", "codegraph", codegraphCurrent, codegraphLatest, versionState(codegraphCurrent, codegraphLatest), "npmjs.org"],
    ["CLI", "code-review-graph", reviewGraphCurrent, reviewGraphLatest, versionState(reviewGraphCurrent, reviewGraphLatest), "PyPI"],
  ];
};

const audit = async () => {
  console.log("类型 | 项目 | 当前版本 | 最新版本 | 状态 | 依据");

  const codexBin = process.env.CODEX_VERSION_AUDIT_CODEX_BIN || "codex";
  const npmBin = process.env.CODEX_VERSION_AUDIT_NPM_BIN || "npm";
  const [currentCli, latestCli] = await Promise.all([
    run(codexBin, ["--version"]).then((value) => parseSemver(value)?.raw || null).catch(() => null),
    run(npmBin, ["view", "@openai/codex", "version", "--registry=https://registry.npmjs.org"])
      .then((value) => parseSemver(value)?.raw || null)
      .catch(() => null),
  ]);
  printRow("Codex", "@openai/codex", currentCli, latestCli, versionState(currentCli, latestCli), "npmjs.org");
  (await auditExternalTools()).forEach((row) => printRow(...row));

  let pluginState;
  let marketplaceState;
  try {
    [pluginState, marketplaceState] = await Promise.all([
      readFixtureOrCommand("CODEX_VERSION_AUDIT_PLUGIN_LIST_JSON", codexBin, ["plugin", "list", "--json"]),
      readFixtureOrCommand("CODEX_VERSION_AUDIT_MARKETPLACE_LIST_JSON", codexBin, ["plugin", "marketplace", "list", "--json"]),
    ]);
  } catch (error) {
    printRow("插件", "全部", null, null, "无法判断", `Codex 插件命令失败: ${error.message}`);
    console.log("VERSION_AUDIT_DONE");
    return;
  }

  const marketplaces = new Map((marketplaceState.marketplaces || []).map((item) => [item.name, item]));
  const plugins = (pluginState.installed || []).filter((item) => (
    item.enabled !== false
    && marketplaces.get(item.marketplaceName)?.marketplaceSource?.sourceType === "git"
  ));

  const rows = await Promise.all(plugins.map(async (plugin) => {
    const marketplace = marketplaces.get(plugin.marketplaceName);
    const manifest = manifestFor(plugin, marketplace);
    const localVersion = manifest?.version || null;
    let latest = localVersion;
    let note = localVersion ? "本地 marketplace" : "未找到本地 manifest";
    let upstreamChecked = false;
    try {
      const origin = await originFor(marketplace);
      const relativeManifest = manifest && marketplace?.root ? path.relative(marketplace.root, manifest.file) : null;
      if (origin && relativeManifest && !relativeManifest.startsWith("..")) {
        latest = await remoteVersion(origin, relativeManifest);
        note = "公开上游 manifest";
        upstreamChecked = true;
      }
    } catch (error) {
      note = `无法判断上游: ${error.message}`;
    }

    let state = versionState(String(plugin.version || ""), latest);
    if (!upstreamChecked && state === "已是最新") state = "无法判断";
    return ["插件", plugin.pluginId || plugin.name, String(plugin.version || ""), latest, state, note];
  }));
  rows.forEach((row) => printRow(...row));

  console.log("VERSION_AUDIT_DONE");
};

audit().catch((error) => {
  printRow("审计", "全部", null, null, "无法判断", error.message);
  console.log("VERSION_AUDIT_DONE");
});
