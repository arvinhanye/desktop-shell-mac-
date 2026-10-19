import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createStore, initialState } from '../../web/js/store.js';
import { createBridge, applyEvent } from '../../web/js/bridge.js';
import { createMock } from '../../web/js/mock.js';

const fresh = () => createStore(initialState);
const config = () => ({ character: { name: '爱弥斯' }, greetings: [], projects: [{ id: 'p', name: '项目' }], apps: [] });
const reply = () => ({ config: config(), media: { avatars: [], backgrounds: [] }, uiState: {} });
const stats = () => ({ battery: { level: 80, charging: false, onBattery: true }, cpu: 25, memory: { usedBytes: 512, totalBytes: 1024, percent: 50 } });
const todo = () => ({ id: 'a', text: '', done: false });
const now = () => 1234;

test('bridge: modes use injected/target native handler or mock; receive is installed synchronously', () => {
  for (const native of [undefined, null, {}, { postMessage: true }]) {
    const target = { shell: { previous: true } };
    const bridge = createBridge(fresh(), { target, native });
    assert.equal(bridge.mode, 'mock');
    assert.equal(typeof bridge.mock.handle, 'function');
    assert.equal(typeof target.shell.receive, 'function');
    assert.equal(target.shell.previous, undefined);
  }
  const native = { postMessage() {} };
  const target = { webkit: { messageHandlers: { shell: native } } };
  const bridge = createBridge(fresh(), { target });
  assert.equal(bridge.mode, 'native');
  assert.equal(bridge.mock, null);
  assert.equal(createBridge(fresh(), { target, native: null }).mode, 'mock');
});

test('bridge: send preserves native this/reply and action cannot be overridden by params', async () => {
  const expected = { result: 7 };
  const native = { postMessage(message) {
    assert.equal(this, native);
    assert.deepEqual(message, { projectId: 'p', action: 'openProject' });
    return Promise.resolve(expected);
  } };
  const bridge = createBridge(fresh(), { target: {}, native });
  assert.equal(await bridge.send('openProject', { action: 'launchApp', projectId: 'p' }), expected);
});

for (const [name, failure, code] of [
  ['sync exception', () => { throw new Error('untrusted'); }, 'untrusted'],
  ['promise rejection', () => Promise.reject(new Error('not-found')), 'not-found'],
  ['string rejection', () => Promise.reject('failed'), 'failed'],
  ['object without message', () => Promise.reject({ message: 7 }), '[object Object]'],
  ['null rejection', () => Promise.reject(null), 'null'],
]) {
  test(`bridge: ${name} becomes Error with code and one warning`, async t => {
    const warn = t.mock.method(console, 'warn', () => {});
    const bridge = createBridge(fresh(), { target: {}, native: { postMessage: failure } });
    const promise = bridge.send('launchApp');
    assert.ok(promise instanceof Promise);
    await assert.rejects(promise, error => error instanceof Error && error.message === code && error.code === code);
    assert.deepEqual(warn.mock.calls[0].arguments, [`bridge: launchApp 失败：${code}`]);
    assert.equal(warn.mock.callCount(), 1);
  });
}

test('bridge: startup sanitizes optional media/UI/project fields in one atomic store update', async () => {
  const s = fresh();
  const bridge = createBridge(s, { target: {}, native: { postMessage: () => ({
    config: config(),
    media: { avatars: [null, { id: 1, url: 'x' }, { id: '1', url: '/a.png' }], backgrounds: [{ id: 'b', url: 7 }] },
    uiState: { avatarId: 12, backgroundId: 'b', voiceEnabled: 'no' },
  }) } });
  let notifications = 0;
  s.subscribe('config', () => {
    notifications++;
    assert.equal(s.get('ready'), true);
    assert.deepEqual(s.get('ui'), { avatarId: null, backgroundId: 'b', voiceEnabled: true });
    assert.deepEqual(s.get('media'), { avatars: [{ id: '1', url: '/a.png' }], backgrounds: [], voices: [] });
  });
  await bridge.start();
  assert.equal(notifications, 1);
  assert.deepEqual(s.get('config').projects[0], { id: 'p', name: '项目', tags: [], apps: [], hasReminders: false });
});

