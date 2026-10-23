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
  assert.equal(reply.config.projects.length, 6);
  assert.ok(!Object.hasOwn(reply.config, 'apps'));
  assert.deepEqual(reply.config.terminal, { hotkey: '⌥`' });
  assert.equal(reply.config.projects[0].hasReminders, true);
  assert.ok(reply.config.projects.some(project => !project.hasReminders));
  for (const project of reply.config.projects) {
    assert.ok(!('apps' in project));
    assert.ok(!('path' in project) && !('remindersList' in project));
  }
  assert.ok(!('background' in reply.config));
  assert.equal(reply.media.avatars.length, 30);
  assert.deepEqual(reply.media.avatars[29], { id: '30', url: '/media/avatars/30.png' });
  assert.equal(reply.media.backgrounds.length, 63);
  assert.deepEqual(reply.media.backgrounds[0], { id: 'folder-01', url: '/media/backgrounds/folder-01.png' });
  assert.deepEqual(reply.media.backgrounds[6], { id: 'settings-01', url: '/media/backgrounds/settings-01.png' });
  assert.deepEqual(reply.media.backgrounds[62], { id: 'start-56', url: '/media/backgrounds/start-56.jpg' });
  assert.deepEqual(reply.uiState, { avatarId: '1', backgroundId: 'folder-01', voiceEnabled: true });
});

