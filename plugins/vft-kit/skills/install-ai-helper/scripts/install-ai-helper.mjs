#!/usr/bin/env node

import { createHash } from "node:crypto";
import { constants as fsConstants } from "node:fs";
import {
  access,
  mkdir,
  mkdtemp,
  readFile,
  readdir,
  rename,
  rm,
} from "node:fs/promises";
import { homedir, tmpdir } from "node:os";
import { basename, dirname, join } from "node:path";
import { Readable } from "node:stream";
import { pipeline } from "node:stream/promises";
import { spawnSync } from "node:child_process";
import { createReadStream, createWriteStream } from "node:fs";

const DEFAULT_REPO = "Miofly/vft-kit";
const RELEASE_PREFIX = "ai-helper-v";
const EXPECTED_BUNDLE_ID = "com.wfly.ai-helper";
const EXPECTED_TEAM_ID = "K46RM9974S";
const APP_NAMES = ["ai-helper.app", "AIHelper.app"];

function usage() {
  console.log(`Usage:
  install-ai-helper.mjs --check
  install-ai-helper.mjs --install [--no-launch] [--destination <directory>]

Environment overrides for maintainers/tests:
  AI_HELPER_GITHUB_REPO       GitHub owner/repo (default: ${DEFAULT_REPO})
  AI_HELPER_RELEASES_FILE     Read GitHub releases JSON from a local fixture
`);
}

function fail(message) {
  console.error(`ERROR: ${message}`);
  process.exitCode = 1;
}

function run(command, args, options = {}) {
  const result = spawnSync(command, args, {
    encoding: "utf8",
    stdio: options.capture ? "pipe" : "inherit",
  });
  if (result.error) throw result.error;
  if (result.status !== 0 && !options.allowFailure) {
    const detail = options.capture ? (result.stderr || result.stdout || "").trim() : "";
    throw new Error(`${command} exited with ${result.status}${detail ? `: ${detail}` : ""}`);
  }
  return result;
}

function parseArgs(argv) {
  const options = { mode: null, launch: true, destination: null };
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === "--check" || arg === "--install") options.mode = arg.slice(2);
    else if (arg === "--no-launch") options.launch = false;
    else if (arg === "--destination") options.destination = argv[++index];
    else if (arg === "--help" || arg === "-h") options.help = true;
    else throw new Error(`Unknown argument: ${arg}`);
  }
  if (!options.help && !options.mode) throw new Error("Choose --check or --install.");
  if (options.destination === undefined) throw new Error("--destination requires a directory.");
  return options;
}

async function fetchReleases(repo) {
  const fixture = process.env.AI_HELPER_RELEASES_FILE;
  if (fixture) return JSON.parse(await readFile(fixture, "utf8"));

  try {
    const ghResult = run("gh", ["api", `repos/${repo}/releases`, "--paginate"], {
      capture: true,
      allowFailure: true,
    });
    if (ghResult.status === 0 && ghResult.stdout.trim()) {
      return JSON.parse(ghResult.stdout);
    }
  } catch {
    // gh is optional; continue with the public API.
  }

  const token = process.env.GH_TOKEN || process.env.GITHUB_TOKEN;
  const response = await fetch(`https://api.github.com/repos/${repo}/releases?per_page=30`, {
    headers: {
      Accept: "application/vnd.github+json",
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      "User-Agent": "vft-kit-install-ai-helper",
      "X-GitHub-Api-Version": "2022-11-28",
    },
  });
  if (!response.ok) {
    throw new Error(`GitHub Releases request failed: HTTP ${response.status}`);
  }
  return response.json();
}

function selectRelease(releases) {
  for (const release of releases) {
    if (release.draft || release.prerelease || !release.tag_name?.startsWith(RELEASE_PREFIX)) continue;
    const dmg = release.assets?.find((asset) => /^AIHelper-[0-9][A-Za-z0-9.+-]*\.dmg$/.test(asset.name));
    if (!dmg) continue;
    const checksum = release.assets?.find((asset) => asset.name === `${dmg.name}.sha256`);
    if (!checksum) {
      throw new Error(`Release ${release.tag_name} is missing ${dmg.name}.sha256.`);
    }
    return { release, dmg, checksum };
  }
  return null;
}

async function fileExists(path) {
  try {
    await access(path);
    return true;
  } catch {
    return false;
  }
}

async function findInstalledApp() {
  const roots = ["/Applications", join(homedir(), "Applications")];
  for (const root of roots) {
    for (const name of APP_NAMES) {
      const candidate = join(root, name);
      if (await fileExists(candidate)) return candidate;
    }
  }
  return null;
}

function plistValue(appPath, key) {
  const plist = join(appPath, "Contents", "Info.plist");
  const result = run("/usr/libexec/PlistBuddy", ["-c", `Print :${key}`, plist], { capture: true });
  return result.stdout.trim();
}

async function download(url, destination) {
  const response = await fetch(url, { headers: { "User-Agent": "vft-kit-install-ai-helper" } });
  if (!response.ok || !response.body) throw new Error(`Download failed: HTTP ${response.status} ${url}`);
  await pipeline(Readable.fromWeb(response.body), createWriteStream(destination));
}

async function sha256(path) {
  const hash = createHash("sha256");
  for await (const chunk of createReadStream(path)) hash.update(chunk);
  return hash.digest("hex");
}

