import { test } from 'node:test';
import assert from 'node:assert/strict';
import visualizer, { createVisualizer } from '../../web/widgets/visualizer.js';
import { createStore, initialState } from '../../web/js/store.js';
import { applyEvent } from '../../web/js/bridge.js';

const spectrum = value => ({ bands: Array(12).fill(value), at: 0 });
function scheduler() {
  let next = 0, now = 0;
  const frames = new Map(), timers = new Map(), frameRequests = [], timerRequests = [];
  return {
    frames, timers, frameRequests, timerRequests,
    raf(callback) { const id = next++; frames.set(id, callback); frameRequests.push(id); return id; },
    cancelRaf(id) { frames.delete(id); },
    setTimer(callback, delay) {
      const id = next++; timers.set(id, { callback, due: now + delay }); timerRequests.push(delay); return id;
    },
    clearTimer(id) { timers.delete(id); },
    draw() {
      const pending = [...frames]; frames.clear();
      for (const [, callback] of pending) callback(now);
    },
    advance(ms) {
      now += ms;
      for (const [id, timer] of [...timers]) {
        if (timer.due <= now) { timers.delete(id); timer.callback(); }
      }
    },
  };
}
function bar(writes) {
  let transform = '';
  return { style: {
    get transform() { return transform; },
    set transform(value) { transform = value; writes.push(value); },
    removeProperty(name) { assert.equal(name, 'transform'); transform = ''; },
  } };
}
function fixture(rest = 0.02) {
  const clock = scheduler(), writes = [];
  const bars = { left: Array.from({ length: 12 }, () => bar(writes)), right: Array.from({ length: 12 }, () => bar(writes)) };
  const player = createVisualizer({ bars, ...clock, rest });
  return { ...clock, bars, writes, player };
}
const transforms = f => [...f.bars.left, ...f.bars.right].map(node => node.style.transform);
const idle = f => { assert.equal(f.frames.size, 0); assert.equal(f.timers.size, 0); };
const atRest = f => assert.deepEqual(transforms(f), Array(24).fill(''));