test('bridge: optional malformed media/UI defaults; valid fields survive normalization', async () => {
  const s = fresh();
  const r = reply();
  r.config.projects = [{ id: 'p', tags: ['dev'], apps: ['cursor'], hasReminders: true }];
  r.media = { avatars: [{ id: 'a', url: '/a' }], backgrounds: null };
  r.uiState = { avatarId: 'a', backgroundId: null, voiceEnabled: false };
  await createBridge(s, { target: {}, native: { postMessage: () => r } }).start();
  assert.deepEqual(s.get('media'), { avatars: [], backgrounds: [], voices: [] });
  assert.deepEqual(s.get('ui'), { avatarId: 'a', backgroundId: null, voiceEnabled: false });
  assert.deepEqual(s.get('config').projects, r.config.projects);
});

for (const [label, response] of [
  ['legacy undefined', undefined], ['null', null], ['array', []], ['missing config', {}],
  ['invalid character', { config: { ...config(), character: { name: 1 } } }],
  ...['greetings', 'projects', 'apps'].map(key => [`invalid ${key}`, { config: { ...config(), [key]: null } }]),
]) {
  test(`bridge: start handles ${label}, marks ready and resolves instead of rejecting`, async t => {
    const error = t.mock.method(console, 'error', () => {});
    const s = fresh();
    const bridge = createBridge(s, { target: {}, native: { postMessage: () => response } });
    await bridge.start();
    assert.equal(s.get('ready'), true);
    assert.equal(s.get('config'), null);
    assert.equal(error.mock.callCount(), 1);
  });
}

test('bridge: rejected getConfig resolves startup after ready; repeated and reentrant start reuse one promise', async t => {
  t.mock.method(console, 'warn', () => {});
  t.mock.method(console, 'error', () => {});
  const s = fresh();
  let calls = 0;
  let settle;
  const bridge = createBridge(s, { target: {}, native: { postMessage() {
    calls++;
    return new Promise((resolve, reject) => { settle = reject; });
  } } });
  let reentrant;
  s.subscribe('ready', () => { reentrant = bridge.start(); });
  const first = bridge.start();
  assert.equal(first, bridge.start());
  await Promise.resolve();
  settle(new Error('failed'));
  await first;
  assert.equal(first, reentrant);
  assert.equal(first, bridge.start());
  assert.equal(calls, 1);
  assert.equal(s.get('ready'), true);
  assert.equal(s.get('config'), null);
});

test('bridge: real mock startup, replies and timer events all update store through installed receive', async () => {
  const jobs = new Map();
  const timers = { setInterval(fn, delay) { jobs.set(delay, fn); return delay; }, clearInterval(id) { jobs.delete(id); } };
  const mock = createMock({ timers, now: () => new Date(2026, 9, 17, 12).getTime(), random: () => 0.5 });
  const s = fresh();
  const target = {};
  const bridge = createBridge(s, { target, mock, now });
  try {
    const first = bridge.start();
    assert.equal(first, bridge.start());
    await first;
    assert.equal(bridge.mock, mock);
    assert.equal(s.get('config').character.name, '爱弥斯');
    assert.equal(s.get('ready'), true);
    assert.equal(s.get('media').backgrounds.length, 63);
    assert.equal(s.get('todosAccess'), 'granted');
    assert.equal(s.get('todos').length, 13);
    assert.deepEqual(s.get('safeArea'), { top: 25, right: 0, bottom: 80, left: 0 });
    jobs.get(33)();
    assert.equal(s.get('audioSpectrum').at, 1234);
    mock.setPaused(true);
    assert.equal(s.get('paused'), true);
    assert.equal(s.get('audioSpectrum'), null);
    const added = await bridge.send('addTodo', { text: 'new' });
    assert.equal(s.get('todos').at(-1).id, added.id);
    await bridge.send('setTodoDone', { todoId: added.id, done: true });
    assert.equal(s.get('todos').at(-1).done, true);
    await bridge.send('saveUiState', { avatarId: '1' });
    assert.equal(s.get('ui').avatarId, '1');
    mock.setTodosAccess('denied');
    assert.deepEqual(s.get('todos'), []);
    assert.equal(s.get('todosAccess'), 'denied');
  } finally { mock.stop(); }
  assert.equal(jobs.size, 0);
});

