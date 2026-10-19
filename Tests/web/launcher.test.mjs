import { test } from 'node:test';
import assert from 'node:assert/strict';
import launcher, { firstGrapheme, relatedAppIds } from '../../web/widgets/launcher.js';
import { createStore, initialState } from '../../web/js/store.js';

for (const [input, expected] of [['备忘录', '备'], ['Figma', 'F'], ['👨‍👩‍👧‍👦 Family', '👨‍👩‍👧‍👦'], ['👍🏽 App', '👍🏽'], ['🇨🇳 Notes', '🇨🇳'], ['e\u0301ditor', 'e\u0301'], ['', '']]) {
  test(`launcher: first grapheme of ${JSON.stringify(input)}`, () => assert.equal(firstGrapheme(input), expected));
}
const config = { apps: [{ id: 'cursor', name: 'Cursor', iconUrl: '/media/app-icons/cursor.png' }, { id: 'figma', name: 'Figma', iconUrl: null }], projects: [{ id: 'p1', apps: ['cursor'] }, { id: 'p2' }] };
for (const [selected, expected] of [[null, []], ['missing', []], ['p2', []], ['p1', ['cursor']]]) {
  test(`launcher: related apps for ${selected}`, () => assert.deepEqual(relatedAppIds(config, selected), expected));
}
test('launcher: no config has no related apps', () => assert.deepEqual(relatedAppIds(null, 'p1'), []));

function fixture(initial = {}, send = async () => null) {
  const timers = new Map(), observers = [], calls = [];
  let nextTimer = 0;
  class Element {
    constructor(tag) { this.tagName = tag.toUpperCase(); this.children = []; this.parentElement = null; this.ownerDocument = doc; this.className = ''; this.attributes = {}; this.listeners = new Map(); this.style = {}; this._text = ''; this.scrollTop = 0; this.clientHeight = 100; this.scrollHeight = 300; }
    append(...children) { for (const child of children) { child.parentElement = this; this.children.push(child); } }
    replaceChildren(...children) { for (const child of this.children) child.parentElement = null; this.children = []; this._text = ''; this.append(...children); }
    replaceWith(next) { const parent = this.parentElement; if (!parent) return; parent.children.splice(parent.children.indexOf(this), 1, next); next.parentElement = parent; this.parentElement = null; }
    setAttribute(key, value) { this.attributes[key] = String(value); }
    getAttribute(key) { return this.attributes[key] ?? null; }
    set textContent(text) { this.replaceChildren(); this._text = String(text); }
    get textContent() { return this._text + this.children.map(child => child.textContent).join(''); }
    set innerHTML(_) { throw new Error('User content must use textContent'); }
    get classList() { return { contains: name => this.className.split(' ').includes(name), toggle: (name, force) => { const names = new Set(this.className.split(' ').filter(Boolean)); if (force) names.add(name); else names.delete(name); this.className = [...names].join(' '); } }; }
    addEventListener(type, fn) { if (!this.listeners.has(type)) this.listeners.set(type, new Set()); this.listeners.get(type).add(fn); }
    removeEventListener(type, fn) { this.listeners.get(type)?.delete(fn); }
    emit(type, detail = {}) {
      const event = { target: this, type, stopped: false, defaultPrevented: false, stopPropagation() { this.stopped = true; }, preventDefault() { this.defaultPrevented = true; }, ...detail };
      for (let element = this; element; element = event.stopped ? null : element.parentElement) {
        event.currentTarget = element;
        for (const fn of [...(element.listeners.get(type) ?? [])]) fn(event);
      }
      return event;
    }
  }
  const Observer = class {
    constructor(callback) { this.callback = callback; this.disconnected = false; observers.push(this); }
    observe(target, options) { this.target = target; this.options = options; }
    disconnect() { this.disconnected = true; }
  };
  const win = { ResizeObserver: Observer, MutationObserver: Observer,
    setTimeout(callback, delay) { timers.set(++nextTimer, { callback, delay }); return nextTimer; },
    clearTimeout(id) { timers.delete(id); },
  };
  const doc = { defaultView: win, createElement: tag => new Element(tag) };
  const host = doc.createElement('section');
  const store = createStore({ ...initialState, ...initial });
  const bridge = { send(action, payload) { calls.push({ action, payload }); return send(action, payload); } };
  return { host, store, bridge, timers, observers, calls };
}
const all = (root, cls) => [root, ...root.children.flatMap(child => all(child, cls))].filter(element => element.className.split(' ').includes(cls));
const one = (root, cls) => { const found = all(root, cls); assert.ok(found.length > 0, `missing .${cls}`); return found[0]; };
const flush = () => new Promise(resolve => setImmediate(resolve));
const deferred = () => { let resolve, reject; const promise = new Promise((yes, no) => { resolve = yes; reject = no; }); return { promise, resolve, reject }; };

