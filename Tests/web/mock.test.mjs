import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createMock } from '../../web/js/mock.js';

function fixture() {
  const jobs = new Map();
  let next = 0;
  const timers = {
    setInterval(callback, delay) { const id = ++next; jobs.set(id, { callback, delay }); return id; },
    clearInterval(id) { jobs.delete(id); },
    tick(delay) { for (const job of [...jobs.values()]) if (job.delay === delay) job.callback(); },
  };
  const mock = createMock({ timers, now: () => new Date(2026, 9, 17, 12).getTime(), random: () => 0.5 });
  return { mock, timers, jobs };
}
const rejects = (mock, message, code) => assert.rejects(mock.handle(message), error => error instanceof Error && error.message === code);

test('mock: getConfig returns display-only configuration and all 30/63 real media URLs', async () => {
  const { mock } = fixture();
  const reply = await mock.handle({ action: 'getConfig' });
  assert.deepEqual(Object.keys(reply), ['config', 'media', 'uiState']);
  assert.equal(reply.config.character.name, '爱弥斯');
  assert.deepEqual(reply.config.greetings.map(item => item.from), [0, 6, 12, 18, 20, 21, 23]);
  assert.equal(reply.config.greetings[0].wish, '时辰已晚，且捻熄灯盏，良宵安枕');
  assert.equal(reply.config.projects.length, 3);
  assert.equal(reply.config.apps.length, 3);
  assert.deepEqual(reply.config.projects[0].apps, ['cursor']);
  assert.equal(reply.config.projects[0].hasReminders, true);
  assert.ok(reply.config.projects.some(project => !('apps' in project) && !project.hasReminders));
  for (const project of reply.config.projects) {
    assert.ok(!('path' in project) && !('remindersList' in project));
  }
  assert.ok(reply.config.apps.every(app => !('bundleId' in app)));
  assert.ok(!('background' in reply.config));
  assert.equal(reply.media.avatars.length, 30);
  assert.deepEqual(reply.media.avatars[29], { id: '30', url: '/media/avatars/30.png' });
  assert.equal(reply.media.backgrounds.length, 63);
  assert.deepEqual(reply.media.backgrounds[0], { id: 'folder-01', url: '/media/backgrounds/folder-01.png' });
  assert.deepEqual(reply.media.backgrounds[6], { id: 'settings-01', url: '/media/backgrounds/settings-01.png' });
  assert.deepEqual(reply.media.backgrounds[62], { id: 'start-56', url: '/media/backgrounds/start-56.jpg' });
  assert.deepEqual(reply.uiState, { avatarId: null, backgroundId: null, voiceEnabled: true });
});

const badRequests = [
  [null, 'invalid'], [[], 'invalid'], ['x', 'invalid'], [{}, 'invalid'], [{ action: 1 }, 'invalid'],
  [{ action: 'nope' }, 'unknown-action'], [{ action: '__proto__' }, 'unknown-action'],
  [{ action: 'focusInput', extra: null }, 'invalid'], [{ action: 'blurInput', extra: '' }, 'invalid'],
  [{ action: 'deleteTodo', todoId: 'mock-1' }, 'unknown-action'],
  [{ action: 'getConfig', path: '/' }, 'invalid'],
  [{ action: 'setHitRegions', regions: 'bad' }, 'invalid'],
  [{ action: 'openProject', projectId: 'absent' }, 'not-found'],
  [{ action: 'openProject', projectId: '../etc' }, 'invalid'],
  [{ action: 'openProject', projectId: '' }, 'invalid'],
  [{ action: 'openProject', projectId: 'desktop-shell', path: '/' }, 'invalid'],
  [{ action: 'openProjectWith', projectId: 'desktop-shell' }, 'invalid'],
  [{ action: 'openProjectWith', projectId: 'missing', appId: '../bad' }, 'invalid'],
  [{ action: 'openProjectWith', projectId: 'desktop-shell', appId: 'missing' }, 'not-found'],
  [{ action: 'launchApp', appId: 'missing' }, 'not-found'],
  [{ action: 'launchApp', appId: 'com.apple.Safari' }, 'invalid'],
  [{ action: 'saveUiState' }, 'invalid'],
  [{ action: 'saveUiState', avatarId: '31' }, 'not-found'],
  [{ action: 'saveUiState', avatarId: '../1' }, 'invalid'],
  [{ action: 'saveUiState', avatarId: undefined }, 'invalid'],
  [{ action: 'saveUiState', avatarId: null, voiceEnabled: false }, 'invalid'],
  [{ action: 'addTodo', text: ' \n\t ' }, 'invalid'],
  [{ action: 'addTodo', text: 123 }, 'invalid'],
  [{ action: 'addTodo', text: 'x'.repeat(501) }, 'invalid'],
  [{ action: 'addTodo', text: 'x', projectId: '../etc' }, 'invalid'],
  [{ action: 'addTodo', text: 'x', projectId: 'absent' }, 'not-found'],
  [{ action: 'addTodo', text: 'x', due: null }, 'invalid'],
  [{ action: 'setTodoDone', todoId: 'missing', done: true }, 'not-found'],
  [{ action: 'setTodoDone', todoId: 'mock-1', done: 1 }, 'invalid'],
  [{ action: 'setTodoDone', todoId: '../etc', done: true }, 'invalid'],
];
for (const [index, [message, code]] of badRequests.entries()) {
  test(`mock: ${message?.action ?? 'malformed message'} request ${index + 1} → ${code}`, async () => {
    await rejects(fixture().mock, message, code);
  });
}

