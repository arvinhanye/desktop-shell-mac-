// 效果图的模拟数据与交互。只用于在浏览器里预览设计，M4 会按定稿在 web/ 里正式实现。
const $ = id => document.getElementById(id);
const root = document.documentElement;
const pad = n => String(n).padStart(2, '0');

// —— 模拟数据（和 M3 的 mock / config 结构一致，内容是示例） ——
const config = {
  character: { name: '爱弥斯' },
  greetings: [
    { from: 0, title: '深夜了', wish: '时辰已晚，且捻熄灯盏，良宵安枕' },
    { from: 6, title: '早上好', wish: '晨光熹微，愿您涤尽尘扰，理裳启新日' },
    { from: 12, title: '下午好', wish: '愿清风伴您今日，时刻皆有阳光满心' },
    { from: 18, title: '傍晚了', wish: '且舒怀抱，自在一刻尽欢愉' },
    { from: 20, title: '晚上好', wish: '且舒怀抱，自在一刻尽欢愉' },
    { from: 21, title: '晚上好', wish: '时辰已晚，且捻熄灯盏，良宵安枕' },
    { from: 23, title: '深夜了', wish: '时辰已晚，且捻熄灯盏，良宵安枕' },
  ],
  projects: [
    { id: 'desktop-shell', name: 'DesktopShell', tags: ['dev'], apps: ['cursor'], hasReminders: true },
    { id: 'thesis', name: '课程论文', tags: ['写作'], apps: ['safari', 'notes'], hasReminders: true },
    { id: 'photos', name: '旅行照片整理', tags: [], apps: [], hasReminders: false },
  ],
  apps: [
    { id: 'cursor', name: 'Cursor', mark: 'Cu' }, { id: 'safari', name: 'Safari', mark: 'Sa' },
    { id: 'notes', name: '备忘录', mark: 'No' }, { id: 'music', name: '音乐', mark: 'Mu' },
    { id: 'mail', name: '邮件', mark: 'Ma' }, { id: 'calendar', name: '日历', mark: 'Ca' },
  ],
};
const avatars = Array.from({ length: 30 }, (_, i) => ({ id: String(i + 1), url: `/media/avatars/${i + 1}.png` }));
const backgrounds = [
  ...Array.from({ length: 6 }, (_, i) => ({ id: `folder-0${i + 1}`, url: `/media/backgrounds/folder-0${i + 1}.png` })),
  { id: 'settings-01', url: '/media/backgrounds/settings-01.png' },
  ...Array.from({ length: 56 }, (_, i) => ({ id: `start-${pad(i + 1)}`, url: `/media/backgrounds/start-${pad(i + 1)}.jpg` })),
];
const today = new Date();
const dayOffset = (offset, time = null) => {
  const d = new Date(today); d.setDate(d.getDate() + offset);
  return { date: `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`, time };
};
let todos = [
  { id: 't1', text: '检查桌面组件的点击区域', done: false, projectId: 'desktop-shell', due: dayOffset(1, '09:00') },
  { id: 't2', text: '整理设计稿的修改意见', done: false, projectId: 'desktop-shell', due: dayOffset(0) },
  { id: 't3', text: '论文第三章初稿', done: false, projectId: 'thesis', due: dayOffset(2) },
  { id: 't4', text: '预约下周的体检', done: false, projectId: null, due: dayOffset(-1, '18:00') },
  { id: 't5', text: '给阳台的植物浇水', done: false, projectId: null, due: null },
  { id: 't6', text: '回复导师的邮件', done: true, projectId: 'thesis', due: null },
];
let nextTodo = 7;
const ui = { avatarId: '1', backgroundId: 'folder-01' };
const state = { selectedProject: null, lowBattery: false, paused: false, denied: false };