test('bridge: mock startup exception also resolves with ready, never rejects', async t => {
  t.mock.method(console, 'error', () => {});
  const s = fresh();
  const mock = { start() { throw new Error('failed'); }, handle() { assert.fail(); } };
  await createBridge(s, { target: {}, mock }).start();
  assert.equal(s.get('ready'), true);
});

const validEvents = [
  [{ event: 'safeArea', top: 1, right: 2, bottom: 3, left: 4 }, { safeArea: { top: 1, right: 2, bottom: 3, left: 4 } }],
  [{ event: 'paused', paused: true }, { paused: true, audioSpectrum: null }],
  [{ event: 'systemStats', ...stats() }, { systemStats: stats() }],
  [{ event: 'systemStats', ...stats(), battery: { charging: true, onBattery: false } }, { systemStats: { ...stats(), battery: { level: null, charging: true, onBattery: false } } }],
  [{ event: 'uiState' }, { ui: { avatarId: null, backgroundId: null, voiceEnabled: true } }],
  [{ event: 'uiState', avatarId: '12', backgroundId: null, voiceEnabled: false }, { ui: { avatarId: '12', backgroundId: null, voiceEnabled: false } }],
  [{ event: 'audioSpectrum', bands: [-1, 2, ...Array(10).fill(0.5)] }, { audioSpectrum: { bands: [0, 1, ...Array(10).fill(0.5)], at: 1234 } }],
  [{ event: 'todos', access: 'granted', items: [todo()] }, { todos: [{ ...todo(), projectId: null, due: null }], todosAccess: 'granted' }],
  [{ event: 'todos', access: 'granted', items: [{ ...todo(), projectId: 'p', due: { date: '2026-10-18', time: '09:00' } }] }, { todos: [{ ...todo(), projectId: 'p', due: { date: '2026-10-18', time: '09:00' } }], todosAccess: 'granted' }],
  ...['denied', 'notDetermined', 'restricted', 'writeOnly'].map(access => [{ event: 'todos', access, items: [] }, { todos: [], todosAccess: access }]),
];
for (const [index, [event, expected]] of validEvents.entries()) {
  test(`bridge applyEvent: valid ${event.event} case ${index + 1}`, () => {
    const s = fresh();
    applyEvent(s, event, now);
    for (const [key, value] of Object.entries(expected)) assert.deepEqual(s.get(key), value);
    if (event.event === 'audioSpectrum') assert.notEqual(s.get('audioSpectrum').bands, event.bands);
    if (event.event === 'todos') assert.notEqual(s.get('todos'), event.items);
  });
}

const invalidEvents = [
  null, 'x', {}, [], { event: 'unknown' },
  { event: 'safeArea', top: -1, right: 0, bottom: 0, left: 0 },
  { event: 'safeArea', top: Infinity, right: 0, bottom: 0, left: 0 },
  { event: 'paused', paused: 1 },
  { event: 'systemStats', ...stats(), cpu: NaN },
  { event: 'systemStats', ...stats(), cpu: 101 },
  { event: 'systemStats', ...stats(), battery: { level: 1.5, charging: false, onBattery: false } },
  { event: 'systemStats', ...stats(), battery: { level: 101, charging: false, onBattery: false } },
  { event: 'systemStats', ...stats(), battery: { level: null, charging: 1, onBattery: false } },
  { event: 'systemStats', ...stats(), memory: { usedBytes: -1, totalBytes: 100, percent: 1 } },
  { event: 'systemStats', ...stats(), memory: { usedBytes: 1, totalBytes: Infinity, percent: 1 } },
  { event: 'uiState', avatarId: 1 }, { event: 'uiState', voiceEnabled: null },
  { event: 'audioSpectrum', bands: [1] },
  { event: 'audioSpectrum', bands: [NaN, ...Array(11).fill(0)] },
  { event: 'audioSpectrum', bands: Array(12) },
  { event: 'todos', access: 'unknown', items: [] },
  { event: 'todos', access: 'granted', items: {} },
  { event: 'todos', access: 'granted', items: Array(501).fill(todo()) },
  { event: 'todos', access: 'granted', items: Array(2) },
  ...[
    null, { ...todo(), id: '' }, { ...todo(), text: 1 }, { ...todo(), done: 1 },
    { ...todo(), projectId: 1 }, { ...todo(), due: { date: '2026/10/18', time: null } },
    { ...todo(), due: { date: '2026-10-18', time: '9:00' } },
  ].map(item => ({ event: 'todos', access: 'granted', items: [todo(), item] })),
];
for (const [index, event] of invalidEvents.entries()) {
  test(`bridge applyEvent: invalid ${event?.event ?? 'event envelope'} case ${index + 1} warns and leaves all state unchanged`, t => {
    const warn = t.mock.method(console, 'warn', () => {});
    const s = fresh();
    const before = s.getState();
    applyEvent(s, event, now);
    assert.deepEqual(s.getState(), before);
    assert.equal(warn.mock.callCount(), 1);
    const name = typeof event?.event === 'string' ? event.event : '?';
    assert.deepEqual(warn.mock.calls[0].arguments, [`bridge: ignored invalid event ${name}`]);
  });
}

