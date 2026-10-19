import { test } from 'node:test';
import assert from 'node:assert/strict';
import { toGlassRegions, installGlassRegions } from '../../web/js/glass-regions.js';

const viewport = { width: 100, height: 80 };
const entry = (patch = {}) => ({ x: 1.25, y: 2.5, width: 20.5, height: 30.5, radius: 5.5, ...patch });
test('glass: preserve fractions and partially outside geometry for native clipping', () => {
  assert.deepEqual(toGlassRegions([entry(), entry({ x: -15.5, y: -10, radius: 8 })], viewport),
    [[1.25, 2.5, 20.5, 30.5, 5.5], [-15.5, -10, 20.5, 30.5, 8]]);
});
test('glass: discard invalid, zero-sized and fully outside entries; cap at 64', () => {
  const invalid = [null, {}, entry({ width: 0 }), entry({ height: -1 }), entry({ x: 100 }),
    entry({ y: 80 }), entry({ x: -20.5 }), entry({ y: -30.5 })];
  for (const key of ['x', 'y', 'width', 'height', 'radius']) {
    for (const value of [NaN, Infinity, '1', true]) invalid.push(entry({ [key]: value }));
  }
  assert.deepEqual(toGlassRegions(invalid, viewport), []);
  for (const invalidViewport of [{ width: 0, height: 80 }, { width: Infinity, height: 80 }]) {
    assert.deepEqual(toGlassRegions([entry()], invalidViewport), []);
  }
  assert.equal(toGlassRegions(Array.from({ length: 65 }, (_, x) => entry({ x })), viewport).length, 64);
});

function environment() {
  const frames = [], elements = [], events = new Map(), observed = new Set();
  let resized, mutated, collections = 0, attributes;
  const root = {
    documentElement: {}, fonts: { ready: Promise.resolve() },
    querySelectorAll(selector) { assert.equal(selector, '.card, [data-glass]'); collections++; return elements; },
    addEventListener: (name, fn) => events.set(name, fn),
  };
  const win = {
    innerWidth: 100, innerHeight: 80,
    requestAnimationFrame(fn) { frames.push(fn); },
    addEventListener: (name, fn) => events.set(name, fn),
    getComputedStyle: el => ({ visibility: el.visibility ?? 'visible', borderTopLeftRadius: el.radius ?? '5.5px' }),
    ResizeObserver: class { constructor(fn) { resized = fn; } observe(el) { observed.add(el); } unobserve(el) { observed.delete(el); } },
    MutationObserver: class { constructor(fn) { mutated = fn; } observe(_, options) { attributes = options.attributeFilter; } },
  };
  const element = (patch = {}) => ({
    nodeType: 1, matches: selector => selector === '.card, [data-glass]', querySelector: () => null,
    getBoundingClientRect: () => entry(patch),
  });
  return { root, win, frames, elements, events, observed, element,
    get collections() { return collections; }, get attributes() { return attributes; },
    resize: () => resized(), mutate: records => mutated(records), flush: () => frames.splice(0).forEach(fn => fn()),
  };
}
test('glass: one frame per burst; unchanged geometry is silent; fractional radius changes resend', async () => {
  const env = environment(), calls = [];
  const card = env.element(); env.elements.push(card);
  const reporter = installGlassRegions({ send: regions => calls.push(regions), root: env.root, win: env.win });
  await Promise.resolve();
  reporter.schedule(); env.resize(); env.events.get('resize')(); env.events.get('load')();
  assert.equal(env.frames.length, 1); env.flush();
  assert.deepEqual(calls, [[[1.25, 2.5, 20.5, 30.5, 5.5]]]);
  assert.deepEqual(env.attributes, ['class', 'style', 'hidden', 'data-glass']);
  assert.ok(env.observed.has(card) && env.observed.has(env.root.documentElement));
  env.events.get('transitionend')(); env.events.get('animationend')(); env.flush();
  assert.equal(calls.length, 1);
  card.radius = '6.25px';
  env.mutate([{ type: 'attributes', target: card, attributeName: 'style' }]); env.flush();
  assert.deepEqual(calls.at(-1), [[1.25, 2.5, 20.5, 30.5, 6.25]]);
});
test('glass: CSS-only visibility, hidden zero sizes and removed nodes clear glass', () => {
  const env = environment(), calls = [];
  const card = env.element(); env.elements.push(card);
  installGlassRegions({ send: regions => calls.push(regions), root: env.root, win: env.win });
  env.flush(); card.visibility = 'hidden'; env.events.get('transitionend')(); env.flush();
  assert.deepEqual(calls.at(-1), []); assert.ok(!env.observed.has(card));
  card.visibility = 'visible'; card.radius = 'nonsense'; env.events.get('resize')(); env.flush();
  assert.deepEqual(calls.at(-1), [[1.25, 2.5, 20.5, 30.5, 0]]);
  card.getBoundingClientRect = () => entry({ width: 0 }); env.resize(); env.flush();
  assert.deepEqual(calls.at(-1), []);
  const next = env.element({ x: 10 }); env.elements.splice(0, 1, next);
  env.mutate([{ type: 'childList', addedNodes: [next], removedNodes: [card] }]); env.flush();
  assert.deepEqual(calls.at(-1), [[10, 2.5, 20.5, 30.5, 5.5]]);
  env.elements.length = 0;
  env.mutate([{ type: 'childList', addedNodes: [], removedNodes: [next] }]); env.flush();
  assert.deepEqual(calls.at(-1), []);
});
test('glass: decorative mutations do not schedule or scan, removing glass markers does', async () => {
  const env = environment();
  const card = env.element(); env.elements.push(card);
  installGlassRegions({ send() {}, root: env.root, win: env.win });
  await Promise.resolve(); env.flush(); const collections = env.collections;
  const decorative = { nodeType: 1, matches: () => false, querySelector: () => null };
  for (let i = 0; i < 60; i++) env.mutate([{ type: 'attributes', target: decorative, attributeName: 'style' }]);
  assert.equal(env.frames.length, 0); assert.equal(env.collections, collections);
  card.matches = () => false;
  env.mutate([{ type: 'attributes', target: card, attributeName: 'data-glass' }]);
  assert.equal(env.frames.length, 1);
});
test('glass: transport failures are contained', async () => {
  for (const send of [() => { throw Error('failed'); }, () => Promise.reject(Error('failed'))]) {
    const env = environment();
    installGlassRegions({ send, root: env.root, win: env.win });
    assert.doesNotThrow(env.flush);
    await Promise.resolve();
  }
});