// —— 时钟、时段、问候语 ——
const WEEKDAYS_EN = ['SUNDAY', 'MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY', 'FRIDAY', 'SATURDAY'];
const MONTHS_EN = ['JANUARY', 'FEBRUARY', 'MARCH', 'APRIL', 'MAY', 'JUNE', 'JULY', 'AUGUST', 'SEPTEMBER', 'OCTOBER', 'NOVEMBER', 'DECEMBER'];
const WEEKDAYS_CN = ['星期日', '星期一', '星期二', '星期三', '星期四', '星期五', '星期六'];
const phaseForHour = h => (h >= 6 && h < 12 ? 'morning' : h >= 12 && h < 18 ? 'day' : h >= 18 && h < 21 ? 'evening' : 'night');
const PHASE_HOUR = { morning: 9, day: 15, evening: 19, night: 22 };
let phaseOverride = null;

function renderClock() {
  const now = new Date();
  $('date-day').textContent = pad(now.getDate());
  $('date-month').textContent = MONTHS_EN[now.getMonth()];
  $('date-weekday').textContent = WEEKDAYS_EN[now.getDay()];
  $('date-time').textContent = `${pad(now.getHours())}:${pad(now.getMinutes())}`;
  $('date-cn').textContent = `${now.getMonth() + 1}月${now.getDate()}日 ${WEEKDAYS_CN[now.getDay()]}`;
  $('menubar-clock').textContent = `${now.getMonth() + 1}月${now.getDate()}日 ${WEEKDAYS_CN[now.getDay()].replace('星期', '周')}  ${pad(now.getHours())}:${pad(now.getMinutes())}`;
  const phase = phaseOverride ?? phaseForHour(now.getHours());
  root.dataset.phase = phase;
  const hour = phaseOverride ? PHASE_HOUR[phaseOverride] : now.getHours();
  const greeting = config.greetings.filter(g => g.from <= hour).at(-1);
  $('greeting-title').textContent = greeting.title;
  $('greeting-name').textContent = config.character.name;
  $('greeting-wish').textContent = greeting.wish;
  document.querySelectorAll('[data-phase]').forEach(b => { if (b.tagName === 'BUTTON') b.setAttribute('aria-pressed', String(b.dataset.phase === phase)); });
}

// —— 角色卡与外观 ——
function renderAppearance() {
  $('avatar-img').src = avatars.find(a => a.id === ui.avatarId)?.url ?? avatars[0].url;
  const bg = backgrounds.find(b => b.id === ui.backgroundId);
  for (const id of ['character-bg', 'launcher-bg']) $(id).style.backgroundImage = bg ? `url("${bg.url}")` : 'none';
  $('character-name').textContent = config.character.name;
  for (const [gridId, items, key] of [['avatar-grid', avatars, 'avatarId'], ['background-grid', backgrounds, 'backgroundId']]) {
    const grid = $(gridId);
    if (!grid.childElementCount) {
      for (const item of items) {
        const button = document.createElement('button');
        button.type = 'button'; button.className = `thumb ${key === 'backgroundId' ? 'backgrounds-item' : ''}`;
        button.setAttribute('role', 'radio'); button.dataset.id = item.id;
        button.innerHTML = `<img alt="" draggable="false" loading="lazy" src="${item.url}">`;
        button.addEventListener('click', () => { ui[key] = item.id; renderAppearance(); });
        grid.append(button);
      }
    }
    for (const button of grid.children) button.setAttribute('aria-checked', String(button.dataset.id === ui[key]));
  }
}
$('avatar').addEventListener('click', () => {
  const button = $('avatar');
  if (button.classList.contains('playing')) return;   // 播放期间不重复触发
  button.classList.add('playing');
  setTimeout(() => button.classList.remove('playing'), 2400);
});
const setAppearanceOpen = open => {
  $('appearance').classList.toggle('open', open);
  $('toggle-appearance').setAttribute('aria-pressed', String(open));
};
$('open-appearance').addEventListener('click', () => setAppearanceOpen(true));
$('appearance-done').addEventListener('click', () => setAppearanceOpen(false));
$('appearance-reset').addEventListener('click', () => { ui.avatarId = '1'; ui.backgroundId = null; renderAppearance(); });
$('appearance').addEventListener('click', event => { if (event.target === $('appearance')) setAppearanceOpen(false); });