test('bridge: paused clears audio atomically; paused spectrum does not call now or update state', () => {
  const s = fresh();
  applyEvent(s, { event: 'audioSpectrum', bands: Array(12).fill(0.5) }, now);
  s.subscribe('paused', () => assert.equal(s.get('audioSpectrum'), null));
  applyEvent(s, { event: 'paused', paused: true }, now);
  const before = s.getState();
  applyEvent(s, { event: 'audioSpectrum', bands: Array(12).fill(1) }, () => assert.fail('timestamp during pause'));
  assert.deepEqual(s.getState(), before);
});

test('bridge: todos normalizes nullable due, commits access/items together and accepts the 500-item boundary', () => {
  const s = fresh();
  const events = [];
  s.subscribe('todos', value => events.push([value.length, s.get('todosAccess')]));
  const items = Array.from({ length: 500 }, (_, id) => ({ ...todo(), id: String(id), due: { date: '2026-10-18', time: null } }));
  applyEvent(s, { event: 'todos', access: 'granted', items }, now);
  assert.deepEqual(events, [[500, 'granted']]);
  assert.deepEqual(s.get('todos')[0].due, { date: '2026-10-18', time: null });
});

test('bridge: receive never throws for null, primitives, unknown objects or throwing accessors/proxies', t => {
  t.mock.method(console, 'warn', () => {});
  const target = {};
  const s = fresh();
  createBridge(s, { target, native: { postMessage() {} } });
  const revoked = Proxy.revocable({}, {}); revoked.revoke();
  for (const value of [null, 'x', {}, Symbol(), revoked.proxy, { get event() { throw Error('bad input'); } }]) {
    assert.doesNotThrow(() => target.shell.receive(value));
  }
  assert.deepEqual(s.getState(), initialState);
});

test('bridge: event observers report each native receipt by name only, not replies or local writes', async () => {
  const s = fresh(), target = {}, calls = [];
  const bridge = createBridge(s, { target, native: { postMessage: () => reply() } });
  const unsubscribe = bridge.subscribeEvents((...args) => calls.push(args));
  await bridge.start();
  await bridge.send('saveUiState', { avatarId: '1' });
  s.set({ ui: { avatarId: '1', backgroundId: null, voiceEnabled: true } });
  assert.deepEqual(calls, []);
  target.shell.receive({ event: 'paused', paused: false });
  target.shell.receive({ event: 'paused', paused: false });
  target.shell.receive({ event: 'todos', access: 'granted', items: [{ ...todo(), text: 'private title' }] });
  assert.deepEqual(calls, [['paused'], ['paused'], ['todos']]);
  unsubscribe(); unsubscribe();
  target.shell.receive({ event: 'uiState' });
  assert.equal(calls.length, 3);
});

