import { test } from 'node:test';
import assert from 'node:assert/strict';
import projects, { projectActions, toggleSelection } from '../../web/widgets/projects.js';
import { createStore, initialState } from '../../web/js/store.js';

const apps = [{ id: 'cursor', name: 'Cursor' }, { id: 'safari', name: 'Safari' }];
const config = { apps, projects: [
  { id: 'p1', name: 'Project 1', tags: ['dev'], apps: ['cursor'] },
  { id: 'p2', name: 'Project 2', tags: [], apps: ['missing', 'safari', 'cursor'] },
] };
const finder = { label: '访达', title: '在访达中打开', action: 'openProject', payload: { projectId: 'p1' } };
for (const appIds of [undefined, [], ['missing']]) {
  test(`projects: ${JSON.stringify(appIds)} gives only Finder`, () => {
    assert.deepEqual(projectActions({ id: 'p1', apps: appIds }, apps), [finder]);
  });
}
test('projects: first configured app is chosen after skipping unknown ids, payloads contain ids only', () => {
  const p = { id: 'p1', name: 'private name', path: '/private/path', apps: ['missing', 'safari', 'cursor'] };
  const before = structuredClone(p);
  assert.deepEqual(projectActions(p, apps), [finder, { label: 'Safari', title: '用 Safari 打开', action: 'openProjectWith', payload: { projectId: 'p1', appId: 'safari' } }]);
  assert.deepEqual(p, before);
});
test('projects: normal app creates Finder plus its app button', () => {
  assert.deepEqual(projectActions(config.projects[0], apps), [finder, { label: 'Cursor', title: '用 Cursor 打开', action: 'openProjectWith', payload: { projectId: 'p1', appId: 'cursor' } }]);
});
for (const [current, id, expected] of [[null, 'p1', 'p1'], ['p1', 'p1', null], ['p1', 'p2', 'p2']]) {
  test(`projects: toggle ${current} to ${id}`, () => assert.equal(toggleSelection(current, id), expected));
}

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

