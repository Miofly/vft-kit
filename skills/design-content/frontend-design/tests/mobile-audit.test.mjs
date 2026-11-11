import assert from 'node:assert/strict';
import test from 'node:test';
import vm from 'node:vm';
import { collectMobileAudit } from '../scripts/mobile-audit.mjs';

function run({ viewport = 'width=device-width, initial-scale=1', width = 390, scrollWidth = width, controls = [] } = {}) {
  const context = {
    document: {
      documentElement: { clientWidth: width, clientHeight: 844, scrollWidth },
      scrollingElement: { scrollWidth },
      querySelector: () => viewport ? { content: viewport } : null,
      querySelectorAll: () => controls,
    },
    getComputedStyle: (element) => ({ display: 'block', visibility: 'visible', opacity: '1', fontSize: '16px', ...element.style }),
  };
  return JSON.parse(JSON.stringify(vm.runInNewContext(`(${collectMobileAudit.toString()})()`, context)));
}

function control({ width = 44, height = 44, tag = 'BUTTON', type, excluded = false, top = 0, style = {} } = {}) {
  return {
    tagName: tag, style,
    matches: () => excluded,
    closest: () => null,
    getAttribute: () => type ?? null,
    getBoundingClientRect: () => ({ width, height, top, bottom: top + height, left: 0, right: width }),
  };
}

test('collector serializes without imports and keeps 1px rounding tolerance', () => {
  assert.equal(run({ controls: [control()] }).status, 'clear');
  assert.equal(run({ scrollWidth: 391 }).pageOverflow, false);
  assert.equal(run({ scrollWidth: 392 }).pageOverflow, true);
});

test('zoom restrictions and missing viewport require review', () => {
  for (const viewport of ['', 'width=device-width, USER-SCALABLE = no', 'maximum-scale=1', 'user-scalable=0', 'maximum-scale=1.5']) {
    assert.equal(run({ viewport }).status, 'review', viewport);
  }
  for (const viewport of ['maximum-scale=2', 'user-scalable=yes', 'maximum-scale=invalid']) {
    assert.equal(run({ viewport }).viewport.zoomRestricted, false, viewport);
  }
});

test('44px design goal and 24px threshold remain separate candidates', () => {
  const result = run({ controls: [control({ width: 43 }), control({ width: 24 }), control({ width: 23 }), control()] });
  assert.equal(result.smallTargets.count, 3);
  assert.deepEqual(result.smallTargets.candidates.map((item) => item.below24), [false, false, true]);
});

test('disabled, hidden and offscreen controls do not inflate candidates', () => {
  const result = run({ controls: [
    control({ width: 20, excluded: true }),
    control({ width: 20, style: { visibility: 'hidden' } }),
    control({ width: 20, style: { opacity: '0' } }),
    control({ width: 20, top: 900 }),
    control({ width: 0 }),
  ] });
  assert.equal(result.smallTargets.count, 0);
});

test('input sizing excludes non-text controls and report is bounded without values', () => {
  const controls = [control({ tag: 'INPUT', style: { fontSize: '15px' } }), control({ tag: 'INPUT', type: 'checkbox', style: { fontSize: '12px' } })];
  const result = run({ controls: [...controls, ...Array.from({ length: 120 }, () => control({ width: 20 }))] });
  assert.equal(result.smallInputs.count, 1);
  assert.equal(result.smallTargets.count, 120);
  assert.equal(result.smallTargets.candidates.length, 100);
  assert.doesNotMatch(JSON.stringify(result), /value|cookie|https?:|password/i);
});
