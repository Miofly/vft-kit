#!/usr/bin/env node

import { randomInt, randomUUID } from 'node:crypto';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { homedir, tmpdir } from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const EDITOR = 'Keyboard Maestro';
const ENGINE = 'Keyboard Maestro Engine';
const KM_CLI = '/Applications/Keyboard Maestro.app/Contents/MacOS/keyboardmaestro';
const UUID_RE = /^[0-9A-F]{8}-[0-9A-F]{4}-[1-5][0-9A-F]{3}-[89AB][0-9A-F]{3}-[0-9A-F]{12}$/i;
const COMMAND_SCHEMAS = {
  'add-daily-shell': { positional: [0, 0], options: ['before-macro-uid', 'command', 'days', 'dry-run', 'enable', 'group', 'name', 'time'] },
  calculate: { positional: [1, 1], options: [] },
  delete: { positional: [1, 1], options: ['backup', 'yes'] },
  doctor: { positional: [0, 0], options: [] },
  edit: { positional: [1, 1], options: [] },
  enable: { positional: [2, 2], options: [] },
  export: { positional: [2, 2], options: [] },
  help: { positional: [0, 0], options: [] },
  hotkeys: { positional: [0, 0], options: ['all'] },
  import: { positional: [1, 1], options: ['enable'] },
  list: { positional: [0, 0], options: ['all'] },
  run: { positional: [0, 1], options: ['action-file', 'async', 'parameter'] },
  show: { positional: [1, 1], options: ['xml'] },
  tokens: { positional: [1, 1], options: [] },
  'var-get': { positional: [1, 1], options: [] },
  'var-set': { positional: [2, 2], options: [] },
};

function fail(message, code = 1) {
  const error = new Error(message);
  error.exitCode = code;
  throw error;
}

function run(command, args, options = {}) {
  const result = spawnSync(command, args, {
    encoding: 'utf8',
    maxBuffer: 16 * 1024 * 1024,
    ...options,
  });
  if (result.error) fail(`${command}: ${result.error.message}`);
  if (result.status !== 0) {
    fail((result.stderr || result.stdout || `${command} 退出码 ${result.status}`).trim(), result.status || 1);
  }
  return result.stdout ?? '';
}

function osa(source, args = []) {
  return run('/usr/bin/osascript', ['-e', source, '--', ...args]).trimEnd();
}

function plistToJSON(xml) {
  const json = run('/usr/bin/plutil', ['-convert', 'json', '-o', '-', '--', '-'], { input: xml });
  return JSON.parse(json);
}

function parseArgs(argv) {
  const positional = [];
  const options = Object.create(null);
  const booleanOptions = new Set(['all', 'async', 'dry-run', 'enable', 'xml', 'yes']);
  let optionsEnded = false;
  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (token === '--' && !optionsEnded) {
      optionsEnded = true;
      continue;
    }
    if (optionsEnded || !token.startsWith('--')) {
      positional.push(token);
      continue;
    }
    const equal = token.indexOf('=');
    const key = token.slice(2, equal === -1 ? undefined : equal);
    if (booleanOptions.has(key)) {
      if (equal !== -1) fail(`布尔选项只允许裸 flag：--${key}`, 2);
      if (Object.hasOwn(options, key)) fail(`选项 --${key} 不能重复`, 2);
      options[key] = true;
      continue;
    }
    const value = equal === -1 ? argv[++index] : token.slice(equal + 1);
    if (value === undefined || (equal === -1 && value.startsWith('--'))) fail(`选项 --${key} 缺少值`, 2);
    if (Object.hasOwn(options, key)) fail(`选项 --${key} 不能重复`, 2);
    options[key] = value;
  }
  return { positional, options };
}