function verifyApp(appPath) {
  const bundleId = plistValue(appPath, "CFBundleIdentifier");
  if (bundleId !== EXPECTED_BUNDLE_ID) {
    throw new Error(`Unexpected bundle identifier: ${bundleId}`);
  }

  run("/usr/bin/codesign", ["--verify", "--deep", "--strict", "--verbose=2", appPath]);
  const signature = run("/usr/bin/codesign", ["-dv", "--verbose=4", appPath], {
    capture: true,
    allowFailure: true,
  });
  const signatureText = `${signature.stdout}\n${signature.stderr}`;
  if (!signatureText.includes(`TeamIdentifier=${EXPECTED_TEAM_ID}`)) {
    throw new Error(`App is not signed by expected Team ID ${EXPECTED_TEAM_ID}.`);
  }
  run("/usr/sbin/spctl", ["--assess", "--type", "execute", "--verbose=2", appPath]);
}

async function chooseDestination(explicitDirectory) {
  if (explicitDirectory) {
    await mkdir(explicitDirectory, { recursive: true });
    await access(explicitDirectory, fsConstants.W_OK);
    return explicitDirectory;
  }
  try {
    await access("/Applications", fsConstants.W_OK);
    return "/Applications";
  } catch {
    const userApplications = join(homedir(), "Applications");
    await mkdir(userApplications, { recursive: true });
    return userApplications;
  }
}

async function installApp(sourceApp, destinationDirectory, destinationName) {
  const destination = join(destinationDirectory, destinationName);
  const staging = join(destinationDirectory, `.ai-helper.app.installing-${process.pid}`);
  const backup = join(destinationDirectory, `.ai-helper.app.backup-${process.pid}`);

  run("/usr/bin/osascript", [
    "-e",
    `tell application id \"${EXPECTED_BUNDLE_ID}\" to quit`,
  ], { allowFailure: true, capture: true });

  await rm(staging, { recursive: true, force: true });
  run("/usr/bin/ditto", [sourceApp, staging]);
  verifyApp(staging);

  let backedUp = false;
  try {
    if (await fileExists(destination)) {
      await rm(backup, { recursive: true, force: true });
      await rename(destination, backup);
      backedUp = true;
    }
    await rename(staging, destination);
    await rm(backup, { recursive: true, force: true });
    return destination;
  } catch (error) {
    await rm(staging, { recursive: true, force: true });
    if (backedUp && !(await fileExists(destination))) await rename(backup, destination);
    throw error;
  }
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help) return usage();
  if (process.platform !== "darwin") throw new Error("ai-helper supports macOS only.");

  const repo = process.env.AI_HELPER_GITHUB_REPO || DEFAULT_REPO;
  const installedApp = await findInstalledApp();
  const installedVersion = installedApp ? plistValue(installedApp, "CFBundleShortVersionString") : null;
  console.log(`Installed: ${installedVersion ? `${installedVersion} (${installedApp})` : "not installed"}`);
  const selected = selectRelease(await fetchReleases(repo));
  if (!selected) {
    throw new Error(`No published ${RELEASE_PREFIX}* release with a signed DMG was found in ${repo}.`);
  }
  console.log(`Latest: ${selected.release.tag_name} (${selected.dmg.name})`);
  if (options.mode === "check") return;

  const temporaryDirectory = await mkdtemp(join(tmpdir(), "ai-helper-install-"));
  const dmgPath = join(temporaryDirectory, selected.dmg.name);
  const checksumPath = join(temporaryDirectory, selected.checksum.name);
  const mountPoint = join(temporaryDirectory, "mount");
  let mounted = false;

  try {
    await Promise.all([
      download(selected.dmg.browser_download_url, dmgPath),
      download(selected.checksum.browser_download_url, checksumPath),
    ]);
    const checksumText = await readFile(checksumPath, "utf8");
    const expectedHash = checksumText.match(/\b[0-9a-fA-F]{64}\b/)?.[0]?.toLowerCase();
    if (!expectedHash) throw new Error(`Invalid checksum file: ${selected.checksum.name}`);
    const actualHash = await sha256(dmgPath);
    if (actualHash !== expectedHash) throw new Error("DMG SHA-256 verification failed.");

    await mkdir(mountPoint);
    run("/usr/bin/hdiutil", ["attach", "-readonly", "-nobrowse", "-mountpoint", mountPoint, dmgPath]);
    mounted = true;
    const mountedEntries = await readdir(mountPoint, { withFileTypes: true });
    const appEntry = mountedEntries.find((entry) => entry.isDirectory() && APP_NAMES.includes(entry.name));
    if (!appEntry) throw new Error("The DMG does not contain ai-helper.app.");

    const sourceApp = join(mountPoint, appEntry.name);
    verifyApp(sourceApp);
    const destinationDirectory = options.destination
      ? await chooseDestination(options.destination)
      : installedApp
        ? dirname(installedApp)
        : await chooseDestination(null);
    const destinationName = installedApp ? basename(installedApp) : "ai-helper.app";
    const installedPath = await installApp(sourceApp, destinationDirectory, destinationName);
    const version = plistValue(installedPath, "CFBundleShortVersionString");
    if (options.launch) run("/usr/bin/open", [installedPath]);
    console.log(`Installed ai-helper ${version} at ${installedPath}`);
  } finally {
    if (mounted) run("/usr/bin/hdiutil", ["detach", mountPoint], { allowFailure: true });
    await rm(temporaryDirectory, { recursive: true, force: true });
  }
}

main().catch((error) => fail(error.message));