test('visualizer: mounting without spectrum schedules no work', () => {
  const f = fixture(); idle(f); f.advance(10000); f.draw(); idle(f); assert.equal(f.writes.length, 0);
});
test('visualizer: three spectra share one frame and render only the latest values on both sides', () => {
  const f = fixture();
  f.player.update(spectrum(0.2)); f.player.update(spectrum(0.4)); f.player.update(spectrum(0.8));
  assert.equal(f.frameRequests.length, 1); assert.equal(f.frames.size, 1); assert.equal(f.timers.size, 1);
  assert.deepEqual(f.timerRequests, [250, 250, 250]); assert.equal(f.writes.length, 0);
  f.draw(); assert.deepEqual(transforms(f), Array(24).fill('scaleY(0.8)')); assert.equal(f.writes.length, 24);
  assert.equal(f.frames.size, 0); assert.equal(f.frameRequests.length, 1);
  f.draw(); assert.equal(f.writes.length, 24);
});
test('visualizer: each band keeps its index on both sides and clamps only to the CSS rest value', () => {
  const f = fixture(0.07);
  f.player.update({ bands: [0, 0.01, 0.07, 0.08, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.9, 1] }); f.draw();
  const expected = ['scaleY(0.07)', 'scaleY(0.07)', 'scaleY(0.07)', 'scaleY(0.08)', 'scaleY(0.2)', 'scaleY(0.3)', 'scaleY(0.4)', 'scaleY(0.5)', 'scaleY(0.6)', 'scaleY(0.7)', 'scaleY(0.9)', 'scaleY(1)'];
  assert.deepEqual(transforms(f), [...expected, ...expected]);
});
test('visualizer: silence resets at 250ms after the last update then leaves no pending work', () => {
  const f = fixture(); f.player.update(spectrum(0.6)); f.draw(); f.advance(200);
  f.player.update(spectrum(0.8)); f.draw(); f.advance(249);
  assert.deepEqual(transforms(f), Array(24).fill('scaleY(0.8)'));
  f.advance(1); atRest(f); idle(f); const count = f.writes.length;
  f.advance(10000); f.draw(); idle(f); assert.equal(f.writes.length, count);
  f.player.update(spectrum(0.4)); f.draw(); assert.deepEqual(transforms(f), Array(24).fill('scaleY(0.4)'));
});
test('visualizer: silence cancels a frame that has not rendered yet', () => {
  const f = fixture(); f.player.update(spectrum(1));
  const staleFrame = [...f.frames.values()][0]; assert.equal(typeof staleFrame, 'function');
  f.advance(250); idle(f); atRest(f); staleFrame(); assert.equal(f.writes.length, 0); idle(f);
});
for (const rendered of [false, true]) {
  test(`visualizer: null immediately resets and cancels pending work (rendered=${rendered})`, () => {
    const f = fixture(); f.player.update(spectrum(0.8)); if (rendered) f.draw();
    f.player.update(null); idle(f); atRest(f); f.player.update(null); idle(f);
  });
  test(`visualizer: pause immediately resets, ignores spectrum, and resumes only on fresh data (rendered=${rendered})`, () => {
    const f = fixture(); f.player.update(spectrum(0.8)); if (rendered) f.draw();
    f.player.setPaused(true); idle(f); atRest(f);
    f.player.update(spectrum(1)); idle(f); atRest(f);
    f.player.setPaused(false); idle(f); atRest(f);
    f.player.update(spectrum(0.4)); f.draw(); assert.deepEqual(transforms(f), Array(24).fill('scaleY(0.4)'));
  });
}
test('visualizer: canceled callbacks cannot reset or render over a newer spectrum', () => {
  const f = fixture(); f.player.update(spectrum(0.3));
  const oldFrame = [...f.frames.values()][0], oldTimer = [...f.timers.values()][0].callback;
  f.player.update(null); f.player.update(spectrum(0.9)); oldFrame(); oldTimer();
  assert.equal(f.frames.size, 1); assert.equal(f.timers.size, 1); assert.equal(f.writes.length, 0);
  f.draw(); assert.deepEqual(transforms(f), Array(24).fill('scaleY(0.9)'));
  const replacedTimer = [...f.timers.values()][0].callback;
  f.player.update(spectrum(0.5)); replacedTimer(); assert.equal(f.frames.size, 1); assert.equal(f.timers.size, 1);
  f.draw(); assert.deepEqual(transforms(f), Array(24).fill('scaleY(0.5)'));
});
test('visualizer: disposal resets bars, cancels work, and ignores requests and late callbacks', () => {
  const f = fixture(); f.player.update(spectrum(0.6)); f.draw(); f.player.update(spectrum(0.9));
  const oldFrame = [...f.frames.values()][0], oldTimer = [...f.timers.values()][0].callback;
  f.player.dispose(); f.player.dispose(); atRest(f); idle(f); const count = f.writes.length;
  f.player.update(spectrum(1)); f.player.setPaused(false); oldFrame(); oldTimer();
  assert.equal(f.writes.length, count); atRest(f); idle(f);
});

