import { test } from 'node:test';
import assert from 'node:assert/strict';
import projects, { projectActions, toggleSelection } from '../../web/widgets/projects.js';
import { applyEvent, createBridge } from '../../web/js/bridge.js';
import { createMock } from '../../web/js/mock.js';
import { createStore, initialState } from '../../web/js/store.js';

const config = { projects: [
  { id: 'p1', name: 'Project 1', tags: ['dev'] },
  { id: 'p2', name: 'Project 2', tags: [] },
] };
const finder = { label: '访达', title: '在访达中打开', action: 'openProject', payload: { projectId: 'p1' } };
test('projects: Finder payload contains only project identity and leaves project data untouched', () => {
  const p = { id: 'p1', name: 'private name', path: '/private/path' };
  const before = structuredClone(p);
  assert.deepEqual(projectActions(p), [finder]);
  assert.deepEqual(p, before);
});
test('projects: older application preferences do not add an opening action', () => {
  assert.deepEqual(projectActions({ id: 'p1', apps: ['cursor'] }, [{ id: 'cursor', name: 'Cursor' }]), [finder]);
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
  const doc = { defaultView: win, createElement: tag => new Element(tag), createElementNS: (_, tag) => new Element(tag) };
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
  const f = fixture({ config: { projects: [] } });
  assert.equal(projects.name, 'projects'); assert.equal(projects.css, 'projects.css');
  const cleanup = projects.mount(f.host, f);
  assert.equal(typeof cleanup, 'function');
  assert.equal(f.host.getAttribute('aria-label'), '项目');
  const card = one(f.host, 'projects-card');
  assert.ok(card.classList.contains('card'));
  assert.equal(one(card, 'card-title').textContent, '项目');
  assert.equal(one(one(card, 'card-head'), 'card-meta').textContent, '');
  assert.equal(one(card, 'project-list').textContent, '还没有项目，在上面粘贴文件夹路径，或把文件夹拖进来');
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
test('projects: each row has one Finder button and deduplicates its pending request without selecting', async () => {
  const pending = []; const f = fixture({ config }, () => { const request = deferred(); pending.push(request); return request.promise; });
  const cleanup = projects.mount(f.host, f); const buttons = all(one(f.host, 'project'), 'ghost-button');
  assert.equal(buttons.length, 1); assert.equal(buttons[0].title, '在访达中打开');
  assert.equal(buttons[0].textContent, '访达');
  buttons[0].emit('click'); buttons[0].emit('click');
  assert.deepEqual(f.calls, [{ action: 'openProject', payload: { projectId: 'p1' } }]);
  assert.equal(f.store.get('selectedProject'), null);
  pending[0].resolve(null); await flush();
  assert.equal(one(one(f.host, 'card-head'), 'card-meta').textContent, '');
  buttons[0].emit('click'); assert.equal(f.calls.length, 2); pending[1].resolve(null); await flush(); cleanup();
});
test('projects: older configurations still render only one Finder button per row', () => {
  const f = fixture({ config: {
    projects: [{ id: 'p1', name: 'Project 1', tags: [], apps: ['cursor'] }],
    apps: [{ id: 'cursor', name: 'Cursor' }],
  } });
  const cleanup = projects.mount(f.host, f);
  const buttons = all(one(f.host, 'project'), 'ghost-button');
  assert.deepEqual(buttons.map(button => button.textContent), ['访达']);
  cleanup();
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
  f.store.set({ config: { projects: [config.projects[1]] } });
  assert.equal(f.store.get('selectedProject'), null); assert.equal(all(f.host, 'project').length, 1);
  request.reject(new Error('failed')); await flush();
  assert.equal(one(one(f.host, 'card-head'), 'card-meta').textContent, ''); assert.equal(f.timers.size, 0);
  oldButton.emit('click'); assert.equal(f.calls.length, 1); cleanup();
});
test('projects: untrusted labels stay text, scroll hints update, cleanup cancels observers/listeners/replies', async () => {
  const request = deferred(); const f = fixture({ config: { projects: [{ ...config.projects[0], name: '<img src=x>', tags: ['<b>tag</b>'] }] } }, () => request.promise);
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

const inputOf = f => one(f.host, 'project-add').children.find(node => node.tagName === 'INPUT');
const metaOf = f => one(one(f.host, 'card-head'), 'card-meta');
const fireTimers = f => {
  for (const [id, timer] of [...f.timers]) { f.timers.delete(id); timer.callback(); }
};

test('projects: M7 DOM matches input/drop/remove semantics without starting timers', () => {
  const f = fixture({ config }); const cleanup = projects.mount(f.host, f);
  const input = inputOf(f), card = one(f.host, 'projects-card');
  assert.equal(card.getAttribute('data-drop'), 'projects');
  assert.equal(input.type, 'text');
  assert.equal(input.placeholder, '粘贴文件夹路径，或把文件夹拖进来');
  assert.equal(input.getAttribute('spellcheck'), 'false');
  assert.equal(input.getAttribute('autocomplete'), 'off');
  assert.equal(one(f.host, 'project-drop').getAttribute('aria-hidden'), 'true');
  assert.equal(one(f.host, 'project-drop').textContent, '松开，添加为项目');
  const remove = one(f.host, 'project-remove');
  assert.equal(remove.title, '从列表移除（不会删除文件夹）');
  assert.equal(remove.getAttribute('aria-label'), '移除 Project 1');
  assert.equal(remove.children[0].tagName, 'SVG');
  assert.equal(f.timers.size, 0); cleanup();
});

test('projects: add trims input, ignores empty/composing/repeated pending Enter and waits for config push', async () => {
  const request = deferred(); const f = fixture({ config }, () => request.promise);
  const cleanup = projects.mount(f.host, f); const input = inputOf(f);
  input.value = '  '; input.emit('keydown', { key: 'Enter' });
  input.value = '  ~/My App  ';
  input.emit('keydown', { key: 'Enter', isComposing: true });
  input.emit('keydown', { key: 'Enter', keyCode: 229 });
  input.emit('keydown', { key: 'Escape' });
  assert.equal(f.calls.length, 0);
  assert.equal(input.emit('keydown', { key: 'Enter' }).defaultPrevented, true);
  input.emit('keydown', { key: 'Enter' });
  assert.deepEqual(f.calls, [{ action: 'addProject', payload: { path: '~/My App' } }]);
  const added = { id: 'my-app', name: 'My App', tags: [], hasReminders: false };
  request.resolve(added); await flush();
  assert.equal(input.value, '');
  assert.equal(metaOf(f).textContent, '已添加「My App」');
  assert.equal(all(f.host, 'project').length, 2);
  assert.equal(f.store.get('config'), config);
  const list = one(f.host, 'project-list'); list.scrollTop = 0;
  f.store.set({ config: { ...config, projects: [...config.projects, added] } });
  assert.equal(all(f.host, 'project').length, 3);
  assert.equal(list.scrollTop, list.scrollHeight);
  assert.equal(metaOf(f).textContent, '已添加「My App」');
  fireTimers(f); assert.equal(metaOf(f).textContent, ''); cleanup();
});

for (const [code, text] of [
  ['not-found', '找不到这个文件夹'], ['not-directory', '这不是文件夹'],
  ['outside-home', '只能添加个人文件夹（~）里的文件夹'], ['duplicate', '这个文件夹已经是项目了'],
  ['failed', '没能添加，请再试一次'],
]) test(`projects: add ${code} shows approved hint, editing or later success clears it`, async () => {
  let fail = true;
  const f = fixture({ config }, async () => {
    if (fail) throw Object.assign(new Error(code), { code });
    return { id: 'new', name: '<new>' };
  });
  const cleanup = projects.mount(f.host, f); const input = inputOf(f), hint = one(f.host, 'project-hint');
  input.value = '~/new'; input.emit('keydown', { key: 'Enter' }); await flush();
  assert.equal(hint.textContent, text); assert.ok(hint.classList.contains('error')); assert.equal(input.value, '~/new');
  input.emit('input'); assert.equal(hint.textContent, ''); assert.ok(!hint.classList.contains('error'));
  input.emit('keydown', { key: 'Enter' }); await flush();
  fail = false; input.emit('keydown', { key: 'Enter' }); await flush();
  assert.equal(hint.textContent, ''); assert.equal(input.value, '');
  assert.equal(metaOf(f).textContent, '已添加「<new>」'); assert.equal(metaOf(f).children.length, 0);
  cleanup(); assert.equal(f.timers.size, 0);
});

test('projects: removal needs two clicks within three seconds, one confirmation at a time, never selects row', async () => {
  const request = deferred(); const f = fixture({ config, selectedProject: 'p1' }, () => request.promise);
  const cleanup = projects.mount(f.host, f); const [first, second] = all(f.host, 'project-remove');
  first.emit('click'); assert.equal(first.textContent, '移除？'); assert.ok(first.classList.contains('confirm'));
  const stale = [...f.timers.values()][0]; assert.equal(stale.delay, 3000);
  second.emit('click'); assert.ok(!first.classList.contains('confirm')); assert.equal(first.children[0].tagName, 'SVG');
  assert.ok(second.classList.contains('confirm')); assert.equal(f.timers.size, 1);
  stale.callback(); assert.ok(second.classList.contains('confirm'));
  fireTimers(f); assert.ok(!second.classList.contains('confirm')); assert.equal(f.calls.length, 0);
  second.emit('click'); second.emit('click'); second.emit('click');
  assert.deepEqual(f.calls, [{ action: 'removeProject', payload: { projectId: 'p2' } }]);
  assert.equal(f.store.get('selectedProject'), 'p1');
  request.resolve(null); await flush();
  assert.equal(metaOf(f).textContent, '已移除「Project 2」，文件夹没有动');
  assert.equal(all(f.host, 'project').length, 2, 'reply alone must not mutate config');
  f.store.set({ config: { ...config, projects: [] } });
  assert.equal(f.store.get('selectedProject'), null);
  assert.equal(metaOf(f).textContent, '已移除「Project 2」，文件夹没有动');
  fireTimers(f); assert.equal(metaOf(f).textContent, ''); cleanup();
});

test('projects: remove failure resets confirmation and displays a three-second status', async () => {
  const f = fixture({ config }, async () => { throw new Error('failed'); });
  const cleanup = projects.mount(f.host, f); const remove = one(f.host, 'project-remove');
  remove.emit('click'); remove.emit('click'); await flush();
  assert.equal(metaOf(f).textContent, '没能移除'); assert.ok(!remove.classList.contains('confirm'));
  assert.equal(all(f.host, 'project').length, 2);
  fireTimers(f); assert.equal(metaOf(f).textContent, '');
  remove.emit('click'); assert.ok(remove.classList.contains('confirm')); cleanup(); assert.equal(f.timers.size, 0);
});

test('projects: config rerender cancels confirmation and pending removal stays deduplicated across renders', async () => {
  const request = deferred(); const f = fixture({ config }, () => request.promise);
  const cleanup = projects.mount(f.host, f); let remove = one(f.host, 'project-remove');
  remove.emit('click'); f.store.set({ config: structuredClone(config) });
  assert.equal(f.timers.size, 0); remove.emit('click'); assert.equal(f.calls.length, 0);
  remove = one(f.host, 'project-remove'); remove.emit('click'); remove.emit('click');
  f.store.set({ config: structuredClone(config) });
  remove = one(f.host, 'project-remove'); remove.emit('click'); remove.emit('click');
  assert.equal(f.calls.length, 1);
  request.resolve(null); await flush(); cleanup();
});

test('projects: drop hover and partial results, identical pushes each restart feedback even with same timestamp', () => {
  const f = fixture({ config }); const cleanup = projects.mount(f.host, f);
  const card = one(f.host, 'projects-card'), hint = one(f.host, 'project-hint'), input = inputOf(f);
  applyEvent(f.store, { event: 'projectDrop', over: true, result: null });
  assert.ok(card.classList.contains('drop-target'));
  input.value = '~/pending';
  const event = { event: 'projectDrop', over: false, result: { added: [{ id: 'p1', name: 'Project 1' }], error: null } };
  applyEvent(f.store, event, () => 1);
  assert.ok(!card.classList.contains('drop-target')); assert.equal(input.value, '');
  assert.equal(metaOf(f).textContent, '已添加「Project 1」');
  assert.equal(one(f.host, 'project-list').scrollTop, one(f.host, 'project-list').scrollHeight);
  const old = [...f.timers.values()][0]; fireTimers(f); assert.equal(metaOf(f).textContent, '');
  applyEvent(f.store, event, () => 1); assert.equal(metaOf(f).textContent, '已添加「Project 1」');
  old.callback(); assert.equal(metaOf(f).textContent, '已添加「Project 1」');
  applyEvent(f.store, { event: 'projectDrop', over: false, result: { added: [{ id: 'p1', name: 'One' }, { id: 'p2', name: 'Two' }], error: 'duplicate' } });
  assert.equal(metaOf(f).textContent, '已添加 2 个项目'); assert.equal(hint.textContent, '这个文件夹已经是项目了');
  assert.ok(hint.classList.contains('error'));
  applyEvent(f.store, { event: 'projectDrop', over: false, result: { added: [], error: 'not-found' } });
  assert.equal(hint.textContent, '找不到这个文件夹');
  cleanup(); assert.equal(f.timers.size, 0);
  const again = projects.mount(f.host.ownerDocument.createElement('section'), f);
  assert.equal(f.timers.size, 0, 'mount must not replay a stale one-shot result'); again();
});

test('projects: cleanup removes input/drop/confirmation handlers and late add/remove replies do not touch UI', async () => {
  const request = deferred(); const f = fixture({ config }, () => request.promise);
  const cleanup = projects.mount(f.host, f); const input = inputOf(f), remove = one(f.host, 'project-remove');
  input.value = '~/new'; input.emit('keydown', { key: 'Enter' }); remove.emit('click'); remove.emit('click');
  all(f.host, 'project-remove')[1].emit('click');
  cleanup(); cleanup(); assert.equal(f.timers.size, 0);
  const before = f.host.textContent;
  request.resolve({ id: 'new', name: 'New' }); await flush();
  input.emit('keydown', { key: 'Enter' }); input.emit('input'); remove.emit('click');
  applyEvent(f.store, { event: 'projectDrop', over: true, result: null });
  assert.equal(f.calls.length, 2); assert.equal(f.host.textContent, before); assert.equal(f.timers.size, 0);
  assert.equal(input.listeners.get('keydown').size, 0); assert.equal(input.listeners.get('input').size, 0);
  assert.ok(!one(f.host, 'projects-card').classList.contains('drop-target'));
});

test('projects: real bridge/mock pushes before add/remove replies and keeps selection/todo routing consistent', async () => {
  const f = fixture();
  const jobs = new Map(); let next = 0;
  const mock = createMock({ timers: {
    setInterval(fn) { jobs.set(++next, fn); return next; },
    clearInterval(id) { jobs.delete(id); },
  } });
  const bridge = createBridge(f.store, { target: {}, mock });
  await bridge.start();
  const cleanup = projects.mount(f.host, { store: f.store, bridge });
  const input = inputOf(f), list = one(f.host, 'project-list');
  input.value = '~/Desktop/test'; input.emit('keydown', { key: 'Enter' }); await flush();
  assert.equal(all(f.host, 'project').length, 7);
  assert.equal(metaOf(f).textContent, '已添加「test」');
  assert.equal(list.scrollTop, list.scrollHeight);
  const first = all(f.host, 'project')[0]; first.emit('click');
  assert.equal(f.store.get('selectedProject'), 'desktop-shell');
  const remove = one(first, 'project-remove'); remove.emit('click'); remove.emit('click'); await flush();
  assert.equal(all(f.host, 'project').length, 6);
  assert.equal(f.store.get('selectedProject'), null);
  assert.equal(metaOf(f).textContent, '已移除「DesktopShell」，文件夹没有动');
  assert.ok(f.store.get('todos').filter(todo => ['t1', 't2', 't12', 't13'].includes(todo.id)).every(todo => todo.projectId === null));
  await mock.dropFolders(['New One', 'New Two', 'test']);
  assert.equal(all(f.host, 'project').length, 8);
  assert.equal(metaOf(f).textContent, '已添加 2 个项目');
  assert.equal(one(f.host, 'project-hint').textContent, '这个文件夹已经是项目了');
  assert.ok(!one(f.host, 'projects-card').classList.contains('drop-target'));
  cleanup(); mock.stop(); assert.equal(jobs.size, 0); assert.equal(f.timers.size, 0);
});