// —— 系统状态 ——
let cpu = 18.4;
const cpuHistory = Array.from({ length: 24 }, () => 10 + Math.random() * 20);
function renderStats() {
  cpu = Math.max(3, Math.min(70, cpu + (Math.random() - 0.5) * 12));
  cpuHistory.push(cpu); cpuHistory.shift();
  const points = cpuHistory.map((v, i) => `${(i / (cpuHistory.length - 1)) * 60},${26 - (v / 100) * 24 - 1}`);
  $('cpu-spark').querySelector('polyline').setAttribute('points', points.join(' '));
  $('cpu-spark').querySelector('polygon').setAttribute('points', `0,26 ${points.join(' ')} 60,26`);
  $('cpu-value').innerHTML = `${cpu.toFixed(1)}<small>%</small>`;
  const mem = 57.5 + (Math.random() - 0.5) * 2;
  $('mem-bar').style.transform = `scaleX(${mem / 100})`;
  $('mem-value').innerHTML = `${mem.toFixed(1)}<small>%</small>`;
  const battery = state.lowBattery ? 15 : 85;
  $('bat-bar').style.transform = `scaleX(${battery / 100})`;
  $('bat-value').innerHTML = `${battery}<small>${state.lowBattery ? '% 用电池' : '% 电源'}</small>`;
}

