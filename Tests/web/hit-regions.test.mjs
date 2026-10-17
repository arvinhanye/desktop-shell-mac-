import { test } from 'node:test';
import assert from 'node:assert/strict';
import { toRegions, installHitRegions } from '../../web/js/hit-regions.js';

const viewport = { width: 100, height: 80 };
test('hit regions: round outwards then clip on all four viewport edges', () => {
  assert.deepEqual(toRegions([
    { x: 1.2, y: 2.8, width: 3.1, height: 4.3 },
    { x: -2.5, y: -3.5, width: 5, height: 6 },
    { x: 98.5, y: 78.5, width: 4, height: 4 },
  ], viewport), [[1, 2, 4, 6], [0, 0, 3, 3], [98, 78, 2, 2]]);
});
test('hit regions: discard nonfinite, nonpositive and fully outside rectangles', () => {
  const valid = { x: 1, y: 2, width: 3, height: 4 };
  const invalid = [null, {}, { ...valid, width: 0 }, { ...valid, height: -1 },
    { ...valid, x: 100 }, { ...valid, y: 80 }, { ...valid, x: -3 }, { ...valid, y: -4 }];
  for (const key of ['x', 'y', 'width', 'height']) {
    for (const value of [NaN, Infinity, -Infinity, '1', undefined]) invalid.push({ ...valid, [key]: value });
  }
  assert.deepEqual(toRegions([...invalid, valid], viewport), [[1, 2, 3, 4]]);
  assert.deepEqual(toRegions([valid], { width: 0, height: 80 }), []);
});
test('hit regions: deduplicate rounded/clipped results in input order', () => {
  assert.deepEqual(toRegions([
    { x: 1.1, y: 2.1, width: 2, height: 3 },
    { x: 1.2, y: 2.2, width: 2, height: 3 },
    { x: 5, y: 6, width: 1, height: 1 },
  ], viewport), [[1, 2, 3, 4], [5, 6, 1, 1]]);
});
test('hit regions: keep first 64 unique rectangles and warn only on overflow', t => {
  const warn = t.mock.method(console, 'warn', () => {});
  const rects = Array.from({ length: 65 }, (_, x) => ({ x, y: 0, width: 1, height: 1 }));
  assert.equal(toRegions(rects.slice(0, 64), viewport).length, 64);
  assert.equal(warn.mock.callCount(), 0);
  const result = toRegions(rects, viewport);
  assert.equal(result.length, 64);
  assert.deepEqual(result.at(-1), [63, 0, 1, 1]);
  assert.equal(warn.mock.callCount(), 1);
});

function environment() {
  const frames = [];
  const events = new Map();
  const elements = [];
  let resized, mutated;
  const observed = new Set();
  const root = {
    documentElement: {}, fonts: { ready: Promise.resolve() },
    querySelectorAll: () => elements,
    addEventListener: (name, fn) => events.set(name, fn),
  };
  const win = {
    innerWidth: 100, innerHeight: 80,
    requestAnimationFrame(fn) { frames.push(fn); return frames.length; },
    addEventListener: (name, fn) => events.set(name, fn),
    getComputedStyle: element => ({ visibility: element.visibility ?? 'visible' }),
    ResizeObserver: class { constructor(fn) { resized = fn; } observe(el) { observed.add(el); } unobserve(el) { observed.delete(el); } disconnect() { observed.clear(); } },
    MutationObserver: class { constructor(fn) { mutated = fn; } observe() {} },
  };
  const element = (x, attributes = {}) => ({
    getAttribute: name => attributes[name] ?? null,
    getBoundingClientRect: () => ({ x, y: 2, width: 3, height: 4 }),
  });
  return { root, win, elements, events, frames, observed, element,
    resize: () => resized(), mutate: () => mutated([]), flush: () => frames.splice(0).forEach(fn => fn()) };
}

test('hit regions: observers coalesce per frame, recollect elements and suppress unchanged sends', async () => {
  const env = environment();
  const visible = env.element(1);
  const excluded = env.element(10, { 'data-hit': 'none' });
  const hidden = { ...env.element(20), visibility: 'hidden' };
  env.elements.push(visible, excluded, hidden);
  const calls = [];
  const hit = installHitRegions({ send: regions => calls.push(regions), root: env.root, win: env.win });
  await Promise.resolve();
  hit.schedule(); env.resize(); env.events.get('resize')();
  assert.equal(env.frames.length, 1);
  env.flush();
  assert.deepEqual(calls, [[[1, 2, 3, 4]]]);
  assert.deepEqual(hit.last, [[1, 2, 3, 4]]);
  assert.throws(() => { hit.last = []; }, TypeError);
  assert.ok(env.observed.has(env.root.documentElement));
  for (const name of ['transitionend', 'animationend', 'load']) env.events.get(name)();
  env.flush();
  assert.equal(calls.length, 1);
  env.elements.splice(0, 1, env.element(30));
  env.mutate(); env.flush();
  assert.deepEqual(hit.last, [[30, 2, 3, 4]]);
  assert.ok(!env.observed.has(visible));
});
test('hit regions: synchronous and asynchronous send failures do not escape or reject globally', async () => {
  for (const send of [() => { throw Error('failed'); }, () => Promise.reject(Error('failed'))]) {
    const env = environment();
    installHitRegions({ send, root: env.root, win: env.win });
    assert.doesNotThrow(env.flush);
    await Promise.resolve();
  }
});

test('hit regions: CSS-only visibility changes are rechecked on transitions, resize and schedule', () => {
  const env = environment();
  const card = env.element(10);
  env.elements.push(card);
  const calls = [];
  const hit = installHitRegions({ send: regions => calls.push(regions), root: env.root, win: env.win });
  env.flush();
  card.visibility = 'hidden';
  env.events.get('transitionend')(); env.flush();
  assert.deepEqual(hit.last, []);
  assert.ok(!env.observed.has(card));
  card.visibility = 'visible';
  env.events.get('resize')(); env.flush();
  assert.deepEqual(hit.last, [[10, 2, 3, 4]]);
  assert.ok(env.observed.has(card));
  card.visibility = 'hidden'; hit.schedule(); env.flush();
  assert.deepEqual(calls, [[[10, 2, 3, 4]], [], [[10, 2, 3, 4]], []]);
});
