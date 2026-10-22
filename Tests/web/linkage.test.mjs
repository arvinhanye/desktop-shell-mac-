import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createStore, initialState } from '../../web/js/store.js';
import { createBridge } from '../../web/js/bridge.js';
import { createMock } from '../../web/js/mock.js';
import { createBrowser, descendants, byClass, one } from './helpers/linkage-browser.mjs';

// main.js requires a real document and has top-level await: inspect its wiring,
// but mount the real modules below, synchronously in the documented page order.
const mainSource = await readFile(new URL('../../web/js/main.js', import.meta.url), 'utf8');
const widgetNames = ['clock', 'greeting', 'projects', 'launcher', 'todos', 'stats', 'character', 'appearance', 'project-editor', 'voice', 'visualizer'];
const registered = [...(mainSource.match(/const WIDGETS\s*=\s*\[([^\]]+)\]/)?.[1] ?? '').matchAll(/'([^']+)'/g)]
  .map(match => match[1]);
assert.deepEqual(registered, widgetNames, 'the fixture must include every main.js widget in page order');
const widgets = await Promise.all(widgetNames.map(async name =>
  (await import(`../../web/widgets/${name}.js`)).default));

async function page(t, { hour = 7, minute = 0 } = {}) {
  const browser = createBrowser(new Date(2026, 9, 19, hour, minute).getTime());
  const { doc, desktop } = browser;
  const store = createStore(initialState);
  const target = {};
  const mock = createMock({ timers: browser.win, now: browser.now, random: () => 0.25 });
  const requests = [], heldUI = [], received = [], cleanups = [], hosts = {};
  let holdUI = false;
  // Tap the real transport; do not replace bridge.send or synthesize its replies.
  const transport = {
    handle(message) { requests.push(structuredClone(message)); return mock.handle(message); },
    start(receive) {
      assert.equal(receive, target.shell.receive);
      mock.start(event => {
        if (holdUI && event.event === 'uiState') heldUI.push(event);
        else target.shell.receive(event);
      });
    },
    stop: () => mock.stop(),
  };
  const bridge = createBridge(store, { target, mock: transport, now: browser.now });
  const originalAudio = Object.getOwnPropertyDescriptor(globalThis, 'Audio');
  Object.defineProperty(globalThis, 'Audio', { configurable: true, writable: true, value: browser.Audio });
  // voice.mount uses the global Audio and Math.random; neither may reach the host.
  t.mock.method(Math, 'random', () => 0.25);
  const errors = [], warnings = [];
  t.mock.method(console, 'error', (...args) => errors.push(args));
  t.mock.method(console, 'warn', (...args) => warnings.push(args));
  // Register before mounting: assertion/startup failures still dispose the page.
  t.after(() => {
    const cleanupErrors = [];
    try {
      for (const cleanup of cleanups.reverse()) {
        try { cleanup(); } catch (error) { cleanupErrors.push(error); }
      }
    } finally {
      transport.stop();
      if (originalAudio) Object.defineProperty(globalThis, 'Audio', originalAudio);
      else delete globalThis.Audio;
    }
    assert.deepEqual(cleanupErrors, []);
    browser.assertClean();
    const state = store.getState();
    browser.advance(60000); browser.draw();
    assert.deepEqual(store.getState(), state, 'no mock or widget work may leak beyond cleanup');
    assert.deepEqual(errors, [], 'store subscriber exceptions must not be swallowed by the fixture');
    assert.deepEqual(warnings, [], 'all bridge messages/events must be valid');
  });
  cleanups.push(bridge.subscribeEvents(name => received.push(name)));
  for (const widget of widgets) {
    const host = doc.createElement('section');
    host.className = 'widget'; host.dataset.widget = widget.name;
    desktop.append(host); hosts[widget.name] = host;
    const cleanup = widget.mount(host, { store, bridge, hitRegions: {} });
    assert.equal(typeof cleanup, 'function', `${widget.name} must return cleanup`);
    cleanups.push(cleanup);
  }
  await bridge.start();
  assert.equal(bridge.mode, 'mock');
  assert.equal(store.get('ready'), true);
  assert.equal(store.get('todosAccess'), 'granted');
  assert.deepEqual(desktop.children.map(host => host.dataset.widget), widgetNames);
  assert.deepEqual(requests, [{ action: 'getConfig' }]);
  return {
    browser, store, hosts, requests, received, mock,
    push: event => target.shell.receive(event),
    holdUI() { holdUI = true; },
    releaseUI() {
      assert.ok(heldUI.length, 'the actual mock must have emitted a uiState');
      holdUI = false;
      for (const event of heldUI.splice(0)) target.shell.receive(event);
    },
  };
}