// —— 项目、待办、启动栏（联动：选中项目 → 过滤待办、高亮相关应用） ——
const appName = id => config.apps.find(a => a.id === id)?.name ?? id;
function renderProjects() {
  const list = $('project-list'); list.replaceChildren();
  for (const project of config.projects) {
    const row = document.createElement('div');
    row.className = `project${state.selectedProject === project.id ? ' selected' : ''}`;
    row.setAttribute('role', 'button'); row.tabIndex = 0;
    row.innerHTML = `<div><div class="project-name"></div><div class="project-tags"></div></div><div class="project-actions"></div>`;
    row.querySelector('.project-name').textContent = project.name;
    for (const tag of project.tags) { const t = document.createElement('span'); t.className = 'tag'; t.textContent = tag; row.querySelector('.project-tags').append(t); }
    const actions = row.querySelector('.project-actions');
    for (const [label, title] of [['访达', '在访达中打开'], ...project.apps.slice(0, 1).map(id => [appName(id), `用 ${appName(id)} 打开`])]) {
      const b = document.createElement('button'); b.type = 'button'; b.className = 'ghost-button'; b.textContent = label; b.title = title;
      b.addEventListener('click', event => event.stopPropagation());
      actions.append(b);
    }
    row.addEventListener('click', () => selectProject(project.id));
    list.append(row);
  }
}
function selectProject(id) {
  state.selectedProject = state.selectedProject === id ? null : id;
  $('toggle-select').setAttribute('aria-pressed', String(Boolean(state.selectedProject)));
  renderProjects(); renderTodos(); renderLauncher();
}
const dueLabel = due => {
  if (!due) return null;
  const [y, m, d] = due.date.split('-').map(Number);
  const target = new Date(y, m - 1, d); const base = new Date(today.getFullYear(), today.getMonth(), today.getDate());
  const diff = Math.round((target - base) / 86400000);
  const day = diff === 0 ? '今天' : diff === 1 ? '明天' : diff === -1 ? '昨天' : `${m}月${d}日`;
  const overdue = diff < 0 || (diff === 0 && due.time && due.time < `${pad(new Date().getHours())}:${pad(new Date().getMinutes())}`);
  return { text: due.time ? `${day} ${due.time}` : day, overdue };
};
const checkSVG = '<svg viewBox="0 0 10 10" aria-hidden="true"><path d="M1.5 5.2 4 7.6 8.6 2.6" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>';
function renderTodos() {
  const project = config.projects.find(p => p.id === state.selectedProject);
  $('todo-scope').textContent = project ? `只看「${project.name}」` : '全部列表';
  $('todo-hint').textContent = project && !project.hasReminders ? '这个项目没有对应的提醒事项列表，新增的提醒会放进默认列表' : '';
  $('todo-input').disabled = state.denied;
  $('todo-input').closest('.todo-add').hidden = state.denied;
  const list = $('todo-list'); list.replaceChildren();
  if (state.denied) {
    list.innerHTML = '<li class="todo-denied"><strong>还不能读取提醒事项</strong>到「系统设置 → 隐私与安全性 → 提醒事项」里允许 DesktopShell</li>';
    return;
  }
  const visible = todos.filter(t => !project || t.projectId === project.id);
  const open = visible.filter(t => !t.done), done = visible.filter(t => t.done);
  if (!visible.length) { list.innerHTML = '<li class="todo-empty">没有待办。在上面输入一条，按回车保存</li>'; return; }
  const add = (todo) => {
    const li = document.createElement('li'); li.className = `todo${todo.done ? ' done' : ''}`;
    li.innerHTML = `<button class="todo-check" type="button" aria-label="${todo.done ? '取消完成' : '完成'}">${checkSVG}</button><div><span class="todo-text"></span></div>`;
    li.querySelector('.todo-text').textContent = todo.text;
    const due = dueLabel(todo.due);
    if (due && !todo.done) { const s = document.createElement('span'); s.className = `todo-due${due.overdue ? ' overdue' : ''}`; s.textContent = due.overdue ? `已过期  ${due.text}` : due.text; li.lastElementChild.append(s); }
    li.querySelector('.todo-check').addEventListener('click', () => { todo.done = !todo.done; renderTodos(); });
    list.append(li);
  };
  open.forEach(add);
  if (done.length) { const s = document.createElement('li'); s.className = 'todo-section'; s.textContent = '今天完成'; list.append(s); done.forEach(add); }
}
$('todo-input').addEventListener('keydown', event => {
  if (event.key === 'Escape') { event.target.blur(); return; }
  if (event.key !== 'Enter' || event.isComposing) return;
  const text = event.target.value.trim(); if (!text) return;
  const project = config.projects.find(p => p.id === state.selectedProject);
  todos.unshift({ id: `t${nextTodo++}`, text, done: false, projectId: project?.hasReminders ? project.id : null, due: null });
  event.target.value = ''; renderTodos();
});
function renderLauncher() {
  const related = new Set(config.projects.find(p => p.id === state.selectedProject)?.apps ?? []);
  const row = $('app-row'); row.replaceChildren();
  for (const app of config.apps) {
    const b = document.createElement('button'); b.type = 'button'; b.className = `app${related.has(app.id) ? ' related' : ''}`; b.title = `启动 ${app.name}`;
    b.innerHTML = '<span class="app-icon"></span><span class="app-name"></span>';
    b.querySelector('.app-icon').textContent = app.mark; b.querySelector('.app-name').textContent = app.name;
    row.append(b);
  }
}

// —— 音频律动（模拟频谱；暂停或页面不可见时停住并归零） ——
const bars = { left: [], right: [] };
for (const side of ['left', 'right']) for (let i = 0; i < 12; i++) { const s = document.createElement('span'); $(`viz-${side}`).append(s); bars[side].push(s); }
let vizFrame = null;
function vizTick(t) {
  vizFrame = null;
  if (state.paused || document.hidden) { for (const s of [...bars.left, ...bars.right]) s.style.transform = 'scaleY(0.02)'; return; }
  const time = t / 1000;
  for (let i = 0; i < 12; i++) {
    const bass = Math.max(0, 1 - i / 14);
    const v = Math.min(1, 0.08 + bass * (0.55 + 0.35 * Math.sin(time * 4.2 + i * 0.5)) * (0.75 + 0.25 * Math.sin(time * 1.3)) + 0.12 * Math.abs(Math.sin(time * 7 + i)));
    bars.left[i].style.transform = `scaleY(${v.toFixed(3)})`;
    bars.right[i].style.transform = `scaleY(${(v * (0.92 + 0.08 * Math.sin(time * 3 + i))).toFixed(3)})`;
  }
  vizFrame = requestAnimationFrame(vizTick);
}
const startViz = () => { if (vizFrame === null) vizFrame = requestAnimationFrame(vizTick); };
document.addEventListener('visibilitychange', startViz);