test('mock: keyboard focus actions resolve null without changing mock state', async () => {
  const { mock } = fixture();
  const before = mock.state;
  for (const action of ['focusInput', 'blurInput']) {
    assert.equal(await mock.handle({ action }), null);
    for (const extra of [undefined, false, 0, [], {}]) await rejects(mock, { action, extra }, 'invalid');
  }
  assert.deepEqual(mock.state, before);
});

test('mock: launch actions and array hit regions succeed without requiring app/project association', async t => {
  const info = t.mock.method(console, 'info', () => {});
  const { mock } = fixture();
  for (const message of [
    { action: 'setHitRegions', regions: [] },
    { action: 'openProject', projectId: 'desktop-shell' },
    { action: 'openProjectWith', projectId: 'desktop-shell', appId: 'safari' },
    { action: 'launchApp', appId: 'cursor' },
  ]) assert.equal(await mock.handle(message), null);
  assert.equal(info.mock.callCount(), 3);
});

test('mock: saveUiState updates, broadcasts, clears and rejects atomically without leaking mutable state', async () => {
  const { mock } = fixture();
  const events = [];
  mock.start(event => events.push(event));
  events.length = 0;
  const saved = await mock.handle({ action: 'saveUiState', avatarId: '12', backgroundId: 'start-01' });
  assert.deepEqual(saved, { avatarId: '12', backgroundId: 'start-01', voiceEnabled: true });
  assert.deepEqual(events, [{ event: 'uiState', ...saved }]);
  saved.avatarId = '30';
  events[0].backgroundId = 'folder-01';
  await rejects(mock, { action: 'saveUiState', avatarId: '1', backgroundId: 'missing' }, 'not-found');
  assert.equal((await mock.handle({ action: 'getConfig' })).uiState.avatarId, '12');
  assert.equal((await mock.handle({ action: 'getConfig' })).uiState.backgroundId, 'start-01');
  assert.deepEqual(await mock.handle({ action: 'saveUiState', avatarId: null }), { avatarId: null, backgroundId: 'start-01', voiceEnabled: true });
  mock.stop();
});

test('mock: initial reminder fixtures use calendar days, project associations and all due variants', async () => {
  const { mock } = fixture();
  const events = [];
  mock.start(event => events.push(event));
  const items = events.find(event => event.event === 'todos').items;
  assert.equal(items.length, 5);
  assert.deepEqual(items[0].due, { date: '2026-10-18', time: '09:00' });
  assert.equal(items[0].projectId, 'desktop-shell');
  assert.equal(items[1].due, null);
  assert.ok((await mock.handle({ action: 'getConfig' })).config.projects.some(p => p.id === items[1].projectId && p.hasReminders));
  assert.deepEqual(items[2].due, { date: '2026-10-17', time: null });
  assert.deepEqual(items[3].due, { date: '2026-10-16', time: '18:00' });
  assert.equal(items[4].done, true);
  mock.stop();
});

test('mock: addTodo trims, associates or defaults, counts graphemes and broadcasts isolated snapshots', async () => {
  const { mock } = fixture();
  const events = [];
  mock.start(event => events.push(event));
  const config = (await mock.handle({ action: 'getConfig' })).config;
  const noList = config.projects.find(project => !project.hasReminders).id;
  for (const [projectId, expected] of [[undefined, null], [null, null], ['desktop-shell', 'desktop-shell'], [noList, null]]) {
    const params = projectId === undefined ? {} : { projectId };
    const added = await mock.handle({ action: 'addTodo', text: '  新提醒  ', ...params });
    assert.equal(added.text, '新提醒');
    assert.equal(added.projectId, expected);
    assert.equal(added.done, false);
    assert.equal(added.due, null);
    assert.match(added.id, /^[A-Za-z0-9_-]+$/);
    assert.deepEqual(events.at(-1).items.at(-1), added);
  }
  const grapheme = '👨‍👩‍👧‍👦';
  const added = await mock.handle({ action: 'addTodo', text: grapheme.repeat(500) });
  assert.equal(added.text, grapheme.repeat(500));
  await rejects(mock, { action: 'addTodo', text: grapheme.repeat(501) }, 'invalid');
  added.done = true;
  const reply = await mock.handle({ action: 'setTodoDone', todoId: added.id, done: false });
  assert.equal(reply, null);
  assert.equal(events.at(-1).items.at(-1).done, false);
  mock.stop();
});