const row = (f, name) => {
  const result = byClass(f.hosts.projects, 'project')
    .find(node => one(node, 'project-name').textContent === name);
  assert.ok(result, `project ${name} must exist`);
  return result;
};
const todoTexts = f => byClass(f.hosts.todos, 'todo-text').map(node => node.textContent).sort();
const relatedApps = f => byClass(f.hosts.launcher, 'app')
  .filter(node => node.classList.contains('related')).map(node => one(node, 'app-name').textContent).sort();
const avatar = f => one(f.hosts.character, 'avatar-button');
const bars = f => byClass(f.hosts.visualizer, 'viz-bars').flatMap(group => group.children);
const spectrum = level => ({ event: 'audioSpectrum', bands: Array(12).fill(level) });
const desktopTodos = ['检查桌面组件的点击区域', '整理设计稿的修改意见', '确认启动栏图标的显示尺寸', '整理桌面，只留两列图标'].sort();

for (const [hour, phase] of [[7, 'morning'], [21, 'night']]) {
  test(`联动 1：时钟 ${hour}:00 写入 ${phase}，入口订阅页面主题`, async t => {
    const f = await page(t, { hour });
    assert.equal(f.store.get('phase'), phase);
    assert.equal(one(f.hosts.clock, 'clock-time').textContent, `${String(hour).padStart(2, '0')}:00`);
    assert.match(mainSource, /store\.subscribe\('phase',\s*phase\s*=>\s*\{[^}]*document\.documentElement\.dataset\.phase\s*=\s*phase[^}]*\},\s*\{\s*immediate:\s*true\s*\}\)/);
  });
}

test('联动 2：项目点击筛选待办，回车新增经过 bridge/mock 按列表归属推送', async t => {
  const f = await page(t);
  const allTodos = todoTexts(f);
  assert.equal(allTodos.length, 13);
  assert.equal(one(f.hosts.todos, 'card-meta').textContent, '全部列表');
  await row(f, 'DesktopShell').emit('click');
  assert.equal(f.store.get('selectedProject'), 'desktop-shell');
  assert.equal(one(f.hosts.todos, 'card-meta').textContent, '只看「DesktopShell」');
  assert.deepEqual(todoTexts(f), desktopTodos);
  await row(f, 'DesktopShell').emit('click');
  assert.equal(f.store.get('selectedProject'), null);
  assert.equal(one(f.hosts.todos, 'card-meta').textContent, '全部列表');
  assert.deepEqual(todoTexts(f), allTodos);

  await row(f, 'DesktopShell').emit('click');
  const input = descendants(f.hosts.todos).find(node => node.tagName === 'INPUT');
  assert.ok(input && !input.disabled);
  input.value = '  联动测试：项目提醒  ';
  const beforeAdd = f.received.length;
  await input.emit('keydown', { key: 'Enter', isComposing: false });
  assert.deepEqual(f.requests.at(-1), { action: 'addTodo', text: '联动测试：项目提醒', projectId: 'desktop-shell' });
  assert.deepEqual(f.received.slice(beforeAdd), ['todos']);
  assert.equal(f.store.get('todos').find(todo => todo.text === '联动测试：项目提醒')?.projectId, 'desktop-shell');
  assert.deepEqual(todoTexts(f), [...desktopTodos, '联动测试：项目提醒'].sort());
  assert.equal(input.value, '');

  await row(f, '旅行照片整理').emit('click');
  assert.equal(one(f.hosts.todos, 'card-meta').textContent, '只看「旅行照片整理」');
  assert.equal(one(f.hosts.todos, 'todo-hint').textContent, '这个项目没有对应的提醒事项列表，新增的提醒会放进默认列表');
  assert.deepEqual(todoTexts(f), []);
  input.value = '联动测试：默认列表提醒';
  await input.emit('keydown', { key: 'Enter', isComposing: false });
  assert.deepEqual(f.requests.at(-1), { action: 'addTodo', text: '联动测试：默认列表提醒', projectId: 'photos' });
  assert.equal(f.store.get('todos').find(todo => todo.text === '联动测试：默认列表提醒')?.projectId, null);
  assert.deepEqual(todoTexts(f), []);
  await row(f, '旅行照片整理').emit('click');
  assert.equal(one(f.hosts.todos, 'card-meta').textContent, '全部列表');
  assert.equal(one(f.hosts.todos, 'todo-hint').textContent, '');
  assert.deepEqual(todoTexts(f), [...allTodos, '联动测试：项目提醒', '联动测试：默认列表提醒'].sort());
});

