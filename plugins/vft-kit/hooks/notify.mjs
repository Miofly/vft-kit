#!/usr/bin/env node
// Claude Code macOS 桌面通知：任务完成 / 任务失败 / 等待输入 / 对话完成。
//
// 挂在 Stop / PostToolUse / PreToolUse / PermissionRequest 四个事件上（见 hooks.json）。
// 单个 turn 的状态（是否出错、调用了几次工具）靠 ~/.claude/vft-kit/ 下的状态文件跨事件传递，
// 因为每次 hook 都是独立进程，无法共享内存。
//
// 配置：~/.claude/vft-kit/notify-config.json（不存在则用下面的内建默认值，不会自动生成文件）。
// 调试：设 CLAUDE_NOTIFY_DEBUG=1 才写日志。

import { readFileSync, writeFileSync, existsSync, mkdirSync, statSync } from 'fs';
import { join, dirname } from 'path';
import { homedir } from 'os';
import { execFile, spawn } from 'child_process';
import { fileURLToPath } from 'url';

const HOME = homedir();
const DATA_DIR = join(HOME, '.claude/vft-kit');
const CONFIG_PATH = join(DATA_DIR, 'notify-config.json');
const LEGACY_CONFIG_PATH = join(HOME, '.claude/hooks/notify-config.json');
const STATE_FILE = join(DATA_DIR, '.notify-turn-state.json');
const DEBOUNCE_FILE = join(DATA_DIR, '.notify-debounce.json');
const DEBUG_LOG = join(DATA_DIR, '.notify-debug.log');
// 自绘横幅：源码与本脚本同目录(相对定位，不写死安装路径)，编译产物落 DATA_DIR/bin
const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
const BANNER_SRC = join(SCRIPT_DIR, 'banner.swift');
const BIN_DIR = join(DATA_DIR, 'bin');
const BANNER_BIN = join(BIN_DIR, 'banner');
const DEBUG = process.env.CLAUDE_NOTIFY_DEBUG === '1';
const DEBUG_LOG_MAX_BYTES = 1024 * 1024;

const DEFAULT_CONFIG = {
  enabled: true,
  iconPath: '~/Pictures/claude.icon.png',
  notifications: {
    taskComplete: { enabled: true, title: 'Claude Code', subtitle: '任务完成 ✅', sound: 'Hero' },
    taskError: { enabled: true, title: 'Claude Code', subtitle: '任务失败 ❌', sound: 'Basso' },
    waitingForInput: { enabled: true, title: 'Claude Code', subtitle: '等待您的输入 ⏸️', sound: 'default' },
    conversationComplete: { enabled: true, title: 'Claude Code', subtitle: '对话已完成 💬', sound: 'Glass' },
  },
  debounce: { enabled: true, intervalSeconds: 5 },
  // 自绘横幅：仿 macOS 原生通知，在屏幕右上角画横幅。需 macOS + swiftc；单屏/无 swiftc 自动降级。
  //   allScreens=true ：两屏都弹自绘横幅，并关掉原生 terminal-notifier(不撞车)，提示音由横幅补放。
  //   allScreens=false：主屏发原生系统通知 + 副屏补横幅(附加式，非破坏)。
  // 兜底：横幅二进制若不存在(没 swiftc/未编译)，自动退回发原生通知，绝不「零通知」。
  dualScreenBanner: { enabled: true, allScreens: true, durationSeconds: 5 },
};

function debug(msg) {
  if (!DEBUG) return;
  try {
    ensureDataDir();
    if (existsSync(DEBUG_LOG) && statSync(DEBUG_LOG).size > DEBUG_LOG_MAX_BYTES) {
      writeFileSync(DEBUG_LOG, '');
    }
    writeFileSync(DEBUG_LOG, `[${new Date().toISOString()}] ${msg}\n`, { flag: 'a' });
  } catch {}
}

function ensureDataDir() {
  if (!existsSync(DATA_DIR)) mkdirSync(DATA_DIR, { recursive: true });
}

function readJson(path, fallback) {
  try {
    return JSON.parse(readFileSync(path, 'utf-8'));
  } catch {
    return fallback;
  }
}

