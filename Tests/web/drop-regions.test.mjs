import { test } from 'node:test';
import assert from 'node:assert/strict';
import { installDropRegions } from '../../web/js/drop-regions.js';

function environment() {
  const frames = [], events = new Map(), nodes = [], observed = new Set();
  let resized, mutated, mutationOptions;
  const doc = {
    documentElement: {}, fonts: { ready: Promise.resolve() },
    querySelectorAll(selector) { return nodes.filter(node => node.matches(selector)); },
    addEventListener(name, fn) { events.set(name, fn); },
  };
  const win = {
    innerWidth: 100, innerHeight: 80,
    getComputedStyle: node => ({ visibility: node.visibility ?? 'visible' }),
    requestAnimationFrame(fn) { frames.push(fn); },
    addEventListener(name, fn) { events.set(name, fn); },
    ResizeObserver: class { constructor(fn) { resized = fn; } observe(node) { observed.add(node); } unobserve(node) { observed.delete(node); } },
    MutationObserver: class { constructor(fn) { mutated = fn; } observe(_, options) { mutationOptions = options; } },
  };
  const element = (x, attrs = { 'data-drop': 'projects' }) => ({
    nodeType: 1, attrs, x,
    matches(selector) { return selector === '[data-drop]' ? Object.hasOwn(this.attrs, 'data-drop') : Boolean(this.attrs.class === 'card' || Object.hasOwn(this.attrs, 'data-hit')); },
    querySelector() { return null; },
    getAttribute(name) { return this.attrs[name] ?? null; },
    getBoundingClientRect() { return { x: this.x, y: 2, width: 12, height: 8 }; },
  });
  return { root: doc, win, frames, nodes, events, observed, element,
    resize: () => resized(), mutate: records => mutated(records), flush: () => frames.splice(0).forEach(fn => fn()),
    get mutationOptions() { return mutationOptions; } };
}

test('drop regions: only data-drop elements are reported, clipped, and deduplicated with a limit of eight', t => {
  const warn = t.mock.method(console, 'warn', () => {});
  const f = environment(), calls = [];
  f.nodes.push(f.element(1, { class: 'card' }), f.element(2, { 'data-hit': 'yes' }),
    f.element(-2), f.element(-2), { ...f.element(3), visibility: 'hidden' });
  const drop = installDropRegions({ ...f, send: regions => calls.push(regions) });
  f.flush(); assert.deepEqual(calls, [[[0, 2, 10, 8]]]);
  assert.ok(Object.isFrozen(drop.last) && Object.isFrozen(drop.last[0]));
  f.nodes.splice(0, f.nodes.length, ...Array.from({length: 9}, (_, i) => f.element(i * 10)));
  drop.schedule(); f.flush();
  assert.equal(drop.last.length, 8); assert.deepEqual(drop.last.at(-1), [70, 2, 12, 8]);
  assert.equal(warn.mock.callCount(), 1);
});

test('drop regions: coalesces geometry changes and suppresses unchanged sends, with no decorative invalidations', async () => {
  const f = environment(), calls = [], node = f.element(10); f.nodes.push(node);
  const drop = installDropRegions({ ...f, send: regions => calls.push(regions) });
  await Promise.resolve(); f.resize(); drop.schedule(); assert.equal(f.frames.length, 1);
  f.flush(); assert.deepEqual(drop.last, [[10, 2, 12, 8]]);
  f.events.get('resize')(); f.events.get('load')(); f.flush(); assert.equal(calls.length, 1);
  for (let i = 0; i < 20; i++) f.mutate([{ type: 'attributes', attributeName: 'style', target: f.element(1, {}) }]);
  assert.equal(f.frames.length, 0);
  node.x = 25; f.resize(); f.flush(); assert.deepEqual(drop.last, [[25, 2, 12, 8]]);
  node.visibility = 'hidden'; f.events.get('transitionend')(); f.flush(); assert.deepEqual(drop.last, []);
  node.visibility = 'visible'; f.events.get('animationend')(); f.flush(); assert.deepEqual(drop.last, [[25, 2, 12, 8]]);
});