test('联动 3：同一次项目点击同时筛选待办并高亮关联应用，无 apps 或取消时清除', async t => {
  const f = await page(t);
  assert.deepEqual(relatedApps(f), []);
  await row(f, 'DesktopShell').emit('click');
  assert.deepEqual(todoTexts(f), desktopTodos);
  assert.deepEqual(relatedApps(f), ['Cursor']);
  await row(f, '课程论文').emit('click');
  assert.deepEqual(todoTexts(f), ['回复导师的邮件', '论文第三章初稿'].sort());
  assert.deepEqual(relatedApps(f), ['Safari', '备忘录'].sort());
  await row(f, '课程论文').emit('click');
  assert.equal(f.store.get('selectedProject'), null);
  assert.deepEqual(relatedApps(f), []);
  await row(f, 'DesktopShell').emit('click');
  assert.deepEqual(relatedApps(f), ['Cursor']);
  await row(f, '旅行照片整理').emit('click');
  assert.equal(f.store.get('selectedProject'), 'photos');
  assert.deepEqual(relatedApps(f), []);
  await row(f, '旅行照片整理').emit('click');
  assert.deepEqual(relatedApps(f), []);
});

test('联动 4：20:59 到 21:00 的时钟定时更新驱动祝福语和 night 主题', async t => {
  const f = await page(t, { hour: 20, minute: 59 });
  f.mock.setSound(false); // Still run the real mock timers, without irrelevant audio frames.
  assert.equal(f.store.get('phase'), 'evening');
  assert.equal(one(f.hosts.greeting, 'greeting-title').textContent, '晚上好，Arvin');
  assert.equal(one(f.hosts.greeting, 'greeting-wish').textContent, '且舒怀抱，自在一刻尽欢愉');
  const previousMinute = f.store.get('now');
  f.browser.advance(59999);
  assert.equal(f.store.get('now'), previousMinute);
  assert.equal(f.store.get('phase'), 'evening');
  // clock.js intentionally fires 50ms after the minute boundary.
  f.browser.advance(51);
  assert.equal(f.store.get('now'), previousMinute + 60000);
  assert.equal(one(f.hosts.clock, 'clock-time').textContent, '21:00');
  assert.equal(f.store.get('phase'), 'night');
  assert.equal(one(f.hosts.greeting, 'greeting-wish').textContent, '时辰已晚，且捻熄灯盏，良宵安枕');
});

