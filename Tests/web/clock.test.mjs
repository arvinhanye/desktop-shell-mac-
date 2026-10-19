import { test } from 'node:test';
import assert from 'node:assert/strict';
import clock, { phaseForHour, clockText, msUntilNextMinute } from '../../web/widgets/clock.js';
import { createStore, initialState } from '../../web/js/store.js';

for (const [hour, expected] of [[0, 'night'], [5, 'night'], [6, 'morning'], [11, 'morning'],
  [12, 'day'], [17, 'day'], [18, 'evening'], [20, 'evening'], [21, 'night'], [23, 'night']]) {
  test(`clock: hour ${hour} uses ${expected}`, () => assert.equal(phaseForHour(hour), expected));
}

test('clock: local September date uses uppercase names and zero-padded day/time', () => {
  assert.deepEqual(clockText(new Date(2026, 8, 9, 7, 5)), {
    weekday: 'WEDNESDAY', day: '09', month: 'SEPTEMBER', time: '07:05', date: '9月9日 星期三',
  });
});

test('clock: local year end keeps 24-hour time and unpadded Chinese date', () => {
  assert.deepEqual(clockText(new Date(2026, 11, 31, 23, 59)), {
    weekday: 'THURSDAY', day: '31', month: 'DECEMBER', time: '23:59', date: '12月31日 星期四',
  });
});

for (const [seconds, milliseconds, expected] of [[0, 0, 60000], [59, 950, 50], [30, 125, 29875]]) {
  test(`clock: next minute delay at ${seconds}s ${milliseconds}ms`, () => {
    assert.equal(msUntilNextMinute(new Date(2026, 8, 9, 7, 5, seconds, milliseconds)), expected);
  });
}

function fixture(date = new Date(2026, 8, 9, 11, 59, 59, 950)) {
  let now = date.getTime();
  let nextTimer = 0;
  const timers = new Map();
  const listeners = new Map();
  class Element {
    constructor(tagName) { this.tagName = tagName.toUpperCase(); this.children = []; this.attributes = {}; this.className = ''; this._text = ''; this.ownerDocument = doc; }
    append(...children) { this.children.push(...children); }
    setAttribute(name, value) { this.attributes[name] = String(value); }
    getAttribute(name) { return this.attributes[name] ?? null; }
    set textContent(value) { this._text = String(value); this.children = []; }
    get textContent() { return this._text + this.children.map(child => child.textContent).join(''); }
    set innerHTML(_) { throw new Error('Clock must build DOM with textContent'); }
  }
  const win = {
    Date: class extends Date { constructor() { super(now); } },
    setTimeout(callback, delay) { timers.set(++nextTimer, { callback, delay }); return nextTimer; },
    clearTimeout(id) { timers.delete(id); },
  };
  const doc = {
    defaultView: win, visibilityState: 'visible',
    createElement: tag => new Element(tag),
    addEventListener: (type, callback) => listeners.set(type, callback),
    removeEventListener(type, callback) { if (listeners.get(type) === callback) listeners.delete(type); },
  };
  const host = doc.createElement('section');
  host.className = 'widget';
  const store = createStore({ ...initialState, paused: true });
  return { host, store, doc, timers, listeners,
    setTime: date => { now = date.getTime(); },
    visible: state => { doc.visibilityState = state; listeners.get('visibilitychange')?.(); },
    fire() { const [id, timer] = timers.entries().next().value; timers.delete(id); timer.callback(); },
  };
}

test('clock: mount renders immediately without hit targets and publishes minute/phase even paused', () => {
  const f = fixture();
  assert.equal(clock.name, 'clock');
  assert.equal(clock.css, 'clock.css');
  const cleanup = clock.mount(f.host, { store: f.store });
  assert.equal(typeof cleanup, 'function');
  assert.equal(f.host.getAttribute('aria-label'), '日期');
  assert.deepEqual(f.host.children.map(child => [child.tagName, child.className, child.textContent]), [
    ['DIV', 'clock-weekday', 'WEDNESDAY'], ['DIV', 'clock-day', '09'], ['DIV', 'clock-month', 'SEPTEMBER'],
    ['DIV', 'clock-time', '11:59'], ['DIV', 'clock-rule', ''], ['DIV', 'clock-date', '9月9日 星期三'],
  ]);
  assert.ok([f.host, ...f.host.children].every(element => !element.className.split(' ').includes('card') && element.getAttribute('data-hit') === null));
  assert.equal(f.store.get('now'), new Date(2026, 8, 9, 11, 59).getTime());
  assert.equal(f.store.get('phase'), 'morning');
  assert.equal(f.store.get('paused'), true);
  assert.equal(f.timers.size, 1);
  assert.equal([...f.timers.values()][0].delay, 100);
  cleanup();
});

test('clock: each one-shot tick rechecks wall time and crosses noon without stopping for pause', () => {
  const f = fixture();
  const cleanup = clock.mount(f.host, { store: f.store });
  assert.equal(f.timers.size, 1);
  f.setTime(new Date(2026, 8, 9, 12, 0, 0, 50));
  f.fire();
  assert.equal(f.host.children[3].textContent, '12:00');
  assert.equal(f.store.get('now'), new Date(2026, 8, 9, 12).getTime());
  assert.equal(f.store.get('phase'), 'day');
  assert.equal(f.timers.size, 1);
  assert.equal([...f.timers.values()][0].delay, 60000);
  f.setTime(new Date(2026, 8, 9, 21, 17, 23, 400)); // A throttled callback must not increment stale time.
  f.fire();
  assert.equal(f.host.children[3].textContent, '21:17');
  assert.equal(f.store.get('phase'), 'night');
  assert.equal([...f.timers.values()][0].delay, 36650);
  cleanup();
});

test('clock: becoming visible immediately catches up across midnight and replaces the old timer', () => {
  const f = fixture(new Date(2026, 11, 31, 23, 59, 20));
  const cleanup = clock.mount(f.host, { store: f.store });
  assert.equal(f.listeners.has('visibilitychange'), true);
  const oldTimer = [...f.timers.keys()][0];
  f.setTime(new Date(2027, 0, 1, 6, 2, 10, 500));
  f.visible('hidden');
  assert.equal(f.host.children[3].textContent, '23:59');
  f.visible('visible');
  assert.equal(f.host.children[1].textContent, '01');
  assert.equal(f.host.children[2].textContent, 'JANUARY');
  assert.equal(f.host.children[3].textContent, '06:02');
  assert.equal(f.store.get('now'), new Date(2027, 0, 1, 6, 2).getTime());
  assert.equal(f.store.get('phase'), 'morning');
  assert.equal(f.timers.size, 1);
  assert.equal(f.timers.has(oldTimer), false);
  assert.equal([...f.timers.values()][0].delay, 49550);
  cleanup();
});

test('clock: cleanup removes timer/listener and a queued callback cannot restart updates', () => {
  const f = fixture();
  const cleanup = clock.mount(f.host, { store: f.store });
  assert.equal(f.timers.size, 1);
  const tick = [...f.timers.values()][0].callback;
  const visible = f.listeners.get('visibilitychange');
  const before = f.store.getState();
  cleanup(); cleanup();
  assert.equal(f.timers.size, 0);
  assert.equal(f.listeners.size, 0);
  f.setTime(new Date(2027, 0, 1, 12));
  tick(); visible();
  assert.deepEqual(f.store.getState(), before);
  assert.equal(f.timers.size, 0);
});
