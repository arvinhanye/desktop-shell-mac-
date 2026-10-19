import { test } from 'node:test';
import assert from 'node:assert/strict';
import greeting, { greetingFor } from '../../web/widgets/greeting.js';
import { createStore, initialState } from '../../web/js/store.js';

const greetings = [
  { from: 0, title: '深夜了', wish: '时辰已晚，且捻熄灯盏，良宵安枕' },
  { from: 6, title: '早上好', wish: '晨光熹微，愿您涤尽尘扰，理裳启新日' },
  { from: 12, title: '下午好', wish: '愿清风伴您今日，时刻皆有阳光满心' },
  { from: 18, title: '傍晚了', wish: '且舒怀抱，自在一刻尽欢愉' },
  { from: 20, title: '晚上好', wish: '且舒怀抱，自在一刻尽欢愉' },
  { from: 21, title: '晚上好', wish: '时辰已晚，且捻熄灯盏，良宵安枕' },
  { from: 23, title: '深夜了', wish: '时辰已晚，且捻熄灯盏，良宵安枕' },
];

for (const [hour, from] of [[0, 0], [5, 0], [6, 6], [12, 12], [18, 18], [19, 18], [20, 20], [21, 21], [23, 23]]) {
  test(`greeting: hour ${hour} selects the entry starting at ${from}`, () => {
    assert.deepEqual(greetingFor(greetings, hour), greetings.find(item => item.from === from));
  });
}

test('greeting: unsorted frozen input is copied before sorting', () => {
  const input = Object.freeze([greetings[5], greetings[1], greetings[6], greetings[3], greetings[0], greetings[4], greetings[2]]);
  const before = input.slice();
  for (const [hour, from] of [[0, 0], [5, 0], [6, 6], [12, 12], [18, 18], [19, 18], [20, 20], [21, 21], [23, 23]]) {
    assert.equal(greetingFor(input, hour)?.from, from);
  }
  assert.deepEqual(input, before);
});

test('greeting: before the first start continues the previous day final entry', () => {
  assert.deepEqual(greetingFor([greetings[3], greetings[6], greetings[1]], 3), greetings[6]);
});

test('greeting: empty list returns null', () => assert.equal(greetingFor([], 12), null));

function fixture({ config = null, now = null } = {}) {
  class Element {
    constructor(tagName) { this.tagName = tagName.toUpperCase(); this.children = []; this.attributes = {}; this.className = ''; this.hidden = false; this._text = ''; this.ownerDocument = doc; }
    append(...children) { this.children.push(...children); }
    setAttribute(name, value) { this.attributes[name] = String(value); }
    getAttribute(name) { return this.attributes[name] ?? null; }
    set textContent(value) { this._text = String(value); this.children = []; }
    get textContent() { return this._text + this.children.map(child => child.textContent).join(''); }
    set innerHTML(_) { throw new Error('User text must not be parsed as HTML'); }
  }
  const doc = { createElement: tag => new Element(tag), defaultView: { Date: class extends Date {
    constructor(value) { super(value === undefined ? new Date(2026, 8, 9, 7, 5).getTime() : value); }
  } } };
  const host = doc.createElement('section');
  host.className = 'widget';
  const store = createStore({ ...initialState, config, now });
  return { host, store };
}

test('greeting: empty before config arrives, then current local time is used while now is null', () => {
  const f = fixture();
  assert.equal(greeting.name, 'greeting');
  assert.equal(greeting.css, 'greeting.css');
  const cleanup = greeting.mount(f.host, { store: f.store });
  assert.equal(typeof cleanup, 'function');
  assert.equal(f.host.getAttribute('aria-label'), '问候语');
  assert.equal(f.host.textContent, '');
  f.store.set({ config: { user: { name: 'Arvin' }, greetings } });
  assert.deepEqual(f.host.children.map(child => [child.tagName, child.className]), [['P', 'greeting-title'], ['P', 'greeting-wish']]);
  assert.equal(f.host.children[0].textContent, '早上好，Arvin');
  assert.equal(f.host.children[0].children[2].className, 'greeting-name');
  assert.equal(f.host.children[1].textContent, greetings[1].wish);
  assert.ok([f.host, ...f.host.children, ...f.host.children[0].children].every(element => !element.className.split(' ').includes('card') && element.getAttribute('data-hit') === null));
  cleanup();
});

test('greeting: now selects the local hour, including a zero timestamp, and reacts at the next hour', () => {
  const f = fixture({ config: { user: { name: 'Arvin' }, greetings }, now: new Date(2026, 8, 9, 20, 59).getTime() });
  const cleanup = greeting.mount(f.host, { store: f.store });
  assert.equal(f.host.children.length, 2);
  assert.equal(f.host.children[1].textContent, greetings[4].wish);
  f.store.set({ now: new Date(2026, 8, 9, 21).getTime() });
  assert.equal(f.host.children[1].textContent, greetings[5].wish);
  f.store.set({ config: { user: { name: 'Arvin' }, greetings: Array.from({ length: 24 }, (_, from) => ({ from, title: `hour-${from}`, wish: '' })) }, now: 0 });
  assert.equal(f.host.children[0].children[0].textContent, `hour-${new Date(0).getHours()}`);
  cleanup();
});

test('greeting: removing name hides comma/name and later configuration restores them as text', () => {
  const f = fixture({ config: { user: { name: null }, greetings } });
  const cleanup = greeting.mount(f.host, { store: f.store });
  assert.equal(f.host.children.length, 2);
  const [title, wish] = f.host.children;
  const [label, comma, name] = title.children;
  assert.equal(label.textContent, '早上好');
  assert.equal(comma.hidden, true);
  assert.equal(name.hidden, true);
  const hostile = '<img src=x onerror=alert(1)>';
  f.store.set({ config: { user: { name: hostile }, greetings: [{ from: 0, title: '<b>你好</b>', wish: '<script>x</script>' }] } });
  assert.equal(label.textContent, '<b>你好</b>');
  assert.equal(comma.textContent, '，');
  assert.equal(comma.hidden, false);
  assert.equal(name.textContent, hostile);
  assert.equal(name.hidden, false);
  assert.equal(name.children.length, 0);
  assert.equal(wish.textContent, '<script>x</script>');
  f.store.set({ config: { user: { name: null }, greetings } });
  assert.equal(comma.hidden, true);
  assert.equal(name.hidden, true);
  cleanup();
});

test('greeting: clearing config or greetings removes stale content; cleanup unsubscribes both keys', () => {
  const f = fixture({ config: { user: { name: 'Arvin' }, greetings } });
  const cleanup = greeting.mount(f.host, { store: f.store });
  assert.notEqual(f.host.textContent, '');
  f.store.set({ config: { user: { name: 'Arvin' }, greetings: [] } });
  assert.equal(f.host.textContent, '');
  f.store.set({ config: { user: { name: 'Arvin' }, greetings } });
  assert.notEqual(f.host.textContent, '');
  f.store.set({ config: null });
  assert.equal(f.host.textContent, '');
  cleanup(); cleanup();
  f.store.set({ config: { user: { name: 'Later' }, greetings }, now: new Date(2026, 8, 9, 12).getTime() });
  assert.equal(f.host.textContent, '');
});