test('联动 5：电池 15% 显示提示但不自行暂停，20% 边界清除提示', async t => {
  const f = await page(t);
  const stats = level => ({ event: 'systemStats', battery: { level, charging: false, onBattery: true },
    cpu: 12, memory: { usedBytes: 4 * 1024 ** 3, totalBytes: 8 * 1024 ** 3, percent: 50 } });
  const card = one(f.hosts.stats, 'stats-card');
  f.push(stats(15));
  assert.ok(card.classList.contains('low-battery'));
  assert.equal(one(card, 'stat-battery').textContent, '电量15% 用电池');
  assert.equal(one(card, 'power-hint').textContent, '电量低于 20%，已暂停背景视频和动画来省电');
  assert.equal(f.store.get('paused'), false, 'the native power policy, not the web card, owns paused');
  f.push(spectrum(0.8)); f.browser.draw();
  assert.ok(bars(f).every(bar => bar.style.transform === 'scaleY(0.8)'));
  f.push({ event: 'paused', paused: true });
  assert.equal(f.store.get('paused'), true);
  assert.equal(f.store.get('audioSpectrum'), null);
  assert.ok(bars(f).every(bar => bar.style.transform === ''));
  f.push(stats(20));
  assert.equal(card.classList.contains('low-battery'), false);
  assert.equal(f.store.get('paused'), true, 'stats must not overwrite a native pause either');
  f.push({ event: 'paused', paused: false });
  assert.equal(f.store.get('paused'), false);
});

test('联动 6：暂停清空频谱和待绘帧、丢弃后续频谱，语音仍可播，恢复等待新数据', async t => {
  const f = await page(t);
  // Swift stopping/restarting system audio capture belongs to M5.5, not this JS test.
  assert.match(mainSource, /store\.subscribe\('paused',\s*paused\s*=>\s*document\.documentElement\.toggleAttribute\('data-paused',\s*paused\),\s*\{\s*immediate:\s*true\s*\}\)/);
  assert.equal(bars(f).length, 24);
  f.push(spectrum(0.8)); f.browser.draw();
  assert.deepEqual(bars(f).map(bar => bar.style.transform), Array(24).fill('scaleY(0.8)'));
  f.push(spectrum(0.9));
  assert.equal(f.browser.frames.size, 1);
  f.push({ event: 'paused', paused: true });
  assert.equal(f.store.get('audioSpectrum'), null);
  assert.deepEqual(bars(f).map(bar => bar.style.transform), Array(24).fill(''));
  assert.equal(f.browser.frames.size, 0);
  const frameRequests = f.browser.frameRequests;
  const timerCount = f.browser.timers.size;
  f.push(spectrum(1));
  f.browser.advance(100); // The real mock also emits several late spectrum events.
  f.browser.draw();
  assert.equal(f.store.get('audioSpectrum'), null);
  assert.equal(f.browser.frameRequests, frameRequests);
  assert.equal(f.browser.frames.size, 0);
  assert.equal(f.browser.timers.size, timerCount);
  assert.ok(bars(f).every(bar => bar.style.transform === ''));
  await avatar(f).emit('click');
  assert.equal(f.browser.audios.length, 1);
  assert.equal(f.browser.audios[0].plays, 1);
  assert.equal(f.store.get('voicePlaying'), true);
  assert.ok(avatar(f).classList.contains('playing'));
  f.push({ event: 'paused', paused: false });
  assert.equal(f.store.get('audioSpectrum'), null);
  assert.equal(f.browser.frames.size, 0, 'resume must wait for fresh spectrum');
  f.push(spectrum(0.4)); f.browser.draw();
  assert.deepEqual(bars(f).map(bar => bar.style.transform), Array(24).fill('scaleY(0.4)'));
});

