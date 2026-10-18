export default {
  name: 'devpanel',
  css: 'devpanel.css',
  mount(host, { store, bridge, hitRegions }) {
    const doc = host.ownerDocument;
    const win = doc.defaultView;
    const dispose = [];
    let destroyed = false;
    host.classList.add('card', 'devpanel');
    const node = (tag, text = '', className = '') => {
      const element = doc.createElement(tag);
      element.textContent = text;
      if (className) element.className = className;
      return element;
    };
    const text = (element, value) => { if (element.textContent !== value) element.textContent = value; };
    const section = title => {
      const element = node('section'); element.append(node('h2', title)); host.append(element); return element;
    };
    const button = (parent, title, action) => {
      const element = node('button', title); element.type = 'button';
      element.addEventListener('click', async () => {
        element.disabled = true;
        try { await action(); }
        catch (error) { record(`✗ ${title}：${error.code ?? error.message}`, false); }
        finally { element.disabled = false; }
      });
      parent.append(element); return element;
    };
    const check = (parent, title, checked, action) => {
      const label = node('label', '', 'devpanel-check');
      const input = node('input'); input.type = 'checkbox'; input.checked = checked;
      input.addEventListener('change', () => action(input.checked));
      label.append(input, node('span', title)); parent.append(label); return input;
    };
    const subscribe = (key, listener) => dispose.push(store.subscribe(key, listener, { immediate: true }));
    const header = node('header'); header.append(node('h1', '骨架自检'), node('span', bridge.mode, 'devpanel-mode')); host.append(header);
    const status = section('状态');
    const readyLine = node('p'), pausedLine = node('p'), phaseLine = node('p'), safeLine = node('p'), hitLine = node('p');
    status.append(readyLine, pausedLine, phaseLine, safeLine, hitLine);
    const appearance = section('外观');
    const uiLine = node('p');
    const avatar = node('img', '', 'devpanel-avatar'); avatar.alt = '当前头像'; avatar.draggable = false; avatar.hidden = true;
    appearance.append(uiLine, avatar);
    const system = section('系统状态'); const statsLine = node('p', '未收到'); system.append(statsLine);
    const spectrum = section('律动');
    const barsHost = node('div', '', 'devpanel-spectrum'); barsHost.setAttribute('aria-label', '12 频段音频律动');
    const bars = Array.from({ length: 12 }, () => node('span')); barsHost.append(...bars); spectrum.append(barsHost);
    const configSection = section('配置'); const configContent = node('div'); configSection.append(configContent);
    const reminders = section('提醒事项'); const todosLine = node('p'), countsLine = node('p', '', 'devpanel-muted'), todoList = node('ul', '', 'devpanel-list');
    reminders.append(todosLine, countsLine, todoList);
    button(reminders, '新增测试提醒', () => invoke('addTodo', { text: `DesktopShell 自检 ${new Date().toLocaleTimeString('zh-CN', { hour12: false })}` }));
    reminders.append(node('p', 'native 模式下会写入系统提醒事项的默认列表，测完请在提醒事项里删掉', 'devpanel-muted'));
    const invalid = section('非法请求自检'); const invalidResults = node('ol', '', 'devpanel-list');
    button(invalid, '发送非法请求', runInvalidRequests); invalid.append(invalidResults);
    const keyboard = section('键盘输入'); const input = node('input'); input.type = 'text'; input.placeholder = '点这里测试键盘输入'; input.setAttribute('aria-label', input.placeholder); keyboard.append(input);
    const phases = section('时段'); const phaseButtons = node('div', '', 'devpanel-actions'); phases.append(phaseButtons);
    for (const [label, phase] of [['早晨', 'morning'], ['白天', 'day'], ['傍晚', 'evening'], ['夜晚', 'night']]) button(phaseButtons, label, () => store.set({ phase }));
    const debug = section('调试开关');
    check(debug, '显示安全区域', false, enabled => doc.getElementById('desktop').toggleAttribute('data-debug-safe-area', enabled));
    let showRegions = false;
    check(debug, '显示点击区域', false, enabled => { showRegions = enabled; drawnRegions = null; scheduleDiagnostics(); });
    if (bridge.mock) {
      check(debug, '模拟声音', bridge.mock.state.sound, value => bridge.mock.setSound(value));
      check(debug, '模拟暂停', bridge.mock.state.paused, value => bridge.mock.setPaused(value));
      check(debug, '模拟提醒事项未授权', bridge.mock.state.todosAccess !== 'granted', value => bridge.mock.setTodosAccess(value ? 'denied' : 'granted'));
    }
    const recent = section('最近结果'); const results = node('ul', '', 'devpanel-list'), events = node('ul', '', 'devpanel-list'), audioCountLine = node('p'); recent.append(results, node('h2', '最近事件'), events, audioCountLine);
    const resultHistory = [], eventHistory = [];
    function record(message, success) {
      if (destroyed) return;
      resultHistory.unshift({ message, success }); resultHistory.splice(6);
      results.replaceChildren(...resultHistory.map(item => node('li', item.message, item.success ? 'devpanel-success' : 'devpanel-error')));
    }
    async function invoke(action, params = {}) {
      try {
        const value = await bridge.send(action, params);
        if (action === 'saveUiState' && value && typeof value === 'object') store.set({ ui: value });
        record(`✓ ${action}${params.appId || params.projectId ? ` ${params.appId ?? params.projectId}` : ''}`, true);
        return { ok: true, value };
      } catch (error) {
        const code = error.code ?? error.message;
        record(`✗ ${action}：${code}`, false);
        return { ok: false, code };
      }
    }
    function renderAppearance() {
      const ui = store.get('ui');
      text(uiLine, `头像：${ui.avatarId ?? '默认'} · 背景：${ui.backgroundId ?? '默认'} · 语音：${ui.voiceEnabled ? '开启' : '关闭'}`);
      const item = store.get('media').avatars.find(item => item.id === ui.avatarId);
      avatar.hidden = !item;
      if (item && avatar.getAttribute('src') !== item.url) avatar.src = item.url;
      else if (!item) avatar.removeAttribute('src');
    }
    function renderConfig() {
      configContent.replaceChildren();
      if (!store.get('ready')) { configContent.append(node('p', '正在获取配置')); return; }
      const config = store.get('config'), media = store.get('media');
      if (!config) { configContent.append(node('p', '未获取到配置')); return; }
      configContent.append(node('p', `${config.character.name} · 问候 ${config.greetings.length} 条 · 头像 ${media.avatars.length} · 背景 ${media.backgrounds.length}`));
      for (const project of config.projects) {
        const row = node('p', '', 'devpanel-actions'); row.append(node('span', project.name));
        button(row, 'Finder', () => invoke('openProject', { projectId: project.id }));
        for (const id of project.apps) {
          const app = config.apps.find(app => app.id === id);
          if (app) button(row, `用 ${app.name} 打开`, () => invoke('openProjectWith', { projectId: project.id, appId: app.id }));
        }
        configContent.append(row);
      }
      const actions = node('div', '', 'devpanel-actions'); configContent.append(actions);
      for (const app of config.apps) button(actions, `启动 ${app.name}`, () => invoke('launchApp', { appId: app.id }));
      for (const [label, key, items] of [['随机头像', 'avatarId', media.avatars], ['随机背景', 'backgroundId', media.backgrounds]]) {
        const control = button(actions, label, () => invoke('saveUiState', { [key]: items[Math.floor(Math.random() * items.length)].id }));
        control.disabled = items.length === 0;
      }
      button(actions, '恢复默认外观', () => invoke('saveUiState', { avatarId: null, backgroundId: null }));
    }
    function renderTodos() {
      const items = store.get('todos');
      text(todosLine, `权限：${store.get('todosAccess')} · ${items.length} 条`);
      const groups = new Map();
      for (const item of items) { const key = item.projectId ?? '未关联'; groups.set(key, (groups.get(key) ?? 0) + 1); }
      text(countsLine, [...groups].map(([key, count]) => `${key} ${count}`).join(' · ') || '暂无提醒');
      todoList.replaceChildren(...items.slice(0, 5).map(item => {
        const li = node('li'), label = node('label', '', 'devpanel-todo'), checkbox = node('input');
        checkbox.type = 'checkbox'; checkbox.checked = item.done; checkbox.setAttribute('aria-label', `完成：${item.text}`);
        checkbox.addEventListener('change', async () => {
          checkbox.disabled = true;
          const result = await invoke('setTodoDone', { todoId: item.id, done: checkbox.checked });
          if (!result.ok) checkbox.checked = item.done;
          checkbox.disabled = false;
        });
        const due = item.due ? `${item.due.date}${item.due.time ? ` ${item.due.time}` : ''}` : '无到期时间';
        label.append(checkbox, node('span', `${item.text} · ${due} · ${item.projectId ?? '未关联'}`)); li.append(label); return li;
      }));
    }
    async function childFrameRequest() {
      const frame = node('iframe'); frame.hidden = true; frame.srcdoc = '';
      let timeout;
      try {
        await new Promise((resolve, reject) => {
          timeout = win.setTimeout(() => reject(new Error('iframe-timeout')), 3000);
          frame.addEventListener('load', resolve, { once: true });
          frame.addEventListener('error', () => reject(new Error('iframe-failed')), { once: true });
          host.append(frame);
        });
        await frame.contentWindow.webkit.messageHandlers.shell.postMessage({ action: 'getConfig' });
        record('✓ 子框架 getConfig', true);
        return { ok: true };
      } catch (error) {
        const code = error.message ?? String(error); record(`✗ 子框架 getConfig：${code}`, false); return { ok: false, code };
      } finally { win.clearTimeout(timeout); frame.remove(); }
    }
    async function runInvalidRequests() {
      invalidResults.replaceChildren();
      const requests = [
        ['deleteFile', {}, 'unknown-action'],
        ['openProject', { projectId: '../etc' }, 'invalid'],
        ['openProject', { projectId: 'desktop-shell', path: '/' }, 'invalid'],
        ['launchApp', { appId: 'no-such-app' }, 'not-found'],
        ['saveUiState', { avatarId: 'no-such-avatar' }, 'not-found'],
        ['setTodoDone', { todoId: 'no-such-todo', done: true }, 'not-found'],
      ];
      for (const [action, params, expected] of requests) {
        const result = await invoke(action, params);
        const ok = !result.ok && result.code === expected;
        invalidResults.append(node('li', `${ok ? '✓' : '✗'} ${action}（预期 ${expected}）：${result.ok ? '成功' : result.code}`, ok ? 'devpanel-success' : 'devpanel-error'));
      }
      if (bridge.mode === 'mock') invalidResults.append(node('li', '子框架来源校验（预期 untrusted）：跳过'));
      else {
        const result = await childFrameRequest(); const ok = !result.ok && result.code === 'untrusted';
        invalidResults.append(node('li', `${ok ? '✓' : '✗'} 子框架 getConfig（预期 untrusted）：${result.ok ? '成功' : result.code}`, ok ? 'devpanel-success' : 'devpanel-error'));
      }
    }

    let audioCount = 0;
    dispose.push(bridge.subscribeEvents(name => {
      if (name === 'audioSpectrum') { audioCount++; scheduleDiagnostics(); return; }
      eventHistory.unshift(`${name} · ${new Date().toLocaleTimeString()}`); eventHistory.splice(6);
      events.replaceChildren(...eventHistory.map(value => node('li', value)));
    }));
    subscribe('ready', value => { text(readyLine, `就绪 ready：${value}`); renderConfig(); });
    subscribe('phase', value => text(phaseLine, `时段 phase：${value}`));
    subscribe('safeArea', value => text(safeLine, `安全区域：${value.top} / ${value.right} / ${value.bottom} / ${value.left}`));
    subscribe('ui', renderAppearance); subscribe('media', () => { renderAppearance(); renderConfig(); });
    subscribe('config', renderConfig); subscribe('todos', renderTodos); subscribe('todosAccess', renderTodos);
    subscribe('systemStats', value => text(statsLine, value
      ? `电量 ${value.battery.level ?? '未知'}% · ${value.battery.charging ? '充电中' : '未充电'} · ${value.battery.onBattery ? '使用电池' : '非电池供电'} · CPU ${value.cpu.toFixed(1)}% · 内存 ${value.memory.percent.toFixed(1)}%`
      : '未收到'));
    let animation = null, diagnostics = null, drawnRegions = null;
    const overlays = [];
    function drawDiagnostics() {
      text(hitLine, `点击区域：${hitRegions.last.length}`);
      text(audioCountLine, `audioSpectrum 累计：${audioCount}`);
      if (drawnRegions === hitRegions.last) return;
      drawnRegions = hitRegions.last;
      overlays.splice(0).forEach(element => element.remove());
      if (showRegions) for (const [x, y, width, height] of drawnRegions) {
        const element = node('div', '', 'hit-overlay'); element.setAttribute('aria-hidden', 'true');
        for (const [property, value] of Object.entries({ left: x, top: y, width, height })) element.style.setProperty(property, `${value}px`);
        doc.body.append(element); overlays.push(element);
      }
    }
    function scheduleDiagnostics() {
      if (destroyed || diagnostics !== null) return;
      diagnostics = win.requestAnimationFrame(() => { diagnostics = null; if (!destroyed) drawDiagnostics(); });
    }
    function drawBars(values) {
      bars.forEach((bar, index) => {
        const transform = `scaleY(${values[index] ?? 0})`;
        if (bar.style.transform !== transform) bar.style.transform = transform;
      });
    }
    function frame(at) {
      animation = null;
      if (destroyed || store.get('paused') || doc.hidden) return;
      const sample = store.get('audioSpectrum');
      const age = sample ? Math.max(0, at - sample.at) : Infinity;
      const decay = age <= 200 ? 1 : Math.max(0, 1 - (age - 200) / 200);
      drawBars(sample ? sample.bands.map(value => value * decay) : []);
      if (decay > 0) animation = win.requestAnimationFrame(frame);
    }
    function updateAnimation() {
      if (destroyed) return;
      const sample = store.get('audioSpectrum');
      // Stay idle until fresh data arrives; resuming must not replay an expired sample.
      if (store.get('paused') || doc.hidden || !sample || win.performance.now() - sample.at >= 400) {
        if (animation !== null) { win.cancelAnimationFrame(animation); animation = null; }
        drawBars([]);
      } else if (animation === null) animation = win.requestAnimationFrame(frame);
      scheduleDiagnostics();
    }
    subscribe('paused', value => {
      text(pausedLine, `暂停 paused：${value}`); pausedLine.classList.toggle('devpanel-warning', value); updateAnimation();
    });
    subscribe('audioSpectrum', updateAnimation);
    const diagnosticsObserver = new win.MutationObserver(records => {
      if (records.some(record => !record.target.closest?.('.devpanel-spectrum, .hit-overlay'))) scheduleDiagnostics();
    });
    diagnosticsObserver.observe(doc.documentElement, { subtree: true, childList: true, attributes: true, attributeFilter: ['class', 'style', 'hidden', 'data-hit'] });
    for (const event of ['resize', 'load']) { win.addEventListener(event, scheduleDiagnostics); dispose.push(() => win.removeEventListener(event, scheduleDiagnostics)); }
    doc.addEventListener('visibilitychange', updateAnimation);
    doc.fonts.ready.then(scheduleDiagnostics);
    scheduleDiagnostics();
    return () => {
      destroyed = true;
      dispose.forEach(unsubscribe => unsubscribe());
      diagnosticsObserver.disconnect(); doc.removeEventListener('visibilitychange', updateAnimation);
      if (animation !== null) win.cancelAnimationFrame(animation);
      if (diagnostics !== null) win.cancelAnimationFrame(diagnostics);
      overlays.forEach(element => element.remove());
      host.replaceChildren();
    };
  },
};