test('launcher: creates real images and grapheme fallbacks; failed image is replaced once', () => {
  const f = fixture({ config }); assert.equal(launcher.name, 'launcher'); assert.equal(launcher.css, 'launcher.css');
  const cleanup = launcher.mount(f.host, f); assert.equal(typeof cleanup, 'function');
  assert.equal(f.host.getAttribute('aria-label'), '应用启动栏');
  const card = one(f.host, 'launcher-card'); assert.ok(card.classList.contains('card'));
  assert.deepEqual(card.children.map(element => element.className), ['card-art', 'app-row']);
  const buttons = all(card, 'app'); assert.equal(buttons.length, 2); assert.equal(buttons[0].title, '启动 Cursor');
  const img = one(buttons[0], 'app-icon'); assert.equal(img.tagName, 'IMG'); assert.equal(img.alt, ''); assert.equal(img.draggable, false); assert.equal(img.src, '/media/app-icons/cursor.png');
  assert.equal(one(buttons[1], 'app-icon-fallback').textContent, 'F');
  img.emit('error'); assert.equal(one(buttons[0], 'app-icon-fallback').textContent, 'C');
  img.emit('error'); assert.equal(all(buttons[0], 'app-icon').length, 1); cleanup();
});
test('launcher: launch sends only app id and consumes failures without adding a UI message or logging twice', async t => {
  const error = t.mock.method(console, 'error', () => {});
  const f = fixture({ config }, async () => { throw new Error('failed'); }); const cleanup = launcher.mount(f.host, f);
  const before = f.host.textContent; one(f.host, 'app').emit('click'); await flush();
  assert.deepEqual(f.calls, [{ action: 'launchApp', payload: { appId: 'cursor' } }]);
  assert.equal(f.host.textContent, before); assert.equal(error.mock.callCount(), 0); cleanup();
});
test('launcher: highlight follows selection and project-app changes without selection causing a rebuild', () => {
  const f = fixture({ config }); const cleanup = launcher.mount(f.host, f); const first = one(f.host, 'app');
  assert.ok(!first.classList.contains('related'));
  f.store.set({ selectedProject: 'p1' }); assert.ok(first.classList.contains('related')); assert.equal(one(f.host, 'app'), first);
  f.store.set({ selectedProject: 'p2' }); assert.ok(!first.classList.contains('related'));
  f.store.set({ selectedProject: 'p1', config: { ...config, projects: [{ id: 'p1', apps: ['figma'] }] } });
  assert.ok(!all(f.host, 'app')[0].classList.contains('related')); assert.ok(all(f.host, 'app')[1].classList.contains('related'));
  f.store.set({ selectedProject: null }); assert.ok(all(f.host, 'app').every(button => !button.classList.contains('related'))); cleanup();
});
test('launcher: background reacts to ui and media; null/missing id clears stale art', () => {
  const f = fixture({ config, media: { avatars: [], backgrounds: [{ id: 'bg', url: '/media/backgrounds/one.png' }] }, ui: { backgroundId: 'bg' } });
  const cleanup = launcher.mount(f.host, f); const art = one(f.host, 'card-art');
  assert.equal(art.style.backgroundImage, 'url("/media/backgrounds/one.png")');
  f.store.set({ media: { backgrounds: [{ id: 'bg', url: '/media/backgrounds/two.png' }] } });
  assert.equal(art.style.backgroundImage, 'url("/media/backgrounds/two.png")');
  f.store.set({ ui: { backgroundId: null } }); assert.equal(art.style.backgroundImage, 'none');
  f.store.set({ ui: { backgroundId: 'missing' } }); assert.equal(art.style.backgroundImage, 'none');
  f.store.set({ ui: { backgroundId: 'bg' } }); f.store.set({ media: { backgrounds: [] } }); assert.equal(art.style.backgroundImage, 'none'); cleanup();
});
test('launcher: config may arrive after mount, text stays literal, cleanup detaches handlers and subscriptions', () => {
  const f = fixture(); const cleanup = launcher.mount(f.host, f); assert.equal(all(f.host, 'app').length, 0);
  f.store.set({ config: { apps: [{ id: 'odd', name: '<b>Name</b>', iconUrl: '/media/app-icons/odd.png' }], projects: [] } });
  const button = one(f.host, 'app'), image = one(button, 'app-icon'); assert.equal(one(button, 'app-name').textContent, '<b>Name</b>'); assert.equal(one(button, 'app-name').children.length, 0);
  f.store.set({ config }); image.emit('error'); button.emit('click'); assert.equal(f.calls.length, 0);
  const current = one(f.host, 'app'), text = f.host.textContent; cleanup(); cleanup();
  current.emit('click'); assert.equal(f.calls.length, 0);
  f.store.set({ config: null, selectedProject: 'p1', ui: { backgroundId: 'bg' }, media: { backgrounds: [{ id: 'bg', url: '/bg.png' }] } });
  assert.equal(f.host.textContent, text); assert.equal(one(f.host, 'card-art').style.backgroundImage, 'none');
});