test('联动 7：外观只发送 id，回复先到仍等待 uiState 推送更新头像和两张背景', async t => {
  const f = await page(t);
  const image = avatar(f).children[0];
  const characterArt = one(f.hosts.character, 'card-art');
  const launcherArt = one(f.hosts.launcher, 'card-art');
  const overlay = one(f.hosts.appearance, 'appearance-overlay');
  assert.equal(overlay.hidden, true);
  await one(f.hosts.character, 'appearance-button').emit('click');
  assert.equal(f.store.get('appearanceOpen'), true);
  assert.equal(overlay.hidden, false);
  const avatars = one(f.hosts.appearance, 'avatars').children;
  const backgrounds = one(f.hosts.appearance, 'backgrounds').children;
  const choice = avatars.find(node => node.dataset.id === '2');
  const background = backgrounds.find(node => node.dataset.id === 'folder-02');
  const before = { ...f.store.get('ui') };
  const oldBackground = 'url("/media/backgrounds/folder-01.png")';
  assert.equal(image.src, '/media/avatars/1.png');
  assert.equal(characterArt.style.backgroundImage, oldBackground);
  assert.equal(launcherArt.style.backgroundImage, oldBackground);
  f.holdUI();
  const beforeEvents = f.received.length;
  await choice.emit('click'); // Real handle/save reply finishes; only the push is held.
  assert.deepEqual(f.requests.at(-1), { action: 'saveUiState', avatarId: '2' });
  assert.deepEqual(f.store.get('ui'), before);
  assert.equal(image.src, '/media/avatars/1.png');
  assert.equal(choice.getAttribute('aria-checked'), 'false');
  assert.equal(characterArt.style.backgroundImage, oldBackground);
  assert.equal(launcherArt.style.backgroundImage, oldBackground);
  assert.equal(f.received.length, beforeEvents);
  f.releaseUI();
  assert.equal(image.src, '/media/avatars/2.png');
  assert.equal(choice.getAttribute('aria-checked'), 'true');
  assert.equal(f.store.get('ui').avatarId, '2');

  f.holdUI();
  await background.emit('click');
  assert.deepEqual(f.requests.at(-1), { action: 'saveUiState', backgroundId: 'folder-02' });
  assert.equal(f.store.get('ui').backgroundId, 'folder-01');
  assert.equal(characterArt.style.backgroundImage, oldBackground);
  assert.equal(launcherArt.style.backgroundImage, oldBackground);
  assert.equal(background.getAttribute('aria-checked'), 'false');
  f.releaseUI();
  assert.equal(f.store.get('ui').backgroundId, 'folder-02');
  assert.equal(background.getAttribute('aria-checked'), 'true');
  assert.equal(characterArt.style.backgroundImage, 'url("/media/backgrounds/folder-02.png")');
  assert.equal(launcherArt.style.backgroundImage, 'url("/media/backgrounds/folder-02.png")');
  assert.equal(image.src, '/media/avatars/2.png');
  assert.deepEqual(f.received.slice(beforeEvents), ['uiState', 'uiState']);
});

test('联动 8：语音开关阻止新播放、停止当前播放并清除状态，再开后点击恢复', async t => {
  const f = await page(t);
  const enable = voiceEnabled => f.push({ event: 'uiState', ...f.store.get('ui'), voiceEnabled });
  enable(false);
  await avatar(f).emit('click');
  assert.equal(f.browser.audios.length, 0);
  assert.equal(f.store.get('voicePlaying'), false);
  enable(true);
  assert.equal(f.browser.audios.length, 0, 'enabling voice is not a playback request');
  await avatar(f).emit('click');
  assert.equal(f.browser.audios.length, 1);
  const first = f.browser.audios[0];
  assert.equal(first.plays, 1);
  assert.equal(f.store.get('voicePlaying'), true);
  assert.ok(avatar(f).classList.contains('playing'));
  enable(false);
  assert.equal(first.pauses, 1);
  assert.equal(f.store.get('voicePlaying'), false);
  assert.equal(avatar(f).classList.contains('playing'), false);
  await avatar(f).emit('click');
  assert.equal(f.browser.audios.length, 1);
  enable(true);
  assert.equal(f.browser.audios.length, 1);
  await avatar(f).emit('click');
  assert.equal(f.browser.audios.length, 2);
  assert.equal(f.browser.audios[1].plays, 1);
  assert.equal(f.store.get('voicePlaying'), true);
});
