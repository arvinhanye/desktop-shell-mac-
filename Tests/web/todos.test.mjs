import { test } from 'node:test';
import assert from 'node:assert/strict';
import todosWidget, { dueLabel, visibleTodos, accessView, graphemeCount, scopeText, hintText } from '../../web/widgets/todos.js';
import { createStore, initialState } from '../../web/js/store.js';

const now = new Date(2026, 9, 18, 12, 30, 59).getTime();
const dueCases = [
  [null, null],
  [{ date: '2026-10-18', time: null }, { text: '今天', overdue: false }],
  [{ date: '2026-10-19', time: null }, { text: '明天', overdue: false }],
  [{ date: '2026-10-17', time: null }, { text: '昨天', overdue: true }],
  [{ date: '2026-11-02', time: '09:05' }, { text: '11月2日 09:05', overdue: false }],
  [{ date: '2026-09-30', time: '23:59' }, { text: '9月30日 23:59', overdue: true }],
  [{ date: '2026-10-18', time: '12:29' }, { text: '今天 12:29', overdue: true }],
  [{ date: '2026-10-18', time: '12:30' }, { text: '今天 12:30', overdue: false }],
  [{ date: '2026-10-18', time: '12:31' }, { text: '今天 12:31', overdue: false }],
  [{ date: '2026-10-19', time: '00:00' }, { text: '明天 00:00', overdue: false }],
];
for (const [due, expected] of dueCases) {
  test(`todos: local due label ${JSON.stringify(due)}`, () => assert.deepEqual(dueLabel(due, now), expected));
}
for (const [base, date, text, overdue] of [
  [[2026, 0, 31, 23, 59], '2026-02-01', '明天', false],
  [[2026, 11, 31, 23, 59], '2027-01-01', '明天', false],
  [[2027, 0, 1, 0, 0], '2026-12-31', '昨天', true],
  [[2026, 2, 8, 23, 59], '2026-03-09', '明天', false],
  [[2026, 10, 1, 0, 0], '2026-11-02', '明天', false],
]) {
  test(`todos: local calendar boundaries ${base.join('/')} to ${date}`, () => {
    assert.deepEqual(dueLabel({ date, time: null }, new Date(...base)), { text, overdue });
  });
}

const items = [
  { id: 'a', text: 'first', done: false, projectId: 'p1', due: { date: '2026-10-18', time: '12:30' } },
  { id: 'b', text: 'second', done: false, projectId: null, due: null },
  { id: 'c', text: 'third', done: false, projectId: 'p1', due: { date: '2026-10-19', time: null } },
  { id: 'd', text: 'done', done: true, projectId: 'p1', due: { date: '2026-10-17', time: null } },
  { id: 'e', text: 'also done', done: true, projectId: null, due: null },
];
for (const [selected, open, done] of [[null, ['a', 'b', 'c'], ['d', 'e']], ['p1', ['a', 'c'], ['d']], ['p2', [], []]]) {
  test(`todos: selection ${selected} filters without changing order or source`, () => {
    const source = structuredClone(items), before = structuredClone(source);
    const actual = visibleTodos(source, selected);
    assert.deepEqual(actual.open.map(item => item.id), open);
    assert.deepEqual(actual.done.map(item => item.id), done);
    assert.deepEqual(source, before);
  });
}
const accessCases = [
  ['granted', { canEdit: true, title: '', message: '' }],
  ['unknown', { canEdit: false, title: '', message: '' }],
  ['notDetermined', { canEdit: false, title: '正在等待提醒事项权限', message: '在弹出的对话框里点「允许」' }],
  ...['denied', 'restricted', 'writeOnly'].map(access => [access, { canEdit: false, title: '还不能读取提醒事项', message: '到「系统设置 → 隐私与安全性 → 提醒事项」里允许 DesktopShell' }]),
];
for (const [access, expected] of accessCases) {
  test(`todos: permission ${access} selects the appropriate view`, () => assert.deepEqual(accessView(access), expected));
}
for (const [text, count] of [['', 0], ['你好', 2], ['hello', 5], ['👨‍👩‍👧‍👦👍🏽🇨🇳', 3], ['e\u0301', 1], ['好'.repeat(500), 500], ['👨‍👩‍👧‍👦'.repeat(501), 501]]) {
  test(`todos: count ${count} graphemes, not UTF-16 units`, () => assert.equal(graphemeCount(text), count));
}
const config = { projects: [{ id: 'p1', name: 'Project 1', hasReminders: true }, { id: 'p2', name: 'Project 2', hasReminders: false }] };
for (const [project, scope, hint] of [
  [null, '全部列表', ''],
  [config.projects[0], '只看「Project 1」', ''],
  [config.projects[1], '只看「Project 2」', '这个项目没有对应的提醒事项列表，新增的提醒会放进默认列表'],
]) {
  test(`todos: scope and default-list hint for ${project?.id ?? 'all'}`, () => {
    assert.equal(scopeText(project), scope);
    assert.equal(hintText(project), hint);
  });
}