// —— 模拟的访达图标（右侧两列） ——
const folderSVG = '<svg viewBox="0 0 64 64" aria-hidden="true"><path d="M6 16a4 4 0 0 1 4-4h14l5 5h25a4 4 0 0 1 4 4v29a4 4 0 0 1-4 4H10a4 4 0 0 1-4-4Z" fill="#6cb4ee"/><path d="M6 23h52v27a4 4 0 0 1-4 4H10a4 4 0 0 1-4-4Z" fill="#8ccaf7"/></svg>';
['资料', '截图', '课程', '作业', '照片', '安装包', '素材', '笔记', '下载', '文档', '代码', '归档', '音乐', '表格', '设计', '临时'].forEach(name => {
  const d = document.createElement('div'); d.className = 'sys-icon'; d.innerHTML = `${folderSVG}<span>${name}</span>`; $('icons').append(d);
});

// —— 效果图控制栏 ——
const press = (id, value) => $(id).setAttribute('aria-pressed', String(value));
document.querySelectorAll('.controls [data-phase]').forEach(b => b.addEventListener('click', () => { phaseOverride = b.dataset.phase; renderClock(); }));
$('toggle-select').addEventListener('click', () => selectProject(state.selectedProject ? state.selectedProject : 'desktop-shell'));
$('toggle-lowbat').addEventListener('click', () => {
  state.lowBattery = !state.lowBattery; press('toggle-lowbat', state.lowBattery);
  root.toggleAttribute('data-low-battery', state.lowBattery);
  setPaused(state.lowBattery || $('toggle-paused').getAttribute('aria-pressed') === 'true'); renderStats();
});
function setPaused(paused) {
  state.paused = paused; root.toggleAttribute('data-paused', paused);
  const video = document.querySelector('.wallpaper'); if (paused) video.pause(); else video.play().catch(() => {});
  startViz();
}
$('toggle-paused').addEventListener('click', () => { const on = $('toggle-paused').getAttribute('aria-pressed') !== 'true'; press('toggle-paused', on); setPaused(on || state.lowBattery); });
$('toggle-denied').addEventListener('click', () => { state.denied = !state.denied; press('toggle-denied', state.denied); renderTodos(); });
$('toggle-appearance').addEventListener('click', () => setAppearanceOpen(!$('appearance').classList.contains('open')));
$('toggle-icons').addEventListener('click', () => { const hidden = $('icons').classList.toggle('hidden'); press('toggle-icons', !hidden); });
$('toggle-actual').addEventListener('click', () => { const on = $('viewer').classList.toggle('actual'); press('toggle-actual', on); fit(); });
document.addEventListener('contextmenu', event => { if (event.target.closest('#stage')) event.preventDefault(); });

// —— 缩放到窗口 ——
function fit() {
  const viewer = $('viewer');
  const scale = Math.min(viewer.clientWidth / 1792, viewer.clientHeight / 1120);
  $('stage').style.transform = viewer.classList.contains('actual') ? 'none' : `translate(-50%, -50%) scale(${scale})`;
}
window.addEventListener('resize', fit);

renderClock(); renderAppearance(); renderStats(); renderProjects(); renderTodos(); renderLauncher(); fit(); startViz();
setInterval(renderClock, 30_000);
setInterval(renderStats, 5_000);
