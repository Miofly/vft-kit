import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { buildDailyShellMacro, buildMacroImportPayload, formatMacroDetails, summarizeMacros } from '../scripts/kmctl.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const cli = path.resolve(here, '../scripts/kmctl.mjs');
const uid = '01234567-89AB-4CDE-8FAB-0123456789AB';
const wakeUID = 'A23BD8E9-3FCE-43A2-8C82-7C06FA8373BD';
const command = '/bin/echo "<&> 中文"\nprintf "second line"';

const macro = buildDailyShellMacro({
  name: 'Daily fixture',
  command,
  time: '09:07',
  days: '127',
  uid,
});

assert.equal(macro.UID, uid);
assert.equal(macro.Name, 'Daily fixture');
assert.equal(macro.Actions.length, 1);
assert.equal(macro.Actions[0].MacroActionType, 'ExecuteShellScript');
assert.equal(macro.Actions[0].Text, command);
assert.deepEqual(macro.Triggers[0], {
  ExecuteType: 'Time',
  MacroTriggerType: 'Time',
  TimeHour: 9,
  TimeMinutes: 7,
  WhichDays: 127,
});

const chainedMacro = buildDailyShellMacro({
  name: 'Chained fixture',
  command,
  beforeMacroUID: wakeUID,
});
assert.equal(chainedMacro.Actions.length, 2);
assert.deepEqual(
  {
    Asynchronously: chainedMacro.Actions[0].Asynchronously,
    MacroActionType: chainedMacro.Actions[0].MacroActionType,
    MacroUID: chainedMacro.Actions[0].MacroUID,
    TimeOutAbortsMacro: chainedMacro.Actions[0].TimeOutAbortsMacro,
    UseParameter: chainedMacro.Actions[0].UseParameter,
  },
  {
    Asynchronously: false,
    MacroActionType: 'ExecuteMacro',
    MacroUID: wakeUID,
    TimeOutAbortsMacro: true,
    UseParameter: false,
  },
);
assert.equal(chainedMacro.Actions[1].MacroActionType, 'ExecuteShellScript');
const group = {
  Activate: 'Normal',
  CreationDate: 1,
  Name: 'Fixture Group',
  ToggleMacroUID: 'A4C3EC8C-3150-4D31-8E33-0BD218434A77',
  UID: 'E4D49D25-99FD-4A59-A513-4240E8DE222D',
};
assert.deepEqual(buildMacroImportPayload(group, macro), [{ ...group, Macros: [macro] }]);
assert.equal(group.Macros, undefined);
assert.deepEqual(
  summarizeMacros([{ enabled: true, name: 'Group', uid: 'G', macros: [{ active: true, enabled: false, name: 'Macro', uid: 'M', triggers: [{ type: 'Time' }] }] }]),
  [{ enabled: true, name: 'Group', uid: 'G', macros: [{ active: true, enabled: false, name: 'Macro', uid: 'M', triggers: [{ type: 'Time' }] }] }],
);
assert.deepEqual(
  formatMacroDetails({ Name: 'Macro', UID: 'M', Triggers: [] }, { enabled: false, group: 'Group' }),
  { enabled: false, group: 'Group', name: 'Macro', uid: 'M', definition: { Name: 'Macro', UID: 'M', Triggers: [] } },
);

const dryRun = spawnSync(process.execPath, [
  cli,
  'add-daily-shell',
  '--name', 'CLI fixture',
  '--command', command,
  '--time', '23:59',
  '--dry-run',
], { encoding: 'utf8' });
assert.equal(dryRun.status, 0, dryRun.stderr);
const result = JSON.parse(dryRun.stdout);
assert.equal(result.enabled, false);
assert.equal(result.group, 'Global Macro Group');
assert.equal(result.macro.Actions[0].Text, command);
assert.equal(result.macro.Triggers[0].TimeHour, 23);
assert.equal(result.macro.Triggers[0].TimeMinutes, 59);

const chainedDryRun = spawnSync(process.execPath, [
  cli,
  'add-daily-shell',
  '--name', 'Chained CLI fixture',
  '--command', command,
  '--before-macro-uid', wakeUID,
  '--dry-run',
], { encoding: 'utf8' });
assert.equal(chainedDryRun.status, 0, chainedDryRun.stderr);
assert.equal(JSON.parse(chainedDryRun.stdout).macro.Actions[0].MacroUID, wakeUID);

for (const invalid of ['9:00', '24:00', '09:60']) {
  const failed = spawnSync(process.execPath, [
    cli,
    'add-daily-shell', '--name', 'bad', '--command', '/bin/true', '--time', invalid, '--dry-run',
  ], { encoding: 'utf8' });
  assert.equal(failed.status, 2, `${invalid}: ${failed.stderr}`);
}

const unsafeDelete = spawnSync(process.execPath, [cli, 'delete', 'not-a-uid', '--yes'], { encoding: 'utf8' });
assert.equal(unsafeDelete.status, 2);
assert.match(unsafeDelete.stderr, /只接受 Keyboard Maestro 宏 UID/);

const validUnusedUID = '7130E5D4-8CC3-42E2-9ADC-A9F00A7A87AC';
for (const args of [
  ['run', 'never-run', '--dry-run'],
  ['import', '/tmp/missing.kmmacros', '--dry-run'],
  ['import', '/tmp/missing.kmmacros', '--enable', 'false'],
  ['delete', validUnusedUID, '--yes', '--dry-run'],
  ['add-daily-shell', '--name', 'bad', '--command', '/usr/bin/true', '--dry-run=false'],
  ['doctor', '--unknown', 'value'],
]) {
  const rejected = spawnSync(process.execPath, [cli, ...args], { encoding: 'utf8' });
  assert.equal(rejected.status, 2, `${args.join(' ')}: ${rejected.stderr}`);
}

console.log('test-kmctl: ok');
