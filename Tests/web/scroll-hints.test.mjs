import { test } from 'node:test';
import assert from 'node:assert/strict';
import { scrollHintState, installScrollHints } from '../../web/js/scroll-hints.js';

for (const [name, scrollTop, clientHeight, scrollHeight, above, below] of [
  ['empty', 0, 0, 0, false, false],
  ['content fits', 0, 100, 60, false, false],
  ['exact fit', 0, 100, 100, false, false],
  ['one pixel overflow', 1, 100, 101, false, false],
  ['top', 0, 100, 300, false, true],
  ['top tolerance', 1, 100, 300, false, true],
  ['past top tolerance', 1.01, 100, 300, true, true],
  ['middle', 100, 100, 300, true, true],
  ['before bottom tolerance', 198.99, 100, 300, true, true],
  ['bottom tolerance', 199, 100, 300, true, false],
  ['bottom', 200, 100, 300, true, false],
  ['top overscroll', -10, 100, 300, false, true],
  ['bottom overscroll', 220, 100, 300, true, false],
]) {
  test(`scroll hints: ${name}`, () => {
    assert.deepEqual(scrollHintState({ scrollTop, clientHeight, scrollHeight }), { above, below });
  });
}

function fixture() {
  const classes = new Set(['scroll-list', 'unrelated']);
  const listeners = new Map();
  const resizeObservers = [];
  const mutationObservers = [];
  const observer = instances => class {
    constructor(callback) { this.callback = callback; this.disconnected = false; instances.push(this); }
    observe(target, options) { this.target = target; this.options = options; }
    disconnect() { this.disconnected = true; }
  };
  const list = {
    scrollTop: 0, clientHeight: 100, scrollHeight: 300,
    classList: { toggle(name, force) { if (force) classes.add(name); else classes.delete(name); } },
    addEventListener(type, callback, options) { listeners.set(type, { callback, options }); },
    removeEventListener(type, callback) {
      if (listeners.get(type)?.callback === callback) listeners.delete(type);
    },
  };
  const win = { ResizeObserver: observer(resizeObservers), MutationObserver: observer(mutationObservers) };
  const hints = () => ({ above: classes.has('more-above'), below: classes.has('more-below') });
  return { list, win, classes, listeners, resizeObservers, mutationObservers, hints };
}

test('scroll hints: initial and passive scroll updates preserve unrelated classes', () => {
  const f = fixture();
  const cleanup = installScrollHints(f.list, { win: f.win });
  assert.equal(typeof cleanup, 'function');
  assert.deepEqual(f.hints(), { above: false, below: true });
  assert.equal(f.listeners.get('scroll').options.passive, true);
  f.list.scrollTop = 100;
  f.listeners.get('scroll').callback();
  assert.deepEqual(f.hints(), { above: true, below: true });
  f.list.scrollTop = 200;
  f.listeners.get('scroll').callback();
  assert.deepEqual(f.hints(), { above: true, below: false });
  f.list.scrollTop = 0;
  f.listeners.get('scroll').callback();
  assert.deepEqual(f.hints(), { above: false, below: true });
  assert.ok(f.classes.has('scroll-list') && f.classes.has('unrelated'));
  cleanup();
});

test('scroll hints: resize and child mutations recompute from current layout without polling', () => {
  const f = fixture();
  const cleanup = installScrollHints(f.list, { win: f.win });
  assert.equal(f.resizeObservers.length, 1);
  assert.equal(f.mutationObservers.length, 1);
  const [resize] = f.resizeObservers;
  const [mutation] = f.mutationObservers;
  assert.equal(resize.target, f.list);
  assert.equal(mutation.target, f.list);
  assert.equal(mutation.options.childList, true);
  assert.notEqual(mutation.options.attributes, true); // Our class changes must not trigger a loop.
  f.list.clientHeight = 300;
  resize.callback();
  assert.deepEqual(f.hints(), { above: false, below: false });
  f.list.scrollHeight = 500;
  mutation.callback([{ type: 'childList', target: f.list }]);
  assert.deepEqual(f.hints(), { above: false, below: true });
  f.list.scrollHeight = 300;
  mutation.callback([{ type: 'childList', target: f.list }]);
  assert.deepEqual(f.hints(), { above: false, below: false });
  cleanup();
});

test('scroll hints: cleanup disconnects both observers and ignores already queued callbacks', () => {
  const f = fixture();
  const cleanup = installScrollHints(f.list, { win: f.win });
  const scroll = f.listeners.get('scroll').callback;
  const [resize] = f.resizeObservers;
  const [mutation] = f.mutationObservers;
  const before = f.hints();
  cleanup();
  cleanup();
  assert.equal(f.listeners.size, 0);
  assert.equal(resize.disconnected, true);
  assert.equal(mutation.disconnected, true);
  f.list.scrollTop = 200;
  scroll(); resize.callback(); mutation.callback([]);
  assert.deepEqual(f.hints(), before);
});