test('mock: setTodoDone broadcasts completion and undo; denied writes fail and grant restores memory', async () => {
  const { mock } = fixture();
  const events = [];
  mock.start(event => events.push(event));
  assert.equal(await mock.handle({ action: 'setTodoDone', todoId: 'mock-1', done: true }), null);
  assert.equal(events.at(-1).items[0].done, true);
  assert.equal(await mock.handle({ action: 'setTodoDone', todoId: 'mock-1', done: false }), null);
  assert.equal(events.at(-1).items[0].done, false);
  for (const access of ['denied', 'notDetermined', 'restricted', 'writeOnly']) {
    mock.setTodosAccess(access);
    assert.deepEqual(events.at(-1), { event: 'todos', access, items: [] });
    await rejects(mock, { action: 'addTodo', text: 'x' }, 'failed');
    await rejects(mock, { action: 'setTodoDone', todoId: 'mock-1', done: true }, 'failed');
  }
  mock.setTodosAccess('granted');
  assert.equal(events.at(-1).items.length, 5);
  assert.equal(events.at(-1).items[0].done, false);
  assert.deepEqual(mock.state, { sound: true, paused: false, todosAccess: 'granted' });
  assert.throws(() => { mock.state.sound = false; }, TypeError);
  mock.stop();
});

test('mock: startup pushes once; fake timers honor sound/pause, bounded stats, stop and restart', () => {
  const { mock, timers, jobs } = fixture();
  const events = [];
  mock.start(event => events.push(event));
  mock.start(() => assert.fail('second start replaced receiver'));
  assert.deepEqual(events.map(event => event.event), ['safeArea', 'paused', 'uiState', 'todos', 'systemStats']);
  assert.deepEqual(events[0], { event: 'safeArea', top: 25, right: 0, bottom: 80, left: 0 });
  assert.deepEqual([...jobs.values()].map(job => job.delay).sort((a, b) => a - b), [33, 5000]);
  timers.tick(33);
  assert.equal(events.at(-1).event, 'audioSpectrum');
  assert.equal(events.at(-1).bands.length, 12);
  assert.ok(events.at(-1).bands.every(v => v >= 0 && v <= 1));
  mock.setSound(false);
  let count = events.length;
  timers.tick(33);
  assert.equal(events.length, count);
  mock.setSound(true);
  mock.setPaused(true);
  assert.deepEqual(events.at(-1), { event: 'paused', paused: true });
  count = events.length;
  timers.tick(33);
  assert.equal(events.length, count);
  timers.tick(5000);
  const stats = events.at(-1);
  assert.equal(stats.event, 'systemStats');
  assert.ok(stats.cpu >= 3 && stats.cpu <= 60);
  assert.ok(stats.memory.percent >= 55 && stats.memory.percent <= 75);
  assert.ok(Number.isInteger(stats.battery.level));
  assert.equal(stats.battery.onBattery, false);
  mock.setPaused(false);
  timers.tick(33);
  assert.equal(events.at(-1).event, 'audioSpectrum');
  mock.stop();
  count = events.length;
  timers.tick(33); timers.tick(5000);
  mock.setPaused(true); mock.setTodosAccess('denied');
  assert.equal(events.length, count);
  assert.equal(jobs.size, 0);
  mock.start(event => events.push(event));
  assert.equal(jobs.size, 2);
  mock.stop(); mock.stop();
  assert.equal(jobs.size, 0);
});

for (const stopAt of ['safeArea', 'paused', 'uiState', 'todos', 'systemStats']) {
  test(`mock: stop inside initial ${stopAt} callback prevents timers and permits a clean restart`, () => {
    const { mock, timers, jobs } = fixture();
    const events = [];
    mock.start(event => {
      events.push(event.event);
      if (event.event === stopAt) mock.stop();
    });
    assert.equal(events.at(-1), stopAt);
    assert.equal(jobs.size, 0);
    const count = events.length;
    timers.tick(33); timers.tick(5000);
    assert.equal(events.length, count);
    mock.start(event => events.push(event.event));
    assert.equal(jobs.size, 2);
    assert.equal(events.length, count + 5);
    mock.stop();
    assert.equal(jobs.size, 0);
  });
}

test('mock: stop/restart inside startup callback interrupts the obsolete initial event sequence', () => {
  const { mock, jobs } = fixture();
  const oldEvents = [];
  const newEvents = [];
  mock.start(event => {
    oldEvents.push(event.event);
    mock.stop();
    mock.start(next => newEvents.push(next.event));
  });
  assert.deepEqual(oldEvents, ['safeArea']);
  assert.deepEqual(newEvents, ['safeArea', 'paused', 'uiState', 'todos', 'systemStats']);
  assert.equal(jobs.size, 2);
  mock.stop();
  assert.equal(jobs.size, 0);
});