function validateInvocation(command, positional, options) {
  const schema = COMMAND_SCHEMAS[command];
  if (!schema) fail(`未知命令: ${command}\n运行 kmctl help 查看用法`, 2);
  const [minimum, maximum] = schema.positional;
  if (positional.length < minimum || positional.length > maximum) {
    fail(`${command} 的位置参数数量应为 ${minimum === maximum ? minimum : `${minimum}..${maximum}`}，收到 ${positional.length}`, 2);
  }
  for (const option of Object.keys(options)) {
    if (!schema.options.includes(option)) fail(`${command} 不支持选项 --${option}`, 2);
  }
  if (command === 'run' && Boolean(positional[0]) === Boolean(options['action-file'])) {
    fail('run 必须且只能提供宏名/UID 或 --action-file 之一', 2);
  }
}

function requireValue(value, label) {
  if (value === undefined || value === '') fail(`缺少 ${label}`, 2);
  return value;
}

function requirePresent(value, label) {
  if (value === undefined) fail(`缺少 ${label}`, 2);
  return value;
}

function requireUUID(value) {
  if (!UUID_RE.test(value)) fail(`只接受 Keyboard Maestro 宏 UID，收到: ${value}`, 2);
  return value.toUpperCase();
}

function parseTime(value) {
  const match = /^(?:[01]\d|2[0-3]):[0-5]\d$/.exec(value);
  if (!match) fail(`时间必须是 HH:MM（24 小时制），收到: ${value}`, 2);
  const [hour, minute] = value.split(':').map(Number);
  return { hour, minute };
}

function parseDays(value = '127') {
  const days = Number(value);
  if (!Number.isInteger(days) || days < 1 || days > 127) {
    fail(`--days 必须是 1..127 的周位掩码，收到: ${value}`, 2);
  }
  return days;
}

export function buildDailyShellMacro({ name, command, time = '09:00', days = '127', uid = randomUUID(), beforeMacroUID }) {
  const { hour, minute } = parseTime(time);
  const now = Date.now() / 1000 - 978307200;
  const actions = [];
  if (beforeMacroUID) {
    actions.push({
      ActionUID: randomInt(100000000, 999999999),
      Asynchronously: false,
      MacroActionType: 'ExecuteMacro',
      MacroUID: requireUUID(beforeMacroUID),
      TimeOutAbortsMacro: true,
      UseParameter: false,
    });
  }
  actions.push(
    {
      ActionUID: randomInt(100000000, 999999999),
      DisplayKind: 'None',
      HonourFailureSettings: true,
      IncludeStdErr: false,
      IncludedVariables: ['9999'],
      MacroActionType: 'ExecuteShellScript',
      Path: '',
      Source: 'Nothing',
      Text: command,
      TimeOutAbortsMacro: true,
      TrimResults: true,
      TrimResultsNew: true,
      UseText: true,
    },
  );
  return {
    Actions: actions,
    CreationDate: now,
    ModificationDate: now,
    Name: name,
    Triggers: [
      {
        ExecuteType: 'Time',
        MacroTriggerType: 'Time',
        TimeHour: hour,
        TimeMinutes: minute,
        WhichDays: parseDays(days),
      },
    ],
    UID: uid.toUpperCase(),
  };
}

export function buildMacroImportPayload(group, macro) {
  return [{ ...group, Macros: [macro] }];
}

function writePlist(value, outputPath) {
  const work = mkdtempSync(path.join(tmpdir(), 'kmctl-'));
  const jsonPath = path.join(work, 'value.json');
  try {
    writeFileSync(jsonPath, JSON.stringify(value), { mode: 0o600 });
    run('/usr/bin/plutil', ['-convert', 'xml1', '-o', outputPath, jsonPath]);
  } finally {
    rmSync(work, { recursive: true, force: true });
  }
}

function macroExists(uid) {
  return osa(
    `on run argv
      set macroID to item 1 of argv
      tell application "${EDITOR}"
        return exists (first macro whose id is macroID)
      end tell
    end run`,
    [uid],
  ) === 'true';
}

function importFile(file, disabled) {
  osa(
    `on run argv
      set macroFile to POSIX file (item 1 of argv)
      set forceDisabled to (item 2 of argv is "true")
      tell application "${EDITOR}" to importMacros macroFile disabled forceDisabled
    end run`,
    [path.resolve(file), disabled ? 'true' : 'false'],
  );
}