test('bridge: event observer failures and malformed event names preserve delivery without leaking payloads', t => {
  const warn = t.mock.method(console, 'warn', () => {});
  const target = {}, s = fresh(), calls = [];
  const bridge = createBridge(s, { target, native: { postMessage() {} } });
  bridge.subscribeEvents(() => { throw new Error('private observer details'); });
  bridge.subscribeEvents(name => calls.push(name));
  assert.doesNotThrow(() => target.shell.receive({ event: 'paused', paused: true }));
  assert.equal(s.get('paused'), true);
  const revoked = Proxy.revocable({}, {}); revoked.revoke();
  for (const event of [null, { event: 7 }, revoked.proxy, { get event() { throw Error('private payload'); } }]) {
    assert.doesNotThrow(() => target.shell.receive(event));
  }
  assert.deepEqual(calls, ['paused', '?', '?', '?', '?']);
  assert.ok(!JSON.stringify(warn.mock.calls.map(call => call.arguments)).includes('private'));
});

test('bridge: event observers also cover mock closure delivery and are independent subscriptions', async () => {
  const jobs = new Map();
  const mock = createMock({ timers: { setInterval(fn, delay) { jobs.set(delay, fn); return delay; }, clearInterval(id) { jobs.delete(id); } } });
  const bridge = createBridge(fresh(), { target: {}, mock });
  const names = [];
  const listener = name => names.push(name);
  const first = bridge.subscribeEvents(listener), second = bridge.subscribeEvents(listener);
  try {
    await bridge.start();
    assert.equal(names.filter(name => name === 'uiState').length, 2);
    assert.equal(names.filter(name => name === 'paused').length, 2);
    names.length = 0; first();
    const value = await bridge.send('saveUiState', { avatarId: '1' });
    assert.equal(value.avatarId, '1');
    assert.deepEqual(names, ['uiState']);
    jobs.get(33)();
    assert.deepEqual(names, ['uiState', 'audioSpectrum']);
    second(); jobs.get(33)();
    assert.equal(names.length, 2);
  } finally { mock.stop(); }
});

for (const value of [undefined, null, 42, false, [], {}]) {
  test(`bridge: M4 optional fields default independently for ${JSON.stringify(value)}`, async () => {
    const s = fresh();
    const r = reply();
    r.config.user = value;
    r.config.character.motto = value;
    r.config.apps = [{ id: 'a', name: 'App', iconUrl: value }];
    r.media = { avatars: [{ id: '1', url: '/a' }], backgrounds: [{ id: 'b', url: '/b' }], voices: value };
    await createBridge(s, { target: {}, native: { postMessage: () => r } }).start();
    assert.deepEqual(s.get('config').user, { name: null });
    assert.equal(s.get('config').character.motto, null);
    assert.equal(s.get('config').apps[0].iconUrl, null);
    assert.deepEqual(s.get('media'), { avatars: [{ id: '1', url: '/a' }], backgrounds: [{ id: 'b', url: '/b' }], voices: [] });
  });
}

test('bridge: M4 strings survive and voices expose only id/url', async () => {
  const s = fresh();
  assert.deepEqual(s.get('media').voices, []);
  const r = reply();
  r.config.user = { name: 'Arvin' };
  r.config.character.motto = '签名';
  r.config.apps = [{ id: 'a', name: 'App', iconUrl: '/media/app-icons/a.png' }];
  r.media.voices = [null, { id: 1, url: '/v' }, { id: '1', url: 8 }, { id: '2', url: '/media/voice/2.mp3', extra: 'omit' }];
  await createBridge(s, { target: {}, native: { postMessage: () => r } }).start();
  assert.deepEqual(s.get('config').user, { name: 'Arvin' });
  assert.equal(s.get('config').character.motto, '签名');
  assert.equal(s.get('config').apps[0].iconUrl, '/media/app-icons/a.png');
  assert.deepEqual(s.get('media').voices, [{ id: '2', url: '/media/voice/2.mp3' }]);
});

test('bridge: malformed user.name becomes null', async () => {
  for (const name of [undefined, 7, false, [], {}]) {
    const s = fresh();
    const r = reply();
    r.config.user = { name };
    await createBridge(s, { target: {}, native: { postMessage: () => r } }).start();
    assert.deepEqual(s.get('config').user, { name: null });
  }
});
