const parameters = new Map([
  ['getConfig', []], ['setDropRegions', ['regions']], ['setHitRegions', ['regions']], ['setGlassRegions', ['regions']],
  ['focusInput', []], ['blurInput', []],
  ['openProject', ['projectId']], ['openProjectWith', ['projectId', 'appId']],
  ['launchApp', ['appId']], ['saveUiState', ['avatarId', 'backgroundId']],
  ['addTodo', ['text', 'projectId']], ['setTodoDone', ['todoId', 'done']],
  ['addProject', ['path']], ['removeProject', ['projectId']],
  ['getProjectEditOptions', ['projectId']], ['updateProject', ['projectId', 'name', 'appId', 'reminderListOptionId']],
  ['reorderProjects', ['projectIds']],
]);
const accessStates = new Set(['granted', 'denied', 'notDetermined', 'restricted', 'writeOnly']);
const fail = code => { throw new Error(code); };
const requireID = id => {
  if (typeof id !== 'string' || !/^[A-Za-z0-9_-]+$/.test(id)) fail('invalid');
};
const clamp = (value, min, max) => Math.max(min, Math.min(max, value));
const isPlainObject = value => value !== null && typeof value === 'object'
  && [Object.prototype, null].includes(Object.getPrototypeOf(value));

export function createMock({ timers = globalThis, now = () => Date.now(), random = Math.random } = {}) {
  const config = {
    user: { name: 'Arvin' },
    character: { name: '爱弥斯', motto: '愿星光一直落在你走的路上' },
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
      { id: 'website', name: '个人网站', tags: ['dev'], apps: ['cursor', 'safari'], hasReminders: true },
      { id: 'reading', name: '读书笔记', tags: ['阅读'], apps: ['notes'], hasReminders: true },
      { id: 'budget', name: '家庭账本', tags: [], apps: [], hasReminders: false },
    ],
    apps: [
      { id: 'cursor', name: 'Cursor', iconUrl: '/media/app-icons/cursor.png' },
      { id: 'safari', name: 'Safari', iconUrl: '/media/app-icons/safari.png' },
      { id: 'notes', name: '备忘录', iconUrl: '/media/app-icons/notes.png' },
      { id: 'music', name: '音乐', iconUrl: '/media/app-icons/music.png' },
      { id: 'mail', name: '邮件', iconUrl: '/media/app-icons/mail.png' },
      { id: 'calendar', name: '日历', iconUrl: '/media/app-icons/calendar.png' },
      { id: 'missing', name: 'Figma', iconUrl: null },
    ],
  };
  const sequence = (count, make) => Array.from({ length: count }, (_, index) => make(index + 1));
  const pad = number => String(number).padStart(2, '0');
  const background = (id, extension) => ({ id, url: `/media/backgrounds/${id}.${extension}` });
  const media = {
    voices: sequence(54, id => ({ id: String(id), url: `/media/voice/${id}.mp3` })),
    avatars: sequence(30, id => ({ id: String(id), url: `/media/avatars/${id}.png` })),
    backgrounds: [
      ...sequence(6, id => background(`folder-${pad(id)}`, 'png')),
      background('settings-01', 'png'),
      ...sequence(56, id => background(`start-${pad(id)}`, 'jpg')),
    ],
  };
  const today = new Date(now());
  const dateAt = (offset, time = null) => {
    const date = new Date(today);
    date.setDate(date.getDate() + offset);
    return { date: `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`, time };
  };
  let todos = [
    { id: 't1', text: '检查桌面组件的点击区域', done: false, projectId: 'desktop-shell', due: dateAt(1, '09:00') },
    { id: 't2', text: '整理设计稿的修改意见', done: false, projectId: 'desktop-shell', due: dateAt(0) },
    { id: 't3', text: '论文第三章初稿', done: false, projectId: 'thesis', due: dateAt(2) },
    { id: 't4', text: '预约下周的体检', done: false, projectId: null, due: dateAt(-1, '18:00') },
    { id: 't5', text: '给阳台的植物浇水', done: false, projectId: null, due: null },
    { id: 't7', text: '更新个人网站的作品集页面', done: false, projectId: 'website', due: dateAt(3) },
    { id: 't8', text: '交这个月的水电费', done: false, projectId: null, due: dateAt(0, '20:00') },
    { id: 't9', text: '读完《设计心理学》第五章', done: false, projectId: 'reading', due: null },
    { id: 't10', text: '给妈妈打个电话', done: false, projectId: null, due: dateAt(0, '21:30') },
    { id: 't11', text: '把照片备份到移动硬盘', done: false, projectId: null, due: dateAt(5) },
    { id: 't12', text: '确认启动栏图标的显示尺寸', done: false, projectId: 'desktop-shell', due: dateAt(4) },
    { id: 't6', text: '回复导师的邮件', done: true, projectId: 'thesis', due: null },
    { id: 't13', text: '整理桌面，只留两列图标', done: true, projectId: 'desktop-shell', due: null },
  ];
  const bindings = new Map(config.projects.filter(p => p.hasReminders).map(p => [p.id, `list-${p.id}`]));
  let reminderLists = [
    ...config.projects.filter(p => p.hasReminders).map(p => ({ id: bindings.get(p.id), title: p.name, source: 'iCloud', canWrite: true })),
    { id: 'free-1', title: '提醒', source: 'iCloud', canWrite: true },
    { id: 'free-2', title: '提醒', source: '本地', canWrite: true },
    { id: 'readonly', title: '共享参考', source: '共享', canWrite: false },
  ];
  let nextOption = 0;
  const optionTokens = new Map();
  const refreshOptions = lists => {
    for (const id of optionTokens.keys()) if (!lists.some(l => l.id === id)) optionTokens.delete(id);
    for (const list of lists) if (!optionTokens.has(list.id)) optionTokens.set(list.id, `option-${++nextOption}`);
  };
  const rawOption = token => [...optionTokens].find(([, value]) => value === token)?.[0];
  const todoLists = new Map(todos.map(todo => [todo.id, bindings.get(todo.projectId) ?? 'default']));
  const assignedProject = listId => reminderLists.some(list => list.id === listId)
    ? config.projects.find(p => bindings.get(p.id) === listId)?.id ?? null : null;
  let nextTodo = 14;
  let ui = { avatarId: '1', backgroundId: 'folder-01', voiceEnabled: true };
  let sound = true;
  let paused = false;
  let todosAccess = 'granted';
  let receive = null;
  let intervals = [];
  let generation = 0;
  let cpu = 18;
  let memoryPercent = 64;
  let battery = 100;
  // Swift validates String.count (extended grapheme clusters), not UTF-16 length.
  const segmenter = new Intl.Segmenter(undefined, { granularity: 'grapheme' });
  const emit = event => { if (receive) receive(structuredClone(event)); };
  const emitTodos = () => emit({ event: 'todos', access: todosAccess, items: todosAccess === 'granted' ? todos.slice(0, 500).map(todo => ({ ...todo, projectId: assignedProject(todoLists.get(todo.id)) })) : [] });
  const emitConfig = () => emit({ event: 'config', config });
  // Mock-only paths stay private, just like the native config projection.
  const projectPaths = new Map(config.projects.map(project => [project.id, `~/Desktop/${project.name}`]));
  const addProject = path => {
    if (typeof path !== 'string' || !path) fail('invalid');
    let count = 0;
    for (const _ of segmenter.segment(path)) if (++count > 1024) fail('invalid');
    let clean = path.trim().replace(/\/+$/, '');
    const homePath = /^(~|\/Users\/[^/]+)\/.+/;
    if (!homePath.test(clean)) {
      clean = clean.replace(/^～/, '~').replaceAll('／', '/').replace(/\/+$/, '');
    }
    if (!homePath.test(clean)) fail('outside-home');
    if (/\.[a-z0-9]{1,5}$/i.test(clean)) fail('not-directory');
    if (/不存在|missing/.test(clean)) fail('not-found');
    const name = clean.split('/').at(-1);
    if (config.projects.some(project => projectPaths.get(project.id) === clean || project.name === name)) fail('duplicate');
    const base = name.replace(/[^A-Za-z0-9]+/g, '-').replace(/^-+|-+$/g, '').toLowerCase() || 'project';
    let id = base, suffix = 2;
    while (config.projects.some(project => project.id === id)) id = `${base}-${suffix++}`;
    const project = { id, name, tags: [], apps: config.apps.some(app => app.id === 'cursor') ? ['cursor'] : [], hasReminders: false };
    config.projects.push(project);
    projectPaths.set(id, clean);
    emitConfig();
    return structuredClone(project);
  };
  const projectFor = id => config.projects.find(project => project.id === id) ?? fail('not-found');
  const appFor = id => config.apps.find(app => app.id === id) ?? fail('not-found');
  const emitStats = () => {
    cpu = clamp(cpu + (random() - 0.5) * 10, 3, 60);
    memoryPercent = clamp(memoryPercent + (random() - 0.5) * 2, 55, 75);
    const totalBytes = 16 * 1024 ** 3;
    emit({
      event: 'systemStats',
      battery: { level: Math.floor(battery), charging: false, onBattery: false },
      cpu,
      memory: { usedBytes: totalBytes * memoryPercent / 100, totalBytes, percent: memoryPercent },
    });
    battery = Math.max(0, battery - 0.02);
  };

  return {
    async handle(message) {
      if (!isPlainObject(message) || typeof message.action !== 'string') fail('invalid');
      const allowed = parameters.get(message.action);
      if (!allowed) fail('unknown-action');
      if (Object.keys(message).some(key => key !== 'action' && !allowed.includes(key))) fail('invalid');
      switch (message.action) {
        case 'getConfig':
          return structuredClone({ config, media, uiState: ui });
        case 'getProjectEditOptions': {
          requireID(message.projectId); const p = projectFor(message.projectId), id = bindings.get(p.id);
          const list = reminderLists.find(l => l.id === id);
          refreshOptions(todosAccess === 'granted' ? reminderLists : []);
          return structuredClone({ project: { id: p.id, name: p.name, appId: p.apps.find(id => config.apps.some(a => a.id === id)) ?? null },
            access: todosAccess, binding: { status: todosAccess !== 'granted' ? 'unavailable' : !id ? 'none' : !list ? 'missing' : list.canWrite ? 'linked' : 'read-only',
              optionId: todosAccess === 'granted' && list ? optionTokens.get(id) : null },
            lists: todosAccess === 'granted' ? reminderLists.map(l => ({ ...l, id: optionTokens.get(l.id), assignedProjectId: assignedProject(l.id) })) : [] });
        }
        case 'updateProject': {
          requireID(message.projectId); const p = projectFor(message.projectId);
          const fields = ['name','appId','reminderListOptionId'].filter(k => Object.hasOwn(message,k));
          if (!fields.length) fail('invalid');
          const next = { ...p };
          if (Object.hasOwn(message,'name')) {
            if (typeof message.name !== 'string') fail('invalid');
            const name = message.name.trim(), count = [...segmenter.segment(name)].length;
            if (count < 1 || count > 100) fail('invalid'); next.name = name;
          }
          if (Object.hasOwn(message,'appId')) {
            requireID(message.appId); appFor(message.appId); next.apps = [message.appId, ...p.apps.filter(id => id !== message.appId)];
          }
          if (Object.hasOwn(message,'reminderListOptionId')) {
            const id = message.reminderListOptionId;
            if (id !== null) {
              requireID(id); if (todosAccess !== 'granted') fail('failed');
              refreshOptions(reminderLists);
              const list = reminderLists.find(l => l.id === rawOption(id)); if (!list) fail('not-found');
              if (!list.canWrite || [...bindings].some(([owner, value]) => owner !== p.id && value === list.id)) fail('failed');
            }
            next.hasReminders = id !== null;
          }
          if (Object.hasOwn(message,'reminderListOptionId')) {
            if (message.reminderListOptionId === null) bindings.delete(p.id); else bindings.set(p.id, rawOption(message.reminderListOptionId));
          }
          Object.assign(p, next); emitTodos(); emitConfig(); return structuredClone(p);
        }
        case 'reorderProjects': {
          if (!Array.isArray(message.projectIds)) fail('invalid'); const ids = [...message.projectIds]; ids.forEach(requireID);
          if (new Set(ids).size !== ids.length) fail('invalid');
          if (ids.length !== config.projects.length || ids.some(id => !config.projects.some(p => p.id === id))) fail('not-found');
          config.projects = ids.map(projectFor); emitConfig(); return null;
        }
        case 'addProject':
          return addProject(message.path);
        case 'removeProject': {
          requireID(message.projectId);
          projectFor(message.projectId);
          config.projects = config.projects.filter(project => project.id !== message.projectId);
          projectPaths.delete(message.projectId);
          bindings.delete(message.projectId);
          // Removing a project changes routing, not the reminders themselves.
          todos = todos.map(todo => todo.projectId === message.projectId ? { ...todo, projectId: null } : todo);
          emitTodos();
          emitConfig();
          return null;
        }
        case 'focusInput':
        case 'blurInput':
          return null;
        case 'setDropRegions':
        case 'setGlassRegions':
        case 'setHitRegions':
          if (!Array.isArray(message.regions)) fail('invalid');
          return null;
        case 'openProject':
        case 'openProjectWith':
          requireID(message.projectId);
          if (message.action === 'openProjectWith') requireID(message.appId);
          projectFor(message.projectId);
          if (message.action === 'openProjectWith') appFor(message.appId);
          console.info(`mock: ${message.action} ${message.projectId}`);
          return null;
        case 'launchApp':
          requireID(message.appId);
          appFor(message.appId);
          console.info(`mock: launchApp ${message.appId}`);
          return null;
        case 'saveUiState': {
          const fields = ['avatarId', 'backgroundId'].filter(key => Object.hasOwn(message, key));
          if (fields.length === 0) fail('invalid');
          for (const key of fields) if (message[key] !== null) requireID(message[key]);
          const next = { ...ui };
          for (const key of fields) {
            const library = key === 'avatarId' ? media.avatars : media.backgrounds;
            if (message[key] !== null && !library.some(item => item.id === message[key])) fail('not-found');
            next[key] = message[key];
          }
          ui = next;
          emit({ event: 'uiState', ...ui });
          return structuredClone(ui);
        }
        case 'addTodo': {
          if (typeof message.text !== 'string') fail('invalid');
          const text = message.text.trim();
          if (!text) fail('invalid');
          let count = 0;
          for (const _ of segmenter.segment(text)) if (++count > 500) fail('invalid');
          if (Object.hasOwn(message, 'projectId') && message.projectId !== null) requireID(message.projectId);
          if (todosAccess !== 'granted') fail('failed');
          const project = message.projectId == null ? null : projectFor(message.projectId);
          const listId = bindings.get(project?.id);
          if (listId) {
            const list = reminderLists.find(l => l.id === listId);
            if (!list) fail('not-found'); if (!list.canWrite) fail('failed');
          }
          const todo = { id: `mock-${nextTodo++}`, text, done: false, projectId: listId ? project.id : null, due: null };
          todoLists.set(todo.id, listId ?? 'default');
          todos = [...todos, todo];
          emitTodos();
          return structuredClone(todo);
        }
        case 'setTodoDone': {
          requireID(message.todoId);
          if (typeof message.done !== 'boolean') fail('invalid');
          if (todosAccess !== 'granted') fail('failed');
          if (!todos.some(todo => todo.id === message.todoId)) fail('not-found');
          todos = todos.map(todo => todo.id === message.todoId ? { ...todo, done: message.done } : todo);
          emitTodos();
          return null;
        }
      }
    },
    async dropFolders(names) {
      if (!Array.isArray(names) || ![...names].every(name => typeof name === 'string' && name.length > 0)) fail('invalid');
      emit({ event: 'projectDrop', over: true, result: null });
      const result = { added: [], error: null };
      for (const name of names) {
        try {
          const project = addProject(`~/Desktop/${name}`);
          result.added.push({ id: project.id, name: project.name });
        } catch (error) {
          if (result.error === null) result.error = error.message;
        }
      }
      emit({ event: 'projectDrop', over: false, result });
      return structuredClone(result);
    },
    start(receiver) {
      if (receive) return;
      const startingGeneration = ++generation;
      receive = receiver;
      const initialEvents = [
        () => emit({ event: 'safeArea', top: 25, right: 0, bottom: 80, left: 0 }),
        () => emit({ event: 'paused', paused }),
        () => emit({ event: 'uiState', ...ui }),
        emitTodos,
        emitStats,
      ];
      // A synchronous receiver can stop or restart us during any initial event.
      for (const publish of initialEvents) {
        if (generation !== startingGeneration) return;
        publish();
      }
      if (generation !== startingGeneration) return;
      intervals = [
        timers.setInterval(emitStats, 5000),
        timers.setInterval(() => {
          if (!sound || paused) return;
          const time = now() / 1000;
          const bands = sequence(12, band => clamp((Math.sin(time * 3 + band * 0.7) + 1) * 0.35 + random() * 0.2, 0, 1));
          emit({ event: 'audioSpectrum', bands });
        }, 33),
      ];
    },
    stop() {
      generation++;
      for (const interval of intervals) timers.clearInterval(interval);
      intervals = [];
      receive = null;
    },
    setSound(on) {
      if (typeof on !== 'boolean') fail('invalid');
      sound = on;
    },
    setPaused(value) {
      if (typeof value !== 'boolean') fail('invalid');
      paused = value;
      emit({ event: 'paused', paused });
    },
    // Browser mock controls for external EventKit-like changes, never Bridge actions.
    setReminderList(optionId, patch) {
      const id = rawOption(optionId), list = reminderLists.find(l => l.id === id);
      if (!list) fail('not-found');
      if (patch === null) reminderLists = reminderLists.filter(l => l.id !== id);
      else {
        if (!isPlainObject(patch) || Object.keys(patch).some(k => !['title', 'canWrite'].includes(k))) fail('invalid');
        if (Object.hasOwn(patch, 'title') && typeof patch.title !== 'string') fail('invalid');
        if (Object.hasOwn(patch, 'canWrite') && typeof patch.canWrite !== 'boolean') fail('invalid');
        Object.assign(list, patch);
      }
      emitTodos();
    },
    setTodosAccess(access) {
      if (!accessStates.has(access)) fail('invalid');
      todosAccess = access;
      emitTodos();
    },
    state: Object.freeze({ get sound() { return sound; }, get paused() { return paused; }, get todosAccess() { return todosAccess; } }),
  };
}
