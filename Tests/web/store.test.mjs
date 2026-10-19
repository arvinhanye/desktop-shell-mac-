import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createStore, initialState, store } from '../../web/js/store.js';

test('store: singleton has the initial keys; getState is a shallow copy', () => {
  assert.deepEqual(Object.keys(store.getState()), ['ready', 'config', 'media', 'ui', 'todos', 'todosAccess', 'safeArea', 'paused', 'systemStats', 'audioSpectrum', 'phase', 'selectedProject', 'now', 'appearanceOpen', 'voiceRequest', 'voicePlaying']);
  assert.equal(store.get('ready'), false);
  assert.equal(store.get('todosAccess'), 'unknown');
  const snapshot = store.getState();
  snapshot.ready = true;
  assert.equal(store.get('ready'), false);
  assert.equal(snapshot.ui, store.get('ui'));
  assert.deepEqual(store.getState(), initialState);
});

test('store: unknown keys and non-object patches warn without blocking known keys', t => {
  const warn = t.mock.method(console, 'warn', () => {});
  const s = createStore({ a: 0 });
  s.set({ unknown: 1, a: 2 });
  for (const patch of [null, [], 'x', 3, new Date()]) s.set(patch);
  const unsubscribe = s.subscribe('toString', () => assert.fail());
  unsubscribe();
  s.set(JSON.parse('{"__proto__":{"polluted":true}}'));
  assert.deepEqual(s.getState(), { a: 2 });
  assert.equal(warn.mock.callCount(), 8);
});

test('store: Object.is suppresses identical values including NaN, but distinguishes signed zero', () => {
  const s = createStore({ a: NaN, b: 0 });
  const calls = [];
  s.subscribe('a', (...args) => calls.push(args));
  s.subscribe('b', (...args) => calls.push(args));
  s.set({ a: NaN, b: 0 });
  assert.deepEqual(calls, []);
  s.set({ b: -0 });
  assert.deepEqual(calls, [[-0, 0]]);
});

test('store: patch is fully applied before ordered key/listener notifications', () => {
  const s = createStore({ a: 0, b: 0 });
  const calls = [];
  s.subscribe('a', (value, previous) => calls.push(['a1', value, previous, s.get('b')]));
  s.subscribe('a', () => calls.push(['a2']));
  s.subscribe('b', () => calls.push(['b', s.get('a')]));
  s.set({ b: 2, a: 1 });
  assert.deepEqual(calls, [['b', 1], ['a1', 1, 0, 2], ['a2']]);
});

test('store: throwing listeners are logged, remaining listeners and set continue', t => {
  const error = t.mock.method(console, 'error', () => {});
  const s = createStore({ a: 0 });
  let seen;
  const failure = new Error('listener');
  s.subscribe('a', () => { throw failure; });
  s.subscribe('a', value => { seen = value; });
  assert.doesNotThrow(() => s.set({ a: 1 }));
  assert.equal(seen, 1);
  assert.equal(error.mock.callCount(), 1);
  assert.deepEqual(error.mock.calls[0].arguments, ['store: listener failed', failure]);
});

test('store: nested set applies and notifies synchronously, preserving outer notification values', () => {
  const s = createStore({ a: 0, b: 0 });
  const calls = [];
  s.subscribe('a', value => { calls.push(['a', value]); if (value === 1) s.set({ b: 3 }); });
  s.subscribe('b', (value, previous) => calls.push(['b', value, previous, s.get('b')]));
  s.set({ a: 1, b: 2 });
  assert.deepEqual(calls, [['a', 1], ['b', 3, 2, 3], ['b', 2, 0, 3]]);
});

test('store: unsubscribe and new subscriptions during notification affect only the next round', () => {
  const s = createStore({ a: 0, b: 0 });
  const calls = [];
  let added = false;
  s.subscribe('a', () => {
    calls.push('a');
    off();
    if (!added) { added = true; s.subscribe('b', () => calls.push('new')); }
  });
  const off = s.subscribe('b', () => calls.push('old'));
  s.set({ a: 1, b: 1 });
  assert.deepEqual(calls, ['a', 'old']);
  calls.length = 0;
  s.set({ a: 2, b: 2 });
  assert.deepEqual(calls, ['a', 'new']);
  off();
});

test('store: immediate receives current value/undefined and isolates errors', t => {
  t.mock.method(console, 'error', () => {});
  const s = createStore({ a: 4 });
  const calls = [];
  const off = s.subscribe('a', (...args) => calls.push(args), { immediate: true });
  assert.deepEqual(calls, [[4, undefined]]);
  assert.doesNotThrow(() => s.subscribe('a', () => { throw Error(); }, { immediate: true }));
  off();
  s.set({ a: 5 });
  assert.deepEqual(calls, [[4, undefined]]);
});

test('store: initial and written objects/arrays are shallow frozen; replacement is supported', () => {
  const s = createStore({ obj: { nested: {} }, array: [] });
  assert.ok(Object.isFrozen(s.get('obj')));
  assert.ok(Object.isFrozen(s.get('array')));
  assert.ok(!Object.isFrozen(s.get('obj').nested));
  const obj = { a: 1 };
  const array = [1];
  s.set({ obj, array });
  assert.ok(Object.isFrozen(obj) && Object.isFrozen(array));
  assert.throws(() => { obj.a = 2; }, TypeError);
  s.set({ obj: { a: 2 }, array: [2] });
  assert.deepEqual(s.get('obj'), { a: 2 });
});

test('store: M4 shared keys start empty/idle and publish component updates', () => {
  const s = createStore(initialState);
  const defaults = { now: null, appearanceOpen: false, voiceRequest: 0, voicePlaying: false };
  const values = { now: 123000, appearanceOpen: true, voiceRequest: 1, voicePlaying: true };
  const calls = [];
  const cleanups = Object.keys(defaults).map(key => {
    assert.equal(s.get(key), defaults[key]);
    return s.subscribe(key, (value, previous) => calls.push([key, value, previous]));
  });
  s.set(values);
  assert.deepEqual(calls, [
    ['now', 123000, null], ['appearanceOpen', true, false],
    ['voiceRequest', 1, 0], ['voicePlaying', true, false],
  ]);
  cleanups.forEach(off => off());
  s.set(defaults);
  assert.equal(calls.length, 4);
});