function writeJson(path, value) {
  try {
    ensureDataDir();
    writeFileSync(path, JSON.stringify(value));
  } catch {}
}

function loadConfig() {
  const path = existsSync(CONFIG_PATH) ? CONFIG_PATH : LEGACY_CONFIG_PATH;
  const user = readJson(path, null);
  if (!user) return DEFAULT_CONFIG;
  // 用户配置只需写想改的字段，其余落回默认值
  return {
    ...DEFAULT_CONFIG,
    ...user,
    notifications: { ...DEFAULT_CONFIG.notifications, ...(user.notifications ?? {}) },
    debounce: { ...DEFAULT_CONFIG.debounce, ...(user.debounce ?? {}) },
    dualScreenBanner: { ...DEFAULT_CONFIG.dualScreenBanner, ...(user.dualScreenBanner ?? {}) },
  };
}

// terminal-notifier 收到的是原样字符串，不经 shell，所以 ~ 必须自己展开
function expandHome(p) {
  if (typeof p !== 'string') return p;
  return p.startsWith('~/') ? join(HOME, p.slice(2)) : p;
}

async function readStdin() {
  return new Promise((resolve) => {
    let data = '';
    process.stdin.on('data', (chunk) => (data += chunk));
    process.stdin.on('end', () => {
      try {
        resolve(JSON.parse(data));
      } catch {
        resolve({});
      }
    });
  });
}

const EMPTY_TURN = { hasError: false, toolCount: 0 };

function loadTurnState() {
  return readJson(STATE_FILE, EMPTY_TURN);
}

function checkDebounce(type, config) {
  if (!config.debounce.enabled) return true;

  const state = readJson(DEBOUNCE_FILE, {});
  const now = Date.now();
  if (now - (state[type] || 0) < config.debounce.intervalSeconds * 1000) return false;

  state[type] = now;
  writeJson(DEBOUNCE_FILE, state);
  return true;
}

// 只认工具显式声明的失败信号。曾经还检查过 stderr 非空和响应文本里的 error/failed 字样，
// 但 git、npm 等命令成功时也往 stderr 写东西，那样会把正常输出误报成「任务失败」。
function isToolFailure(response) {
  if (!response || typeof response !== 'object') return false;
  return response.is_error === true || response.isError === true || response.interrupted === true;
}

function decide(hookEvent, payload, config) {
  if (!config.enabled) return null;

  if (hookEvent === 'Stop') {
    const turn = loadTurnState();
    writeJson(STATE_FILE, EMPTY_TURN);

    // 已经就失败弹过一次了，别再报「完成」
    if (turn.hasError) return null;

    return turn.toolCount > 0
      ? { type: 'taskComplete', message: '任务已完成，可以开始下一步' }
      : { type: 'conversationComplete', message: 'Claude 已回复，请查看' };
  }

  if (hookEvent === 'PostToolUse') {
    const turn = loadTurnState();
    turn.toolCount++;

    if (!isToolFailure(payload.tool_response)) {
      writeJson(STATE_FILE, turn);
      return null;
    }

    turn.hasError = true;
    writeJson(STATE_FILE, turn);
    return { type: 'taskError', message: `${payload.tool_name} 执行失败，请检查` };
  }

  if (hookEvent === 'PreToolUse') {
    if (payload.tool_name === 'AskUserQuestion') {
      return { type: 'waitingForInput', message: 'Claude 需要您回答问题' };
    }
    if (payload.tool_name === 'ExitPlanMode') {
      return { type: 'waitingForInput', message: '计划已完成，等待您审批' };
    }
    return null;
  }

  if (hookEvent === 'PermissionRequest') {
    return { type: 'waitingForInput', message: '需要您的授权才能继续' };
  }

  return null;
}