function configureImportedMacro(uid, groupName, enabled) {
  return osa(
    `on run argv
      set macroID to item 1 of argv
      set groupName to item 2 of argv
      set shouldEnable to (item 3 of argv is "true")
      tell application "${EDITOR}"
        set targetMacro to first macro whose id is macroID
        if groupName is "" then
          set targetGroup to global macro group
        else if exists (first macro group whose name is groupName) then
          set targetGroup to first macro group whose name is groupName
        else
          set targetGroup to make new macro group with properties {name:groupName, enabled:true}
        end if
        move targetMacro to end of macros of targetGroup
        set enabled of targetMacro to shouldEnable
        return id of targetMacro
      end tell
    end run`,
    [uid, groupName, enabled ? 'true' : 'false'],
  );
}

function deleteWithoutBackup(uid) {
  osa(`on run argv
    tell application "${EDITOR}" to deleteMacro (item 1 of argv)
  end run`, [uid]);
}

function getMacroXML(uid) {
  return osa(
    `on run argv
      set macroID to item 1 of argv
      tell application "${EDITOR}" to return xml of first macro whose id is macroID
    end run`,
    [uid],
  );
}

function getMacroGroupXML(uid) {
  return osa(
    `on run argv
      set macroID to item 1 of argv
      tell application "${EDITOR}"
        set targetMacro to first macro whose id is macroID
        return group xml of macro group of targetMacro
      end tell
    end run`,
    [uid],
  );
}

function getGroupMetadata(groupName) {
  const xml = osa(
    `on run argv
      set groupName to item 1 of argv
      tell application "${EDITOR}"
        if groupName is "" then return group xml of global macro group
        if exists (first macro group whose name is groupName) then
          return group xml of first macro group whose name is groupName
        end if
        return ""
      end tell
    end run`,
    [groupName],
  );
  if (xml) return plistToJSON(xml);
  const now = Date.now() / 1000 - 978307200;
  return {
    Activate: 'Normal',
    CreationDate: now,
    Name: groupName,
    ToggleMacroUID: randomUUID().toUpperCase(),
    UID: randomUUID().toUpperCase(),
  };
}

function doctor() {
  if (!existsSync('/Applications/Keyboard Maestro.app')) fail('未安装 /Applications/Keyboard Maestro.app');
  if (!existsSync(KM_CLI)) fail(`找不到 Keyboard Maestro CLI: ${KM_CLI}`);
  const editorVersion = osa(`tell application "${EDITOR}" to get version`);
  const engineVersion = osa(`tell application "${ENGINE}" to get version`);
  const calculation = osa(`tell application "${ENGINE}" to calculate "1+2"`);
  const groupCount = Number(osa(`tell application "${EDITOR}" to count macro groups`));
  console.log(JSON.stringify({ ok: calculation === '3', editorVersion, engineVersion, groupCount, cli: KM_CLI }, null, 2));
}

export function summarizeMacros(groups) {
  return groups.map((group) => ({
    enabled: group.enabled,
    name: group.name,
    uid: group.uid,
    macros: (group.macros || []).map((macro) => ({
      active: macro.active,
      enabled: macro.enabled,
      name: macro.name,
      uid: macro.uid,
      triggers: macro.triggers || [],
    })),
  }));
}

function listMacros(all) {
  const xml = osa(`tell application "${ENGINE}" to getmacros asstring true`);
  const groups = plistToJSON(xml);
  if (all) {
    console.log(JSON.stringify(groups, null, 2));
    return;
  }
  console.log(JSON.stringify(summarizeMacros(groups), null, 2));
}

function listHotkeys(all) {
  const xml = osa(`tell application "${ENGINE}" to gethotkeys asstring true getall ${all ? 'true' : 'false'}`);
  console.log(JSON.stringify(plistToJSON(xml), null, 2));
}

export function formatMacroDetails(definition, status) {
  return {
    enabled: status.enabled,
    group: status.group,
    name: definition.Name,
    uid: definition.UID,
    definition,
  };
}