// Exercise the actual entry point; isolate unrelated widget mounting and OS transport.
// The region collector itself stays real, using the fake layout/observers above.
import { registerHooks } from 'node:module';
test('glass: main installs only natively, enables translucent tokens only after success', async () => {
  for (const mode of ['native-success', 'native-failure', 'mock']) {
    const env = environment(), sent = [];
    let resolve, reject;
    const reply = new Promise((yes, no) => { resolve = yes; reject = no; });
    env.root.documentElement.dataset = {};
    env.root.getElementById = () => ({});
    env.elements.push(env.element());
    const fixture = {
      store: { subscribe() {} },
      bridge: { mode: mode === 'mock' ? 'mock' : 'native', start: async () => {},
        send(action, params) { sent.push({ action, params }); return reply; } },
    };
    const oldWindow = globalThis.window, oldDocument = globalThis.document;
    globalThis.window = env.win; globalThis.document = env.root;
    globalThis.__glassMainFixture = fixture;
    const modules = {
      './store.js': 'export const store = globalThis.__glassMainFixture.store;',
      './bridge.js': 'export const createBridge = () => globalThis.__glassMainFixture.bridge;',
      './widgets.js': 'export const mountWidgets = async () => {};',
      './hit-regions.js': 'export const installHitRegions = () => ({schedule(){}});',
      './keyboard-focus.js': 'export const installKeyboardFocus = () => {};',
    };
    const entryURL = new URL(`../../web/js/main.js?glass-test=${mode}`, import.meta.url).href;
    const hook = registerHooks({
      resolve(specifier, context, next) {
        if (context.parentURL === entryURL && Object.hasOwn(modules, specifier)) {
          return { url: `glass-test:${mode}/${specifier}`, shortCircuit: true };
        }
        return next(specifier, context);
      },
      load(url, context, next) {
        if (url.startsWith(`glass-test:${mode}/`)) {
          return { format: 'module', source: modules[url.slice(`glass-test:${mode}/`.length)], shortCircuit: true };
        }
        return next(url, context);
      },
    });
    try {
      await import(entryURL); env.flush();
      assert.equal(env.root.documentElement.dataset.glass, undefined);
      if (mode === 'mock') { assert.deepEqual(sent, []); assert.equal(env.collections, 0); }
      else {
        assert.deepEqual(sent, [{ action: 'setGlassRegions', params: { regions: [[1.25, 2.5, 20.5, 30.5, 5.5]] } }]);
        if (mode === 'native-success') resolve(null); else reject(Error('failed'));
        await new Promise(yes => setImmediate(yes));
        assert.equal(env.root.documentElement.dataset.glass, mode === 'native-success' ? 'on' : undefined);
      }
    } finally {
      hook.deregister(); globalThis.window = oldWindow; globalThis.document = oldDocument;
      delete globalThis.__glassMainFixture;
    }
  }
});

test('glass: the html data-glass=on capability flag is not a fullscreen glass region', () => {
  const env = environment(), calls = [];
  env.root.documentElement = env.element({ x: 0, y: 0, width: 100, height: 80 });
  env.root.documentElement.dataset = { glass: 'on' };
  env.elements.push(env.root.documentElement, env.element());
  installGlassRegions({ send: regions => calls.push(regions), root: env.root, win: env.win });
  env.flush();
  assert.deepEqual(calls, [[[1.25, 2.5, 20.5, 30.5, 5.5]]]);
});
