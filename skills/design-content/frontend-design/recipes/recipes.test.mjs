// Node-only lifecycle test; no browser, server, dependencies or network.
import assert from 'node:assert/strict';
import { mountExampleStack, mountOpeningScene } from './recipes.mjs';
class Target extends EventTarget {
  constructor() { super(); this.attrs = new Map(); this.style = {}; this.dataset = {}; this.disabled = false; }
  setAttribute(k, v) { this.attrs.set(k, v); }
  getAttribute(k) { return this.attrs.get(k) ?? null; }
  removeAttribute(k) { this.attrs.delete(k); if (k === 'style') this.style = {}; }
  classList = { add() {}, remove() {} };
}
const reduced = Object.assign(new Target(), { matches: false });
globalThis.matchMedia = () => reduced;
globalThis.document = Object.assign(new Target(), { hidden: false });
const button = new Target(), status = Object.assign(new Target(), { textContent: 'original' });
let pending = [], cancelled = 0;
const cards = Array.from({ length: 4 }, (_, i) => {
  const card = new Target();
  card.querySelector = () => ({ textContent: `Card ${i}` });
  card.animate = () => {
    let resolve, reject;
    const finished = new Promise((a, b) => { resolve = a; reject = b; });
    const animation = { finished, cancel() { cancelled++; reject(Object.assign(new Error('cancelled'), { name: 'AbortError' })); } };
    pending.push(resolve);
    return animation;
  };
  return card;
});
const root = new Target();
root.querySelector = (sel) => sel === '[data-next]' ? button : status;
root.querySelectorAll = () => cards;
const tick = () => new Promise((resolve) => setImmediate(resolve));
const cleanup = mountExampleStack(root);
assert.equal(cards[0].getAttribute('aria-hidden'), 'false');
button.dispatchEvent(new Event('click'));
button.dispatchEvent(new Event('click'));
assert.equal(pending.length, 4, 'rapid second click must not start another transition');
assert.equal(button.getAttribute('aria-disabled'), 'true');
pending.splice(0).forEach((resolve) => resolve());
await tick();
assert.equal(button.getAttribute('aria-disabled'), null);
assert.equal(cards[1].getAttribute('aria-hidden'), 'false');
assert.equal(cards.filter((card) => card.getAttribute('aria-hidden') === 'false').length, 1);
button.dispatchEvent(new Event('click'));
reduced.matches = true;
reduced.dispatchEvent(new Event('change'));
await tick();
assert.equal(cards[2].getAttribute('aria-hidden'), 'false');
assert.equal(button.getAttribute('aria-disabled'), null);
assert.ok(cancelled >= 8);
pending = [];
button.dispatchEvent(new Event('click'));
await tick();
assert.equal(pending.length, 0, 'reduced motion must not create animations');
assert.equal(cards[3].getAttribute('aria-hidden'), 'false');
cleanup();
assert.equal(status.textContent, 'original');
assert.ok(cards.every((card) => card.getAttribute('aria-hidden') === null));
button.dispatchEvent(new Event('click'));
assert.equal(status.textContent, 'original', 'cleanup must remove handlers');
const remount = mountExampleStack(root);
reduced.matches = false;
button.dispatchEvent(new Event('click'));
remount();
await tick();
assert.equal(status.textContent, 'original', 'settled promises must not mutate an unmounted root');
assert.equal(button.getAttribute('aria-disabled'), null);
assert.throws(() => mountExampleStack({ querySelector: () => null, querySelectorAll: () => [] }), /needs/);
const scene = new Target();
scene.querySelector = () => ({});
scene.style.removeProperty = () => {};
let reverted = 0;
const mounted = { revert() { reverted++; } };
globalThis.Stage = { live: true, scenes: [mounted], scene(_root, opts) { assert.equal(opts.phone, 'rest'); assert.equal(opts.hold, 1); return mounted; } };
mountOpeningScene(scene)();
assert.equal(reverted, 1);
assert.equal(Stage.scenes.length, 0);
delete globalThis.Stage;
mountOpeningScene(scene)();
console.log('PASS: stack initial/final state, rapid clicks, reduced-motion change, cleanup/remount, scene revert/fallback');