// Lightweight DOM boundary double; the widget, store and scroll helper remain real.
function fixture(initial = {}, send = async () => null) {
  const timers = new Map(), observers = [], calls = [];
  let nextTimer = 0;
  class Element {
    constructor(tag) { this.tagName = tag.toUpperCase(); this.children = []; this.parentElement = null; this.ownerDocument = doc; this.className = ''; this.attributes = {}; this.listeners = new Map(); this.style = {}; this._text = ''; this.value = ''; this.scrollTop = 0; this.clientHeight = 100; this.scrollHeight = 300; }
    append(...children) { for (const child of children) { child.parentElement = this; this.children.push(child); } }
    replaceChildren(...children) { for (const child of this.children) child.parentElement = null; this.children = []; this._text = ''; this.scrollTop = 0; this.append(...children); }
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
  const doc = { defaultView: win, createElement: tag => new Element(tag), createElementNS: (_, tag) => new Element(tag), createTextNode: text => { const node = new Element('#text'); node.textContent = text; return node; } };
  const host = doc.createElement('section');
  const store = createStore({ ...initialState, ...initial });
  const bridge = { send(action, payload) { calls.push({ action, payload }); return send(action, payload); } };
  return { host, store, bridge, timers, observers, calls };
}
const all = (root, cls) => [root, ...root.children.flatMap(child => all(child, cls))].filter(element => element.className.split(' ').includes(cls));
const one = (root, cls) => { const found = all(root, cls); assert.ok(found.length > 0, `missing .${cls}`); return found[0]; };
const flush = () => new Promise(resolve => setImmediate(resolve));
const deferred = () => { let resolve, reject; const promise = new Promise((yes, no) => { resolve = yes; reject = no; }); return { promise, resolve, reject }; };

const byTag = (root, tag) => [root, ...root.children.flatMap(child => byTag(child, tag))].filter(node => node.tagName === tag.toUpperCase());
function mounted(initial = {}, send) {
  const f = fixture({ config, todos: structuredClone(items), todosAccess: 'granted', now, ...initial }, send);
  f.cleanup = todosWidget.mount(f.host, f);
  assert.equal(typeof f.cleanup, 'function', 'mount returns its lifecycle cleanup');
  f.list = one(f.host, 'todo-list'); f.input = byTag(f.host, 'input')[0];
  f.hint = one(f.host, 'todo-hint');
  return f;
}
const rowWith = (f, text) => {
  const row = all(f.host, 'todo').find(node => one(node, 'todo-text').textContent === text);
  assert.ok(row, `missing reminder ${text}`); return row;
};
const clickTodo = (f, text) => one(rowWith(f, text), 'todo-check').emit('click');
const enter = (f, text, detail = {}) => { f.input.value = text; return f.input.emit('keydown', { key: 'Enter', ...detail }); };

test('todos: renders the approved card, open/done groups, due labels and inert user text', () => {
  const f = mounted({ todos: [...items, { id: 'x', text: '<img src=x onerror=bad()>', done: false, projectId: null, due: null }] });
  assert.equal(f.host.getAttribute('aria-label'), '待办');
  assert.ok(one(f.host, 'todos-card').classList.contains('card'));
  assert.equal(one(f.host, 'card-title').textContent, '待办');
  assert.equal(one(f.host, 'card-meta').textContent, '全部列表');
  assert.equal(f.input.placeholder, '添加提醒，按回车保存'); assert.equal(f.input.type, 'text');
  assert.equal(f.list.tagName, 'UL'); assert.ok(f.list.classList.contains('scroll-list'));
  assert.deepEqual(f.list.children.map(node => node.className), ['todo', 'todo', 'todo', 'todo', 'todo-section', 'todo done', 'todo done']);
  assert.equal(one(f.host, 'todo-section').textContent, '今天完成');
  assert.equal(one(rowWith(f, 'first'), 'todo-due').textContent, '今天 12:30');
  const done = rowWith(f, 'done'); assert.equal(all(done, 'todo-due').length, 0);
  assert.equal(one(done, 'todo-check').getAttribute('aria-label'), '取消完成');
  assert.equal(one(rowWith(f, 'first'), 'todo-check').getAttribute('aria-label'), '完成');
  const svg = byTag(done, 'svg')[0]; assert.equal(svg.getAttribute('aria-hidden'), 'true');
  assert.equal(byTag(svg, 'path')[0].getAttribute('d'), 'M1.5 5.2 4 7.6 8.6 2.6');
  assert.equal(one(rowWith(f, '<img src=x onerror=bad()>'), 'todo-text').children.length, 0);
  f.cleanup();
});
test('todos: permission transitions hide input and remove reminders without emitting requests', () => {
  const f = mounted();
  for (const [access, expected] of accessCases) {
    f.store.set({ todosAccess: access });
    assert.equal(one(f.host, 'todo-add').hidden, !expected.canEdit);
    assert.equal(f.input.disabled, !expected.canEdit);
    if (expected.canEdit) assert.equal(all(f.host, 'todo').length, 5);
    else {
      assert.equal(all(f.host, 'todo').length, 0);
      assert.equal(f.list.textContent, expected.title + expected.message);
      assert.equal(all(f.host, 'todo-denied').length, expected.title ? 1 : 0);
      enter(f, 'hidden input'); assert.equal(f.calls.length, 0);
    }
  }
  f.cleanup();
});
test('todos: project/config changes update filtering, scope and no-list hint', () => {
  const f = mounted(); f.store.set({ selectedProject: 'p1' });
  assert.deepEqual(all(f.host, 'todo-text').map(node => node.textContent), ['first', 'third', 'done']);
  assert.equal(one(f.host, 'card-meta').textContent, '只看「Project 1」'); assert.equal(f.hint.textContent, '');
  f.store.set({ selectedProject: 'p2' });
  assert.equal(f.list.textContent, '没有待办。在上面输入一条，按回车保存');
  assert.equal(f.hint.textContent, '这个项目没有对应的提醒事项列表，新增的提醒会放进默认列表');
  f.store.set({ config: { projects: [{ id: 'p2', name: '<b>renamed</b>', hasReminders: true }] } });
  assert.equal(one(f.host, 'card-meta').textContent, '只看「<b>renamed</b>」');
  assert.equal(one(f.host, 'card-meta').children.length, 0); assert.equal(f.hint.textContent, '');
  f.store.set({ selectedProject: null }); assert.equal(all(f.host, 'todo').length, 5); f.cleanup();
});
test('todos: each minute and midnight refresh due status, preserving scroll and input identity', () => {
  const f = mounted(); const input = f.input;
  input.value = '正在拼音输入'; f.list.scrollTop = 70;
  f.store.set({ now: new Date(2026, 9, 18, 12, 31).getTime() });
  assert.equal(one(rowWith(f, 'first'), 'todo-due').textContent, '已过期 今天 12:30');
  assert.ok(one(rowWith(f, 'first'), 'todo-due').classList.contains('overdue'));
  f.store.set({ now: new Date(2026, 9, 19, 0, 0).getTime() });
  assert.equal(one(rowWith(f, 'first'), 'todo-due').textContent, '已过期 昨天 12:30');
  assert.equal(one(rowWith(f, 'third'), 'todo-due').textContent, '今天');
  f.store.set({ todos: [...items, { id: 'z', text: 'new push', done: false, projectId: null, due: null }] });
  assert.equal(byTag(f.host, 'input')[0], input); assert.equal(input.value, '正在拼音输入');
  assert.equal(f.list.scrollTop, 70); f.cleanup();
});
test('todos: null now uses the current local calendar before the first clock update', () => {
  const current = new Date();
  const date = `${current.getFullYear()}-${String(current.getMonth() + 1).padStart(2, '0')}-${String(current.getDate()).padStart(2, '0')}`;
  const f = mounted({ now: null, todos: [{ ...items[0], due: { date, time: null } }] });
  assert.equal(one(f.host, 'todo-due').textContent, '今天'); f.cleanup();
});
test('todos: pending checkbox changes are immediate, per-id and survive pushes/filter changes', async () => {
  const requests = []; const f = mounted({}, () => { const request = deferred(); requests.push(request); return request.promise; });
  const original = structuredClone(f.store.get('todos'));
  clickTodo(f, 'first'); assert.ok(rowWith(f, 'first').classList.contains('done'));
  clickTodo(f, 'first'); clickTodo(f, 'second');
  assert.deepEqual(f.calls, [{ action: 'setTodoDone', payload: { todoId: 'a', done: true } }, { action: 'setTodoDone', payload: { todoId: 'b', done: true } }]);
  f.store.set({ selectedProject: 'p2' }); f.store.set({ todos: structuredClone(items), selectedProject: null });
  assert.ok(rowWith(f, 'first').classList.contains('done')); clickTodo(f, 'first'); assert.equal(f.calls.length, 2);
  assert.deepEqual(f.store.get('todos'), original, 'optimistic state never mutates shared reminders');
  f.store.set({ todos: items.map(todo => ['a', 'b'].includes(todo.id) ? { ...todo, done: true } : todo) });
  requests.forEach(request => request.resolve(null)); await flush();
  assert.ok(rowWith(f, 'first').classList.contains('done')); assert.equal(f.hint.textContent, '');
  clickTodo(f, 'first'); assert.deepEqual(f.calls[2], { action: 'setTodoDone', payload: { todoId: 'a', done: false } });
  assert.ok(!rowWith(f, 'first').classList.contains('done')); requests[2].resolve(null); await flush(); f.cleanup();
});
test('todos: failed checkbox request rolls back, reports error and can be retried', async () => {
  const requests = []; const f = mounted({}, () => { const request = deferred(); requests.push(request); return request.promise; });
  clickTodo(f, 'done'); assert.ok(!rowWith(f, 'done').classList.contains('done'));
  requests[0].reject(new Error('failed')); await flush();
  assert.ok(rowWith(f, 'done').classList.contains('done'));
  assert.equal(f.hint.textContent, '没能更新这条提醒，请再试一次');
  clickTodo(f, 'done'); assert.equal(f.calls.length, 2); requests[1].resolve(null); await flush();
  assert.equal(f.hint.textContent, ''); f.cleanup();
});
test('todos: native success reply before push retains the checked state and allows an inverse click', async () => {
  const requests = []; const f = mounted({}, () => { const request = deferred(); requests.push(request); return request.promise; });
  clickTodo(f, 'first'); requests[0].resolve(null); await flush();
  assert.ok(rowWith(f, 'first').classList.contains('done'), 'successful reply must not roll back while awaiting push');
  f.store.set({ now: now + 60000 }); assert.ok(rowWith(f, 'first').classList.contains('done'));
  clickTodo(f, 'first');
  assert.deepEqual(f.calls.map(call => call.payload), [{ todoId: 'a', done: true }, { todoId: 'a', done: false }]);
  assert.ok(!rowWith(f, 'first').classList.contains('done'));
  // The delayed push for the first request must not override the newer pending toggle.
  f.store.set({ todos: items.map(todo => todo.id === 'a' ? { ...todo, done: true } : todo) });
  assert.ok(!rowWith(f, 'first').classList.contains('done'));
  requests[1].resolve(null); await flush(); assert.ok(!rowWith(f, 'first').classList.contains('done'));
  f.store.set({ todos: structuredClone(items) });
  assert.ok(!rowWith(f, 'first').classList.contains('done'));
  // Once acknowledged, external changes become authoritative again.
  f.store.set({ todos: items.map(todo => todo.id === 'a' ? { ...todo, done: true } : todo) });
  assert.ok(rowWith(f, 'first').classList.contains('done')); f.cleanup();
});
test('todos: confirmed optimistic state yields to matching push and then external changes', async () => {
  const f = mounted(); clickTodo(f, 'first'); await flush();
  assert.ok(rowWith(f, 'first').classList.contains('done'));
  f.store.set({ todos: items.map(todo => todo.id === 'a' ? { ...todo, done: true } : todo) });
  f.store.set({ todos: structuredClone(items) });
  assert.ok(!rowWith(f, 'first').classList.contains('done')); f.cleanup();
});
test('todos: a later authoritative push may supersede a successful local toggle', async () => {
  const f = mounted(); clickTodo(f, 'first'); await flush();
  assert.ok(rowWith(f, 'first').classList.contains('done'));
  // Another client may already have undone this action before the first push arrives.
  f.store.set({ todos: structuredClone(items) });
  assert.ok(!rowWith(f, 'first').classList.contains('done'), 'a settled override must not hide external changes forever');
  f.cleanup();
});
test('todos: failed inverse toggle restores the previous successful state still awaiting push', async () => {
  let fails = false;
  const f = mounted({}, async () => { if (fails) throw new Error('failed'); return null; });
  clickTodo(f, 'first'); await flush();
  assert.ok(rowWith(f, 'first').classList.contains('done'));
  fails = true; clickTodo(f, 'first'); await flush();
  assert.ok(rowWith(f, 'first').classList.contains('done'));
  assert.equal(f.hint.textContent, '没能更新这条提醒，请再试一次');
  f.store.set({ todos: items.map(todo => todo.id === 'a' ? { ...todo, done: true } : todo) });
  f.store.set({ todos: structuredClone(items) });
  assert.ok(!rowWith(f, 'first').classList.contains('done')); f.cleanup();
});
test('todos: late checkbox replies use the latest store, never resurrect a removed reminder', async () => {
  const request = deferred(); const f = mounted({}, () => request.promise); clickTodo(f, 'first');
  f.store.set({ todos: items.filter(todo => todo.id !== 'a') });
  request.reject(new Error('not-found')); await flush();
  assert.equal(all(f.host, 'todo-text').some(node => node.textContent === 'first'), false); f.cleanup();
});
test('todos: failed inverse toggle yields to a fresh snapshot received during the request', async () => {
  const requests = []; const f = mounted({}, () => { const request = deferred(); requests.push(request); return request.promise; });
  clickTodo(f, 'first'); requests[0].resolve(null); await flush();
  assert.ok(rowWith(f, 'first').classList.contains('done'));
  clickTodo(f, 'first');
  f.store.set({ todos: structuredClone(items) });
  requests[1].reject(new Error('failed')); await flush();
  assert.ok(!rowWith(f, 'first').classList.contains('done'), 'failure must not restore an override older than the current snapshot');
  assert.equal(f.hint.textContent, '没能更新这条提醒，请再试一次'); f.cleanup();
});
test('todos: Enter ignores IME confirmation, whitespace and unrelated keys', () => {
  const f = mounted();
  assert.equal(enter(f, '拼音', { isComposing: true }).defaultPrevented, false);
  enter(f, ' \n\t ');
  for (const key of ['Escape', 'a', 'Tab']) assert.equal(f.input.emit('keydown', { key }).defaultPrevented, false);
  assert.equal(f.calls.length, 0); f.cleanup();
});
test('todos: validates trimmed graphemes at 500/501 and clears error on input change', async () => {
  const f = mounted({ selectedProject: 'p2' });
  enter(f, '👨‍👩‍👧‍👦'.repeat(501)); assert.equal(f.calls.length, 0); assert.equal(f.hint.textContent, '最多 500 个字');
  f.input.emit('input'); assert.equal(f.hint.textContent, '这个项目没有对应的提醒事项列表，新增的提醒会放进默认列表');
  enter(f, `  ${'e\u0301'.repeat(500)}  `); await flush();
  assert.deepEqual(f.calls, [{ action: 'addTodo', payload: { text: 'e\u0301'.repeat(500), projectId: 'p2' } }]);
  assert.equal(f.input.value, ''); f.cleanup();
});
test('todos: add deduplicates while pending, trims text and waits for pushed rows', async () => {
  const request = deferred(); const f = mounted({}, () => request.promise);
  enter(f, '  新提醒  '); enter(f, '  新提醒  ');
  assert.deepEqual(f.calls, [{ action: 'addTodo', payload: { text: '新提醒' } }]);
  assert.equal(all(f.host, 'todo').length, 5);
  request.resolve({ id: 'new', text: '新提醒', done: false, projectId: null, due: null }); await flush();
  assert.equal(f.input.value, ''); assert.equal(all(f.host, 'todo').length, 5);
  f.store.set({ todos: [...items, { id: 'new', text: '新提醒', done: false, projectId: null, due: null }] });
  assert.equal(all(f.host, 'todo').length, 6); f.cleanup();
});
test('todos: add captures its project, preserves edits during a request and allows the next add', async () => {
  const requests = []; const f = mounted({ selectedProject: 'p1' }, () => { const request = deferred(); requests.push(request); return request.promise; });
  enter(f, 'first draft'); f.input.value = 'next draft'; f.input.emit('input'); f.store.set({ selectedProject: 'p2' });
  requests[0].resolve(null); await flush(); assert.equal(f.input.value, 'next draft');
  enter(f, 'next draft');
  assert.deepEqual(f.calls, [{ action: 'addTodo', payload: { text: 'first draft', projectId: 'p1' } }, { action: 'addTodo', payload: { text: 'next draft', projectId: 'p2' } }]);
  requests[1].resolve(null); await flush(); assert.equal(f.input.value, ''); f.cleanup();
});
test('todos: failed add preserves text; successful retry restores the default-list hint', async () => {
  let fails = true; const f = mounted({ selectedProject: 'p2' }, async () => { if (fails) throw new Error('failed'); return null; });
  enter(f, '保留这段文字'); await flush();
  assert.equal(f.input.value, '保留这段文字'); assert.equal(f.hint.textContent, '没能添加，请再试一次');
  f.store.set({ now: now + 60000 }); assert.equal(f.hint.textContent, '没能添加，请再试一次');
  fails = false; enter(f, '保留这段文字'); await flush();
  assert.equal(f.input.value, ''); assert.equal(f.hint.textContent, '这个项目没有对应的提醒事项列表，新增的提醒会放进默认列表'); f.cleanup();
});
test('todos: successful add also clears a checkbox error', async () => {
  const f = mounted({}, async action => { if (action === 'setTodoDone') throw new Error('failed'); return null; });
  clickTodo(f, 'first'); await flush(); assert.equal(f.hint.textContent, '没能更新这条提醒，请再试一次');
  enter(f, 'new'); await flush(); assert.equal(f.hint.textContent, ''); f.cleanup();
});
test('todos: cleanup disconnects scroll hints, listeners, subscriptions and pending callbacks', async () => {
  const requests = []; const f = mounted({}, () => { const request = deferred(); requests.push(request); return request.promise; });
  f.list.scrollTop = 200; f.list.emit('scroll'); assert.ok(f.list.classList.contains('more-above'));
  assert.ok(!f.list.classList.contains('more-below')); clickTodo(f, 'first'); enter(f, 'pending input');
  const button = one(rowWith(f, 'second'), 'todo-check'); f.cleanup(); f.cleanup();
  assert.ok(f.observers.every(observer => observer.disconnected));
  assert.equal(f.input.listeners.get('keydown').size, 0); assert.equal(f.input.listeners.get('input').size, 0);
  assert.equal(f.list.listeners.get('scroll').size, 0);
  const text = f.host.textContent;
  requests[0].reject(new Error('failed')); requests[1].resolve(null); await flush();
  f.store.set({ todos: [], todosAccess: 'denied', now: now + 60000, selectedProject: 'p2', config: null });
  button.emit('click'); enter(f, 'pending input');
  assert.equal(f.calls.length, 2); assert.equal(f.host.textContent, text); assert.equal(f.input.value, 'pending input');
});