function showMacro(uid, rawXML) {
  const macroUID = requireUUID(uid);
  const xml = getMacroXML(macroUID);
  if (rawXML) {
    process.stdout.write(`${xml}\n`);
    return;
  }
  const enabled = osa(`on run argv
    tell application "${EDITOR}" to return enabled of first macro whose id is item 1 of argv
  end run`, [macroUID]) === 'true';
  const group = osa(`on run argv
    tell application "${EDITOR}" to return name of macro group of first macro whose id is item 1 of argv
  end run`, [macroUID]);
  console.log(JSON.stringify(formatMacroDetails(plistToJSON(xml), { enabled, group }), null, 2));
}

function runMacro(target, options) {
  let executable = target;
  if (options['action-file']) {
    const actionPath = path.resolve(options['action-file']);
    if (!existsSync(actionPath)) fail(`Action XML 文件不存在: ${actionPath}`, 2);
    executable = readFileSync(actionPath, 'utf8');
  }
  requireValue(executable, '宏名、UID 或 --action-file');
  const args = [];
  if (options.async) args.push('--async');
  if (options.parameter !== undefined) args.push('--parameter', options.parameter);
  args.push(executable);
  process.stdout.write(run(KM_CLI, args));
}

function addDailyShell(options) {
  const name = requireValue(options.name, '--name');
  const command = requireValue(options.command, '--command');
  const macro = buildDailyShellMacro({
    name,
    command,
    time: options.time || '09:00',
    days: options.days || '127',
    beforeMacroUID: options['before-macro-uid'],
  });
  if (options['dry-run']) {
    console.log(JSON.stringify({ enabled: Boolean(options.enable), group: options.group || 'Global Macro Group', macro }, null, 2));
    return;
  }

  const work = mkdtempSync(path.join(tmpdir(), 'kmctl-import-'));
  const macroPath = path.join(work, `${macro.UID}.kmmacros`);
  let imported = false;
  try {
    const group = getGroupMetadata(options.group || '');
    writePlist(buildMacroImportPayload(group, macro), macroPath);
    importFile(macroPath, true);
    imported = macroExists(macro.UID);
    if (!imported) fail(`Keyboard Maestro 未返回已导入宏: ${macro.UID}`);
    configureImportedMacro(macro.UID, options.group || '', Boolean(options.enable));
    console.log(JSON.stringify({
      created: true,
      name: macro.Name,
      uid: macro.UID,
      group: options.group || 'Global Macro Group',
      enabled: Boolean(options.enable),
      time: options.time || '09:00',
      days: Number(options.days || 127),
    }, null, 2));
  } catch (error) {
    if (imported && macroExists(macro.UID)) deleteWithoutBackup(macro.UID);
    throw error;
  } finally {
    rmSync(work, { recursive: true, force: true });
  }
}

function importMacro(file, enabled) {
  const absolute = path.resolve(requireValue(file, '待导入文件'));
  if (!existsSync(absolute)) fail(`文件不存在: ${absolute}`, 2);
  importFile(absolute, !enabled);
  console.log(JSON.stringify({ imported: absolute, forcedDisabled: !enabled }, null, 2));
}

function exportMacro(uid, output) {
  const macroUID = requireUUID(uid);
  const destination = path.resolve(requireValue(output, '输出路径'));
  mkdirSync(path.dirname(destination), { recursive: true });
  const macro = plistToJSON(getMacroXML(macroUID));
  const group = plistToJSON(getMacroGroupXML(macroUID));
  writePlist(buildMacroImportPayload(group, macro), destination);
  console.log(JSON.stringify({ uid: macroUID, exported: destination }, null, 2));
}

function deleteMacro(uid, yes, backupOption) {
  const macroUID = requireUUID(uid);
  if (!yes) fail('删除宏必须显式添加 --yes', 2);
  const backupDir = path.join(homedir(), 'Documents', 'Keyboard Maestro Backups');
  const backup = backupOption
    ? path.resolve(backupOption)
    : path.join(backupDir, `${macroUID}-${new Date().toISOString().replace(/[:.]/g, '-')}.kmmacros`);
  mkdirSync(path.dirname(backup), { recursive: true });
  const macro = plistToJSON(getMacroXML(macroUID));
  const group = plistToJSON(getMacroGroupXML(macroUID));
  writePlist(buildMacroImportPayload(group, macro), backup);
  deleteWithoutBackup(macroUID);
  console.log(JSON.stringify({ deleted: macroUID, backup }, null, 2));
}