function mountFixture(initial = {}) {
  const clock = scheduler(), writes = [], nodes = [], computedReads = [];
  class Element {
    constructor(tag) {
      this.tagName = tag.toUpperCase(); this.children = []; this.attributes = {};
      this.className = ''; this.style = bar(writes).style; this.ownerDocument = doc; nodes.push(this);
    }
    append(...children) { this.children.push(...children); }
    setAttribute(key, value) { this.attributes[key] = String(value); }
    getAttribute(key) { return this.attributes[key] ?? null; }
  }
  const win = {
    requestAnimationFrame(cb) { assert.equal(this, win); return clock.raf(cb); },
    cancelAnimationFrame(id) { assert.equal(this, win); clock.cancelRaf(id); },
    setTimeout(cb, delay) { assert.equal(this, win); return clock.setTimer(cb, delay); },
    clearTimeout(id) { assert.equal(this, win); clock.clearTimer(id); },
    getComputedStyle(root) {
      assert.equal(root, doc.documentElement); computedReads.push(root);
      return { getPropertyValue(name) { assert.equal(name, '--viz-bar-rest'); return ' 0.07 '; } };
    },
  };
  const doc = { defaultView: win, documentElement: {}, createElement: tag => new Element(tag) };
  const host = doc.createElement('section'), store = createStore({ ...initialState, ...initial });
  const cleanup = visualizer.mount(host, { store });
  return { ...clock, host, store, cleanup, nodes, writes, computedReads };
}
test('visualizer: synchronous mount creates 24 decorative spans and the non-draggable heart without hit regions', () => {
  const f = mountFixture(); assert.equal(typeof f.cleanup, 'function');
  assert.equal(visualizer.name, 'visualizer'); assert.equal(visualizer.css, 'visualizer.css');
  assert.equal(f.host.getAttribute('aria-hidden'), 'true');
  assert.deepEqual(f.host.children.map(node => node.className), ['viz-bars left', 'viz-bars right', 'viz-ornament']);
  for (const group of f.host.children.slice(0, 2)) {
    assert.equal(group.children.length, 12); assert.ok(group.children.every(node => node.tagName === 'SPAN'));
  }
  const image = f.host.children[2];
  assert.equal(image.tagName, 'IMG'); assert.equal(image.src, '/media/ornaments/heart.png');
  assert.equal(image.alt, ''); assert.equal(image.draggable, false);
  assert.ok(f.nodes.every(node => node.getAttribute('data-hit') === null && !node.className.split(' ').includes('card')));
  assert.equal(f.computedReads.length, 1); idle(f); f.cleanup();
});
test('visualizer: mount consumes initial spectrum and reads the CSS rest only once', () => {
  const f = mountFixture({ audioSpectrum: spectrum(0.01) });
  assert.equal(f.frames.size, 1); f.draw(); assert.deepEqual(f.writes, Array(24).fill('scaleY(0.07)'));
  applyEvent(f.store, { event: 'audioSpectrum', bands: Array(12).fill(0.5) }); f.draw();
  assert.equal(f.computedReads.length, 1); assert.deepEqual(f.writes.slice(24), Array(24).fill('scaleY(0.5)')); f.cleanup(); idle(f);
});
test('visualizer: initially paused mount ignores an existing spectrum and awaits new data after resume', () => {
  const f = mountFixture({ paused: true, audioSpectrum: spectrum(0.6) }); idle(f);
  f.store.set({ paused: false }); idle(f);
  applyEvent(f.store, { event: 'audioSpectrum', bands: Array(12).fill(0.3) });
  f.draw(); assert.deepEqual(f.writes, Array(24).fill('scaleY(0.3)')); f.cleanup();
});
test('visualizer: bridge pause/null resets immediately and late spectrum stays idle until resume', () => {
  const f = mountFixture(); applyEvent(f.store, { event: 'audioSpectrum', bands: Array(12).fill(0.8) }); f.draw();
  applyEvent(f.store, { event: 'paused', paused: true }); idle(f);
  assert.ok(f.host.children.slice(0, 2).flatMap(group => group.children).every(node => node.style.transform === ''));
  applyEvent(f.store, { event: 'audioSpectrum', bands: Array(12).fill(1) }); idle(f);
  applyEvent(f.store, { event: 'paused', paused: false }); idle(f);
  applyEvent(f.store, { event: 'audioSpectrum', bands: Array(12).fill(0.4) }); assert.equal(f.frames.size, 1);
  f.store.set({ audioSpectrum: null }); idle(f); f.cleanup();
});
test('visualizer: mount cleanup unsubscribes and cancels both pending handles', () => {
  const f = mountFixture(); f.store.set({ audioSpectrum: spectrum(0.5) });
  assert.equal(f.frames.size, 1); assert.equal(f.timers.size, 1); f.cleanup(); f.cleanup(); idle(f);
  f.store.set({ paused: true }); f.store.set({ paused: false, audioSpectrum: spectrum(1) });
  idle(f); assert.equal(f.writes.length, 0);
});