const badRequests = [
  [null, 'invalid'], [[], 'invalid'], ['x', 'invalid'], [{}, 'invalid'], [{ action: 1 }, 'invalid'],
  [{ action: 'nope' }, 'unknown-action'], [{ action: '__proto__' }, 'unknown-action'],
  [{ action: 'focusInput', extra: null }, 'invalid'], [{ action: 'blurInput', extra: '' }, 'invalid'],
  [{ action: 'deleteTodo', todoId: 't1' }, 'unknown-action'],
  [{ action: 'getConfig', path: '/' }, 'invalid'],
  [{ action: 'setHitRegions', regions: 'bad' }, 'invalid'],
  [{ action: 'openProject', projectId: 'absent' }, 'not-found'],
  [{ action: 'openProject', projectId: '../etc' }, 'invalid'],
  [{ action: 'openProject', projectId: '' }, 'invalid'],
  [{ action: 'openProject', projectId: 'desktop-shell', path: '/' }, 'invalid'],
  [{ action: 'openTerminal', projectId: 'desktop-shell' }, 'invalid'],
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
  [{ action: 'setTodoDone', todoId: 't1', done: 1 }, 'invalid'],
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

test('mock: opening a project and array hit regions succeed', async t => {
  const info = t.mock.method(console, 'info', () => {});
  const { mock } = fixture();
  for (const message of [
    { action: 'setHitRegions', regions: [] },
    { action: 'openProject', projectId: 'desktop-shell' },
  ]) assert.equal(await mock.handle(message), null);
  assert.equal(info.mock.callCount(), 1);
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
  assert.deepEqual(items, [
    { id: 't1', text: '检查桌面组件的点击区域', done: false, projectId: 'desktop-shell', due: { date: '2026-10-18', time: '09:00' } },
    { id: 't2', text: '整理设计稿的修改意见', done: false, projectId: 'desktop-shell', due: { date: '2026-10-17', time: null } },
    { id: 't3', text: '论文第三章初稿', done: false, projectId: 'thesis', due: { date: '2026-10-19', time: null } },
    { id: 't4', text: '预约下周的体检', done: false, projectId: null, due: { date: '2026-10-16', time: '18:00' } },
    { id: 't5', text: '给阳台的植物浇水', done: false, projectId: null, due: null },
    { id: 't7', text: '更新个人网站的作品集页面', done: false, projectId: 'website', due: { date: '2026-10-20', time: null } },
    { id: 't8', text: '交这个月的水电费', done: false, projectId: null, due: { date: '2026-10-17', time: '20:00' } },
    { id: 't9', text: '读完《设计心理学》第五章', done: false, projectId: 'reading', due: null },
    { id: 't10', text: '给妈妈打个电话', done: false, projectId: null, due: { date: '2026-10-17', time: '21:30' } },
    { id: 't11', text: '把照片备份到移动硬盘', done: false, projectId: null, due: { date: '2026-10-22', time: null } },
    { id: 't12', text: '确认启动栏图标的显示尺寸', done: false, projectId: 'desktop-shell', due: { date: '2026-10-21', time: null } },
    { id: 't6', text: '回复导师的邮件', done: true, projectId: 'thesis', due: null },
    { id: 't13', text: '整理桌面，只留两列图标', done: true, projectId: 'desktop-shell', due: null },
  ]);
  const config = (await mock.handle({ action: 'getConfig' })).config;
  assert.ok(items.every(item => item.projectId === null || config.projects.some(p => p.id === item.projectId && p.hasReminders)));
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
  assert.equal(await mock.handle({ action: 'setTodoDone', todoId: 't1', done: true }), null);
  assert.equal(events.at(-1).items[0].done, true);
  assert.equal(await mock.handle({ action: 'setTodoDone', todoId: 't1', done: false }), null);
  assert.equal(events.at(-1).items[0].done, false);
  for (const access of ['denied', 'notDetermined', 'restricted', 'writeOnly']) {
    mock.setTodosAccess(access);
    assert.deepEqual(events.at(-1), { event: 'todos', access, items: [] });
    await rejects(mock, { action: 'addTodo', text: 'x' }, 'failed');
    await rejects(mock, { action: 'setTodoDone', todoId: 't1', done: true }, 'failed');
  }
  mock.setTodosAccess('granted');
  assert.equal(events.at(-1).items.length, 13);
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

test('mock: display fields and all 54 voice URLs', async () => {
  const { mock } = fixture();
  const { config, media } = await mock.handle({ action: 'getConfig' });
  assert.deepEqual(config.user, { name: 'Arvin' });
  assert.equal(config.character.motto, '愿星光一直落在你走的路上');
  assert.equal(media.voices.length, 54);
  for (let i = 1; i <= 54; i++) assert.deepEqual(media.voices[i - 1], { id: String(i), url: `/media/voice/${i}.mp3` });
});

test('mock: all six projects match the approved preview', async () => {
  const { mock } = fixture();
  const { config } = await mock.handle({ action: 'getConfig' });
  assert.deepEqual(config.projects, [
    { id: 'desktop-shell', name: 'DesktopShell', tags: ['dev'], hasReminders: true },
    { id: 'thesis', name: '课程论文', tags: ['写作'], hasReminders: true },
    { id: 'photos', name: '旅行照片整理', tags: [], hasReminders: false },
    { id: 'website', name: '个人网站', tags: ['dev'], hasReminders: true },
    { id: 'reading', name: '读书笔记', tags: ['阅读'], hasReminders: true },
    { id: 'budget', name: '家庭账本', tags: [], hasReminders: false },
  ]);
});

test('mock: relative dates cross calendar boundaries and added reminders keep unique ids', async () => {
  const mock = createMock({ now: () => new Date(2026, 11, 31, 12).getTime(), timers: { setInterval() {}, clearInterval() {} } });
  const events = [];
  mock.start(event => events.push(event));
  const initial = events.find(event => event.event === 'todos').items;
  assert.deepEqual(initial[0].due, { date: '2027-01-01', time: '09:00' });
  assert.deepEqual(initial[3].due, { date: '2026-12-30', time: '18:00' });
  const added = await mock.handle({ action: 'addTodo', text: '新提醒' });
  assert.equal(added.id, 'mock-14');
  const ids = events.at(-1).items.map(item => item.id);
  assert.equal(ids.length, 14);
  assert.equal(new Set(ids).size, ids.length);
  mock.stop();
});

test('mock: glass regions accepts arrays, rejects missing/non-array and extra parameters', async () => {
  const { mock } = fixture();
  assert.equal(await mock.handle({ action: 'setGlassRegions', regions: [[1, 2, 30, 40, 5]] }), null);
  assert.equal(await mock.handle({ action: 'setGlassRegions', regions: [] }), null);
  for (const message of [
    { action: 'setGlassRegions' }, { action: 'setGlassRegions', regions: null },
    { action: 'setGlassRegions', regions: '[]' },
    { action: 'setGlassRegions', regions: [], extra: true },
  ]) await rejects(mock, message, 'invalid');
});

test('mock: addProject returns a public project, pushes config and generates stable ASCII ids', async () => {
  const { mock } = fixture(); const events = []; mock.start(event => events.push(event));
  for (const [name, id] of [['CS61A-master', 'cs61a-master'], ['My App', 'my-app'], ['操作系统原理实验', 'project'],
    ['另一中文项目', 'project-2'], ['--a__b--', 'a-b'], ['My-App', 'my-app-2']]) {
    const project = await mock.handle({ action: 'addProject', path: `~/Desktop/${name}` });
    assert.deepEqual(project, { id, name, tags: [], hasReminders: false });
    assert.equal(events.at(-1).event, 'config');
    assert.deepEqual(events.at(-1).config.projects.at(-1), project);
    project.name = 'mutated reply'; events.at(-1).config.projects.at(-1).name = 'mutated event';
    assert.equal((await mock.handle({ action: 'getConfig' })).config.projects.at(-1).name, name);
  }
  mock.stop();
});

for (const [path, code] of [
  ['/etc/hosts', 'outside-home'], ['relative', 'outside-home'], ['~', 'outside-home'], ['/Users/me', 'outside-home'],
  ['~/Desktop/file.txt', 'not-directory'], ['~/Desktop/missing', 'not-found'], ['~/Desktop/不存在', 'not-found'],
  ['~/Desktop/DesktopShell', 'duplicate'],
]) test(`mock: project path ${path} returns ${code} without modifying config or pushing`, async () => {
  const { mock } = fixture(); const events = []; mock.start(event => events.push(event));
  const before = await mock.handle({ action: 'getConfig' }), count = events.length;
  await rejects(mock, { action: 'addProject', path }, code);
  assert.deepEqual(await mock.handle({ action: 'getConfig' }), before); assert.equal(events.length, count); mock.stop();
});

for (const path of ['～/Desktop/test', '～／Desktop／test', '／Users／me／Desktop／test']) {
  test(`mock: full-width prefix ${path} is normalized before adding`, async () => {
    const { mock } = fixture(); const events = []; mock.start(event => events.push(event));
    const project = await mock.handle({ action: 'addProject', path });
    assert.deepEqual(project, { id: 'test', name: 'test', tags: [], hasReminders: false });
    assert.deepEqual(events.at(-1).config.projects.at(-1), project);
    await rejects(mock, { action: 'addProject', path: '~/Desktop/test' }, 'duplicate');
    mock.stop();
  });
}

for (const [path, code] of [['／etc', 'outside-home'], ['～/Desktop/missing', 'not-found'],
  ['～/Desktop/file.txt', 'not-directory'], ['～/Desktop/DesktopShell', 'duplicate']]) {
  test(`mock: normalized path ${path} preserves ${code} and config`, async () => {
    const { mock } = fixture(); const events = []; mock.start(event => events.push(event));
    const before = await mock.handle({ action: 'getConfig' }), count = events.length;
    await rejects(mock, { action: 'addProject', path }, code);
    assert.deepEqual(await mock.handle({ action: 'getConfig' }), before);
    assert.equal(events.length, count); mock.stop();
  });
}

test('mock: valid original prefix preserves full-width filename characters', async () => {
  const { mock } = fixture();
  const project = await mock.handle({ action: 'addProject', path: '~/Desktop/a／b～c' });
  assert.equal(project.name, 'a／b～c');
});

test('mock: project add validates path payload/length and remove validates ids and extra fields', async () => {
  const { mock } = fixture();
  for (const message of [
    { action: 'addProject' }, { action: 'addProject', path: null }, { action: 'addProject', path: 1 },
    { action: 'addProject', path: '' }, { action: 'addProject', path: 'x'.repeat(1025) },
    { action: 'addProject', path: '~/x', extra: null }, { action: 'removeProject' },
    { action: 'removeProject', projectId: null }, { action: 'removeProject', projectId: 'a/b' },
    { action: 'removeProject', projectId: 'desktop-shell', path: '~/x' },
  ]) await rejects(mock, message, 'invalid');
  const name = '中'.repeat(1022);
  assert.equal((await mock.handle({ action: 'addProject', path: `~/${name}` })).name, name);
});

test('mock: same path or same name duplicates; remove returns null and makes the folder addable again', async () => {
  const { mock } = fixture(); const events = []; mock.start(event => events.push(event));
  const project = await mock.handle({ action: 'addProject', path: '/Users/test/Folder/' });
  await rejects(mock, { action: 'addProject', path: '/Users/test/Folder' }, 'duplicate');
  await rejects(mock, { action: 'addProject', path: '~/Elsewhere/Folder' }, 'duplicate');
  assert.equal(await mock.handle({ action: 'removeProject', projectId: project.id }), null);
  assert.equal(events.at(-1).event, 'config');
  assert.ok(!events.at(-1).config.projects.some(item => item.id === project.id));
  await rejects(mock, { action: 'removeProject', projectId: project.id }, 'not-found');
  assert.equal((await mock.handle({ action: 'addProject', path: '/Users/test/Folder' })).id, 'folder');
  mock.stop();
});

test('mock: dropFolders emits hover, adds each name, reports first error and finishes without timers', async () => {
  const { mock, jobs } = fixture(); const events = []; mock.start(event => events.push(event)); events.length = 0;
  const result = await mock.dropFolders(['Folder A', 'missing', 'Folder B', 'file.txt']);
  assert.deepEqual(events[0], { event: 'projectDrop', over: true, result: null });
  assert.deepEqual(result, { added: [{ id: 'folder-a', name: 'Folder A' }, { id: 'folder-b', name: 'Folder B' }], error: 'not-found' });
  assert.deepEqual(events.at(-1), { event: 'projectDrop', over: false, result });
  assert.equal(events.filter(event => event.event === 'config').length, 2);
  assert.equal(jobs.size, 2, 'no extra persistent timers for drops');
  await assert.rejects(mock.dropFolders([null]), /invalid/);
  mock.stop(); assert.equal(jobs.size, 0);
});

test('mock: setDropRegions accepts regions like setHitRegions and rejects missing/non-array/extra parameters', async () => {
  const { mock } = fixture();
  for (const regions of [[], [[0, 0, 20, 30]]]) {
    assert.equal(await mock.handle({ action: 'setDropRegions', regions }), null);
  }
  for (const message of [{ action: 'setDropRegions' }, { action: 'setDropRegions', regions: 'bad' },
    { action: 'setDropRegions', regions: [], path: '~/private' }]) {
    await rejects(mock, message, 'invalid');
  }
});

test('mock: openTerminal logs once, returns null and rejects every parameter without changing state', async t => {
  const info = t.mock.method(console, 'info', () => {});
  const { mock } = fixture();
  const before = await mock.handle({ action: 'getConfig' });
  assert.equal(await mock.handle({ action: 'openTerminal' }), null);
  assert.deepEqual(info.mock.calls[0].arguments, ['mock: openTerminal']);
  for (const extra of [undefined, null, false, 0, '', [], {}]) {
    await rejects(mock, { action: 'openTerminal', extra }, 'invalid');
  }
  assert.equal(info.mock.callCount(), 1);
  assert.deepEqual(await mock.handle({ action: 'getConfig' }), before);
});

test('mock: retired application actions are unknown and cannot change configuration', async () => {
  const { mock } = fixture();
  const before = await mock.handle({ action: 'getConfig' });
  for (const action of ['launch' + 'App', 'openProject' + 'With']) {
    await rejects(mock, { action, projectId: 'desktop-shell', ['app' + 'Id']: 'cursor' }, 'unknown-action');
  }
  assert.deepEqual(await mock.handle({ action: 'getConfig' }), before);
});

test('mock: project edit options only expose identity and name', async () => {
  const { mock } = fixture();
  const options = await mock.handle({ action: 'getProjectEditOptions', projectId: 'desktop-shell' });
  assert.deepEqual(options.project, { id: 'desktop-shell', name: 'DesktopShell' });
});

test('mock: legacy application updates reject atomically', async () => {
  const { mock } = fixture(); const events = []; mock.start(event => events.push(event));
  try {
    const before = await mock.handle({ action: 'getConfig' }), count = events.length;
    for (const value of ['cursor', null, undefined]) {
      await rejects(mock, { action: 'updateProject', projectId: 'desktop-shell', name: 'Changed', ['app' + 'Id']: value }, 'invalid');
    }
    assert.deepEqual(await mock.handle({ action: 'getConfig' }), before);
    assert.equal(events.length, count);
    const updated = await mock.handle({ action: 'updateProject', projectId: 'desktop-shell', name: 'Changed' });
    assert.deepEqual(updated, { id: 'desktop-shell', name: 'Changed', tags: ['dev'], hasReminders: true });
    assert.deepEqual(events.at(-1).config.projects[0], updated);
  } finally { mock.stop(); }
});