test('drop regions: attribute addition/removal and DOM replacement refresh observation and send empty regions', () => {
  const f = environment(), node = f.element(10), calls = []; f.nodes.push(node);
  installDropRegions({ ...f, send: regions => calls.push(regions) }); f.flush();
  assert.ok(f.observed.has(node)); assert.ok(f.mutationOptions.attributeFilter.includes('data-drop'));
  delete node.attrs['data-drop'];
  f.mutate([{ type: 'attributes', attributeName: 'data-drop', target: node }]); f.flush();
  assert.deepEqual(calls.at(-1), []); assert.ok(!f.observed.has(node));
  node.attrs['data-drop'] = 'projects';
  f.mutate([{ type: 'attributes', attributeName: 'data-drop', target: node }]); f.flush();
  assert.deepEqual(calls.at(-1), [[10, 2, 12, 8]]);
  const replacement = f.element(30); f.nodes.splice(0, 1, replacement);
  f.mutate([{ type: 'childList', addedNodes: [replacement], removedNodes: [node] }]); f.flush();
  assert.deepEqual(calls.at(-1), [[30, 2, 12, 8]]);
  assert.ok(f.observed.has(replacement) && !f.observed.has(node));
  f.nodes.length = 0;
  f.mutate([{ type: 'childList', addedNodes: [], removedNodes: [replacement] }]); f.flush();
  assert.deepEqual(calls.at(-1), []);
});

test('drop regions: failed transport does not throw or produce an unhandled rejection', async () => {
  for (const send of [() => { throw Error('failed'); }, () => Promise.reject(Error('failed'))]) {
    const f = environment(); installDropRegions({ ...f, send }); assert.doesNotThrow(f.flush); await Promise.resolve();
  }
});

// Verify the real entry point wires drop reports in both runtime modes and
// schedules them after safe-area changes; unrelated collectors stay isolated.
import { registerHooks } from 'node:module';
test('drop regions: main sends setDropRegions in native and mock modes and refreshes after safe-area changes', async () => {
  for (const mode of ['native', 'mock']) {
    const f = environment(), sent = [], subscriptions = new Map();
    const node = f.element(10); f.nodes.push(node);
    f.root.documentElement.style = { setProperty() {} };
    f.root.getElementById = () => ({});
    const fixture = {
      store: { subscribe(key, fn) { subscriptions.set(key, fn); } },
      bridge: { mode, start: async () => {}, send: async (action, params) => { sent.push({ action, params }); } },
    };
    const modules = {
      './store.js': 'export const store = globalThis.__dropMainFixture.store;',
      './bridge.js': 'export const createBridge = () => globalThis.__dropMainFixture.bridge;',
      './widgets.js': 'export const mountWidgets = async () => {};',
      './hit-regions.js': 'export const installHitRegions = () => ({schedule(){}});',
      './glass-regions.js': 'export const installGlassRegions = () => {};',
      './keyboard-focus.js': 'export const installKeyboardFocus = () => {};',
    };
    const entryURL = new URL(`../../web/js/main.js?drop-test=${mode}`, import.meta.url).href;
    const oldWindow = globalThis.window, oldDocument = globalThis.document;
    globalThis.window = f.win; globalThis.document = f.root; globalThis.__dropMainFixture = fixture;
    const hook = registerHooks({
      resolve(specifier, context, next) {
        if (context.parentURL === entryURL && Object.hasOwn(modules, specifier)) return {url: `drop-test:${mode}/${specifier}`, shortCircuit: true};
        return next(specifier, context);
      },
      load(url, context, next) {
        if (url.startsWith(`drop-test:${mode}/`)) return { format: 'module', source: modules[url.slice(`drop-test:${mode}/`.length)], shortCircuit: true };
        return next(url, context);
      },
    });
    try {
      await import(entryURL); f.flush();
      assert.deepEqual(sent, [{action: 'setDropRegions', params: {regions: [[10, 2, 12, 8]]}}]);
      node.x = 20; subscriptions.get('safeArea')({top: 30, right: 0, bottom: 0, left: 0}); f.flush();
      assert.deepEqual(sent.at(-1), {action: 'setDropRegions', params: {regions: [[20, 2, 12, 8]]}});
      assert.equal(sent.length, 2);
    } finally {
      hook.deregister(); globalThis.window = oldWindow; globalThis.document = oldDocument; delete globalThis.__dropMainFixture;
    }
  }
});