function setEnabled(target, value) {
  if (!['true', 'false'].includes(value)) fail('enable 的状态必须是 true 或 false', 2);
  osa(`on run argv
    tell application "${EDITOR}" to setMacroEnable (item 1 of argv) enable (item 2 of argv is "true")
  end run`, [target, value]);
  console.log(JSON.stringify({ target, enabled: value === 'true' }, null, 2));
}

function variableGet(name) {
  process.stdout.write(`${osa(`on run argv
    tell application "${ENGINE}" to getvariable (item 1 of argv)
  end run`, [name])}\n`);
}

function variableSet(name, value) {
  osa(`on run argv
    tell application "${ENGINE}" to setvariable (item 1 of argv) to (item 2 of argv)
  end run`, [name, value]);
  console.log(JSON.stringify({ variable: name, updated: true }, null, 2));
}

function usage() {
  console.log(`kmctl - Keyboard Maestro 官方脚本接口封装

用法:
  kmctl doctor
  kmctl list [--all]
  kmctl hotkeys [--all]
  kmctl show UID [--xml]
  kmctl run <宏名或UID> [--parameter VALUE] [--async]
  kmctl run --action-file ACTION.plist [--parameter VALUE] [--async]
  kmctl var-get NAME
  kmctl var-set NAME VALUE
  kmctl calculate EXPRESSION
  kmctl tokens TEXT
  kmctl edit <宏名或UID>
  kmctl enable <宏名或UID> <true|false>
  kmctl add-daily-shell --name NAME --command CMD [--time HH:MM] [--days 127] [--group NAME] [--before-macro-uid UID] [--enable] [--dry-run]
  kmctl import FILE.kmmacros [--enable]
  kmctl export UID OUTPUT.kmmacros
  kmctl delete UID --yes [--backup OUTPUT.kmmacros]
`);
}

export function main(argv = process.argv.slice(2)) {
  const command = argv.shift() || 'help';
  const { positional, options } = parseArgs(argv);
  validateInvocation(command === '--help' ? 'help' : command, positional, options);
  switch (command) {
    case 'doctor': doctor(); break;
    case 'list': listMacros(Boolean(options.all)); break;
    case 'hotkeys': listHotkeys(Boolean(options.all)); break;
    case 'show': showMacro(positional[0], Boolean(options.xml)); break;
    case 'run': runMacro(positional[0], options); break;
    case 'var-get': variableGet(requireValue(positional[0], '变量名')); break;
    case 'var-set': variableSet(requireValue(positional[0], '变量名'), requirePresent(positional[1], '变量值')); break;
    case 'calculate': process.stdout.write(`${osa(`on run argv
      tell application "${ENGINE}" to calculate (item 1 of argv)
    end run`, [requireValue(positional[0], '表达式')])}\n`); break;
    case 'tokens': process.stdout.write(`${osa(`on run argv
      tell application "${ENGINE}" to process tokens (item 1 of argv)
    end run`, [requireValue(positional[0], '文本')])}\n`); break;
    case 'edit': osa(`on run argv
      tell application "${EDITOR}" to editMacro (item 1 of argv)
    end run`, [requireValue(positional[0], '宏名或 UID')]); break;
    case 'enable': setEnabled(requireValue(positional[0], '宏名或 UID'), requireValue(positional[1], '状态')); break;
    case 'add-daily-shell': addDailyShell(options); break;
    case 'import': importMacro(positional[0], Boolean(options.enable)); break;
    case 'export': exportMacro(positional[0], positional[1]); break;
    case 'delete': deleteMacro(positional[0], Boolean(options.yes), options.backup); break;
    case 'help':
    case '--help': usage(); break;
  }
}

const isMain = process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isMain) {
  try {
    main();
  } catch (error) {
    console.error(`kmctl: ${error.message}`);
    process.exitCode = error.exitCode || 1;
  }
}