test('projects: mount creates the card, error slot and empty-project message', () => {
  const f = fixture({ config: { projects: [], apps } });
  assert.equal(projects.name, 'projects'); assert.equal(projects.css, 'projects.css');
  const cleanup = projects.mount(f.host, f);
  assert.equal(typeof cleanup, 'function');
  assert.equal(f.host.getAttribute('aria-label'), '项目');
  const card = one(f.host, 'projects-card');
  assert.ok(card.classList.contains('card'));
  assert.equal(one(card, 'card-title').textContent, '项目');
  assert.equal(one(one(card, 'card-head'), 'card-meta').textContent, '');
  assert.equal(one(card, 'project-list').textContent, '还没有项目，在 config.json 的 projects 里添加');
  cleanup();
});
test('projects: row selection follows the store without replacing rows or resetting scroll', () => {
  const f = fixture({ config }); const cleanup = projects.mount(f.host, f);
  const rows = all(f.host, 'project'), list = one(f.host, 'project-list');
  assert.equal(rows.length, 2);
  assert.equal(rows[0].getAttribute('role'), 'button'); assert.equal(rows[0].tabIndex, 0);
  list.scrollTop = 80;
  one(rows[0], 'project-name').emit('click');
  assert.equal(f.store.get('selectedProject'), 'p1'); assert.ok(rows[0].classList.contains('selected'));
  rows[0].emit('click'); assert.equal(f.store.get('selectedProject'), null);
  rows[1].emit('click'); assert.equal(f.store.get('selectedProject'), 'p2');
  f.store.set({ selectedProject: 'p1' });
  assert.ok(rows[0].classList.contains('selected')); assert.ok(!rows[1].classList.contains('selected'));
  assert.equal(all(f.host, 'project')[0], rows[0]); assert.equal(list.scrollTop, 80);
  cleanup();
});
test('projects: Enter/Space toggle the focused row, not its nested buttons or repeated keys', () => {
  const f = fixture({ config }); const cleanup = projects.mount(f.host, f);
  const row = one(f.host, 'project'), button = one(row, 'ghost-button');
  assert.equal(row.emit('keydown', { key: 'Enter' }).defaultPrevented, true);
  assert.equal(f.store.get('selectedProject'), 'p1');
  row.emit('keydown', { key: ' ', repeat: true }); assert.equal(f.store.get('selectedProject'), 'p1');
  button.emit('keydown', { key: ' ' }); button.emit('keydown', { key: 'Enter' });
  assert.equal(f.store.get('selectedProject'), 'p1');
  assert.equal(row.emit('keydown', { key: ' ' }).defaultPrevented, true);
  assert.equal(f.store.get('selectedProject'), null);
  row.emit('keydown', { key: 'Escape' }); assert.equal(f.store.get('selectedProject'), null);
  cleanup();
});
test('projects: each button deduplicates only its own pending request and does not select its row', async () => {
  const pending = []; const f = fixture({ config }, () => { const request = deferred(); pending.push(request); return request.promise; });
  const cleanup = projects.mount(f.host, f); const buttons = all(one(f.host, 'project'), 'ghost-button');
  assert.equal(buttons.length, 2); assert.equal(buttons[0].title, '在访达中打开'); assert.equal(buttons[1].title, '用 Cursor 打开');
  buttons[0].emit('click'); buttons[0].emit('click'); buttons[1].emit('click');
  assert.deepEqual(f.calls, [{ action: 'openProject', payload: { projectId: 'p1' } }, { action: 'openProjectWith', payload: { projectId: 'p1', appId: 'cursor' } }]);
  assert.equal(f.store.get('selectedProject'), null);
  pending[0].resolve(null); pending[1].resolve(null); await flush();
  assert.equal(one(one(f.host, 'card-head'), 'card-meta').textContent, '');
  buttons[0].emit('click'); assert.equal(f.calls.length, 3); pending[2].resolve(null); await flush(); cleanup();
});
test('projects: failures show a three-second message and a later failure restarts that timer', async () => {
  const f = fixture({ config }, async () => { throw new Error('failed'); }); const cleanup = projects.mount(f.host, f);
  const button = one(f.host, 'ghost-button'), status = one(one(f.host, 'card-head'), 'card-meta');
  button.emit('click'); await flush();
  assert.equal(status.textContent, '没能打开'); assert.equal(f.timers.size, 1);
  const first = [...f.timers.keys()][0]; assert.equal(f.timers.get(first).delay, 3000);
  const oldCallback = f.timers.get(first).callback;
  button.emit('click'); await flush();
  assert.equal(f.timers.size, 1); assert.equal(f.timers.has(first), false);
  oldCallback(); assert.equal(status.textContent, '没能打开');
  const [id, timer] = [...f.timers.entries()][0]; f.timers.delete(id); timer.callback();
  assert.equal(status.textContent, ''); cleanup();
});
test('projects: config changes clear removed selection and ignore replies from replaced buttons', async () => {
  const request = deferred(); const f = fixture({ config, selectedProject: 'p1' }, () => request.promise);
  const cleanup = projects.mount(f.host, f); const oldButton = one(f.host, 'ghost-button'); oldButton.emit('click');
  f.store.set({ config: { apps, projects: [config.projects[1]] } });
  assert.equal(f.store.get('selectedProject'), null); assert.equal(all(f.host, 'project').length, 1);
  request.reject(new Error('failed')); await flush();
  assert.equal(one(one(f.host, 'card-head'), 'card-meta').textContent, ''); assert.equal(f.timers.size, 0);
  oldButton.emit('click'); assert.equal(f.calls.length, 1); cleanup();
});
test('projects: untrusted labels stay text, scroll hints update, cleanup cancels observers/listeners/replies', async () => {
  const request = deferred(); const f = fixture({ config: { apps, projects: [{ ...config.projects[0], name: '<img src=x>', tags: ['<b>tag</b>'] }] } }, () => request.promise);
  const cleanup = projects.mount(f.host, f); const list = one(f.host, 'project-list'), button = one(f.host, 'ghost-button');
  assert.equal(one(f.host, 'project-name').textContent, '<img src=x>'); assert.equal(one(f.host, 'tag').textContent, '<b>tag</b>');
  assert.equal(one(f.host, 'project-name').children.length, 0);
  assert.equal(f.observers.length, 2); assert.ok(list.classList.contains('more-below'));
  list.scrollTop = 200; list.emit('scroll'); assert.ok(list.classList.contains('more-above')); assert.ok(!list.classList.contains('more-below'));
  button.emit('click'); cleanup(); cleanup();
  assert.ok(f.observers.every(observer => observer.disconnected)); assert.equal(list.listeners.get('scroll').size, 0);
  request.reject(new Error('failed')); await flush(); assert.equal(f.timers.size, 0);
  const text = f.host.textContent; f.store.set({ config: null, selectedProject: 'p2' });
  assert.equal(f.host.textContent, text); button.emit('click'); assert.equal(f.calls.length, 1);
});