// 横幅二进制是否已就绪。不存在则(仅 macOS)后台异步编译一次(detached 不阻塞本次 hook，
// 避免撞 hook 超时)，本次返回 false → 由 notify() 退回原生兜底，编译完成后下次生效。
function ensureBannerBinary() {
  if (existsSync(BANNER_BIN)) return true;
  if (process.platform !== 'darwin') return false;
  if (!existsSync(BANNER_SRC)) return false;
  try {
    if (!existsSync(BIN_DIR)) mkdirSync(BIN_DIR, { recursive: true });
    const c = spawn('swiftc', ['-O', BANNER_SRC, '-o', BANNER_BIN], { detached: true, stdio: 'ignore' });
    c.on('error', (e) => debug(`swiftc spawn failed: ${e.message}`));
    c.unref();
  } catch (e) {
    debug(`banner compile kick failed: ${e.message}`);
  }
  return false;
}

// 自绘横幅：detached 起进程立即 unref，node 不等它跑完，绝不拖住 hook。全程静默容错。
// allScreens 模式画两屏并接管提示音(sound)；否则只补副屏。仅在二进制已就绪时被调用。
function showBanner(title, subtitle, message, icon, sound, config) {
  const bconf = config.dualScreenBanner;
  const args = [
    '--title', title,
    '--subtitle', subtitle || '',
    '--message', message || '',
    '--duration', String(bconf.durationSeconds ?? 5),
  ];
  if (icon && existsSync(icon)) args.push('--icon', icon);
  if (bconf.allScreens) {
    args.push('--all-screens');
    if (sound) args.push('--sound', sound); // 原生被关，声音改由横幅放
  }
  try {
    const child = spawn(BANNER_BIN, args, { detached: true, stdio: 'ignore' });
    child.on('error', (e) => debug(`banner spawn failed: ${e.message}`));
    child.unref();
  } catch (e) {
    debug(`banner spawn threw: ${e.message}`);
  }
}

function notify(type, message, config) {
  const conf = config.notifications[type];
  if (!conf?.enabled) return;

  const { title, subtitle, sound } = conf;
  const icon = expandHome(config.iconPath);
  const bconf = config.dualScreenBanner;

  debug(`notify ${type}: ${message}`);

  // 横幅是否会「真的」显示：macOS + 启用 + 二进制已就绪。只有确定会显示,才敢关掉原生。
  const bannerReady = bconf?.enabled && process.platform === 'darwin' && ensureBannerBinary();
  // 两屏接管模式(allScreens) 且横幅就绪 → 不发原生(否则主屏原生 + 横幅会重叠)。
  // 反之(非接管 / 横幅没就绪) → 照发原生,保证绝不「零通知」。
  const bannerTakesOver = bannerReady && bconf.allScreens;

  if (!bannerTakesOver) {
    // execFile 不经 shell，参数原样传递，无需转义引号 / $
    const args = ['-message', message, '-title', title, '-subtitle', subtitle, '-sound', sound, '-group', `claude-code-${type}`];
    if (icon && existsSync(icon)) args.push('-contentImage', icon);

    execFile('terminal-notifier', args, (error) => {
      if (!error) return;

      // 没装 terminal-notifier 就退到系统自带的 osascript（不支持自定义图标）
      debug(`terminal-notifier failed (${error.message}), falling back to osascript`);
      const script = `display notification ${JSON.stringify(message)} with title ${JSON.stringify(title)} subtitle ${JSON.stringify(subtitle)} sound name ${JSON.stringify(sound)}`;
      execFile('osascript', ['-e', script], (err) => {
        if (err) debug(`osascript failed: ${err.message}`);
      });
    });
  }

  // 横幅就绪就显示(allScreens 画两屏、接管提示音；否则只补副屏)
  if (bannerReady) showBanner(title, subtitle, message, icon, sound, config);
}

async function main() {
  const payload = await readStdin();
  const hookEvent = payload.hook_event_name;
  if (!hookEvent) return;

  debug(`event: ${hookEvent}`);

  const config = loadConfig();
  const decision = decide(hookEvent, payload, config);
  if (!decision) return;

  if (!checkDebounce(decision.type, config)) {
    debug(`debounced: ${decision.type}`);
    return;
  }

  notify(decision.type, decision.message, config);
}

main().catch(() => {
  // hook 失败绝不能影响会话
});
