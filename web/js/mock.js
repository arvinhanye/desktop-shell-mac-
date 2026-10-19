const parameters = new Map([
  ['getConfig', []], ['setHitRegions', ['regions']],
  ['focusInput', []], ['blurInput', []],
  ['openProject', ['projectId']], ['openProjectWith', ['projectId', 'appId']],
  ['launchApp', ['appId']], ['saveUiState', ['avatarId', 'backgroundId']],
  ['addTodo', ['text', 'projectId']], ['setTodoDone', ['todoId', 'done']],
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
      { id: 'reading', name: '阅读笔记', tags: ['notes'], apps: ['safari'], hasReminders: true },
      { id: 'sketches', name: '草图', tags: [], hasReminders: false },
    ],
    apps: [
      { id: 'cursor', name: 'Cursor', iconUrl: '/media/app-icons/cursor.png' },
      { id: 'safari', name: 'Safari', iconUrl: '/media/app-icons/safari.png' },
      { id: 'notes', name: '备忘录', iconUrl: '/media/app-icons/notes.png' },
      { id: 'figma', name: 'Figma', iconUrl: null },
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
  const dateAt = offset => {
    const date = new Date(today);
    date.setDate(date.getDate() + offset);
    return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
  };
  let todos = [
    { id: 'mock-1', text: '检查桌面组件', done: false, projectId: 'desktop-shell', due: { date: dateAt(1), time: '09:00' } },
    { id: 'mock-2', text: '整理阅读笔记', done: false, projectId: 'reading', due: null },
    { id: 'mock-3', text: '今天的提醒', done: false, projectId: null, due: { date: dateAt(0), time: null } },
    { id: 'mock-4', text: '过期待办示例', done: false, projectId: null, due: { date: dateAt(-1), time: '18:00' } },
    { id: 'mock-5', text: '已完成示例', done: true, projectId: null, due: null },
  ];
  let nextTodo = 6;
  let ui = { avatarId: null, backgroundId: null, voiceEnabled: true };
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
  const emitTodos = () => emit({ event: 'todos', access: todosAccess, items: todosAccess === 'granted' ? todos.slice(0, 500) : [] });
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
        case 'focusInput':
        case 'blurInput':
          return null;
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
          const todo = { id: `mock-${nextTodo++}`, text, done: false, projectId: project?.hasReminders ? project.id : null, due: null };
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
    setTodosAccess(access) {
      if (!accessStates.has(access)) fail('invalid');
      todosAccess = access;
      emitTodos();
    },
    state: Object.freeze({ get sound() { return sound; }, get paused() { return paused; }, get todosAccess() { return todosAccess; } }),
  };
}
