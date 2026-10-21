import { createMock } from './mock.js';

const isObject = value => value !== null && typeof value === 'object'
  && [Object.prototype, null].includes(Object.getPrototypeOf(value));
const requireValue = valid => { if (!valid) throw new Error('invalid'); };
const nonnegative = value => Number.isFinite(value) && value >= 0;
const percent = value => Number.isFinite(value) && value >= 0 && value <= 100;
const nullableString = value => value === null || typeof value === 'string';
const accessStates = new Set(['granted', 'denied', 'notDetermined', 'restricted', 'writeOnly']);

function normalizeConfig(config) {
  requireValue(isObject(config));
  requireValue(isObject(config.character) && typeof config.character.name === 'string');
  requireValue(['greetings', 'projects', 'apps'].every(key => Array.isArray(config[key])));
  const projects = [...config.projects].map(project => {
    requireValue(isObject(project));
    return {
      ...project,
      tags: Array.isArray(project.tags) ? project.tags : [],
      apps: Array.isArray(project.apps) ? project.apps : [],
      hasReminders: typeof project.hasReminders === 'boolean' ? project.hasReminders : false,
    };
  });
  const stringOrNull = value => typeof value === 'string' ? value : null;
  const apps = [...config.apps].map(app => {
    requireValue(isObject(app));
    return { ...app, iconUrl: stringOrNull(app.iconUrl) };
  });
  return {
    ...config, projects, apps,
    user: { name: stringOrNull(config.user?.name) },
    character: { ...config.character, motto: stringOrNull(config.character.motto) },
  };
}

function normalizeReply(reply) {
  requireValue(isObject(reply));
  const config = normalizeConfig(reply.config);
  const mediaItems = items => items
    .filter(item => isObject(item) && typeof item.id === 'string' && typeof item.url === 'string')
    .map(({ id, url }) => ({ id, url }));
  const media = isObject(reply.media) && Array.isArray(reply.media.avatars) && Array.isArray(reply.media.backgrounds)
    ? { avatars: mediaItems(reply.media.avatars), backgrounds: mediaItems(reply.media.backgrounds) }
    : { avatars: [], backgrounds: [] };
  media.voices = Array.isArray(reply.media?.voices) ? mediaItems(reply.media.voices) : [];
  const ui = isObject(reply.uiState) ? reply.uiState : {};
  return {
    config,
    media,
    ui: {
      avatarId: typeof ui.avatarId === 'string' ? ui.avatarId : null,
      backgroundId: typeof ui.backgroundId === 'string' ? ui.backgroundId : null,
      voiceEnabled: typeof ui.voiceEnabled === 'boolean' ? ui.voiceEnabled : true,
    },
    ready: true,
  };
}

function normalizeTodo(item) {
  requireValue(isObject(item) && typeof item.id === 'string' && item.id.length > 0);
  requireValue(typeof item.text === 'string' && typeof item.done === 'boolean');
  const projectId = item.projectId === undefined ? null : item.projectId;
  requireValue(nullableString(projectId));
  let due = item.due === undefined ? null : item.due;
  if (due !== null) {
    requireValue(isObject(due) && typeof due.date === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(due.date));
    requireValue(due.time === null || (typeof due.time === 'string' && /^\d{2}:\d{2}$/.test(due.time)));
    due = { date: due.date, time: due.time };
  }
  return { id: item.id, text: item.text, done: item.done, projectId, due };
}

export function applyEvent(store, event, now = () => Date.now()) {
  let eventName = '?';
  try {
    if (typeof event?.event === 'string') eventName = event.event;
    requireValue(isObject(event));
    let patch;
    switch (event.event) {
      case 'config':
        patch = { config: normalizeConfig(event.config) };
        break;
      case 'projectDrop': {
        requireValue(typeof event.over === 'boolean');
        let result = null;
        if (event.result !== null) {
          requireValue(isObject(event.result) && Array.isArray(event.result.added) && nullableString(event.result.error));
          const added = [...event.result.added].map(item => {
            requireValue(isObject(item) && typeof item.id === 'string' && /^[A-Za-z0-9_-]+$/.test(item.id)
              && typeof item.name === 'string');
            return { id: item.id, name: item.name };
          });
          result = { added, error: event.result.error };
        }
        // A fresh envelope for every receipt makes even identical results observable.
        patch = { projectDrop: { over: event.over, result } };
        break;
      }
      case 'safeArea': {
        const { top, right, bottom, left } = event;
        requireValue([top, right, bottom, left].every(nonnegative));
        patch = { safeArea: { top, right, bottom, left } };
        break;
      }
      case 'paused':
        requireValue(typeof event.paused === 'boolean');
        patch = event.paused ? { paused: true, audioSpectrum: null } : { paused: false };
        break;
      case 'systemStats': {
        requireValue(isObject(event.battery) && isObject(event.memory));
        const { charging, onBattery } = event.battery;
        const level = event.battery.level === undefined ? null : event.battery.level;
        requireValue(level === null || (Number.isInteger(level) && percent(level)));
        requireValue(typeof charging === 'boolean' && typeof onBattery === 'boolean' && percent(event.cpu));
        const { usedBytes, totalBytes, percent: memoryPercent } = event.memory;
        requireValue(nonnegative(usedBytes) && nonnegative(totalBytes) && percent(memoryPercent));
        patch = { systemStats: {
          battery: { level, charging, onBattery }, cpu: event.cpu,
          memory: { usedBytes, totalBytes, percent: memoryPercent },
        } };
        break;
      }
      case 'uiState': {
        const avatarId = event.avatarId === undefined ? null : event.avatarId;
        const backgroundId = event.backgroundId === undefined ? null : event.backgroundId;
        const voiceEnabled = event.voiceEnabled === undefined ? true : event.voiceEnabled;
        requireValue(nullableString(avatarId) && nullableString(backgroundId) && typeof voiceEnabled === 'boolean');
        patch = { ui: { avatarId, backgroundId, voiceEnabled } };
        break;
      }
      case 'audioSpectrum': {
        requireValue(Array.isArray(event.bands) && event.bands.length === 12);
        // Spreading also turns holes into undefined so sparse arrays fail validation.
        const bands = [...event.bands];
        requireValue(bands.every(Number.isFinite));
        if (store.get('paused')) return;
        patch = { audioSpectrum: { bands: bands.map(value => Math.max(0, Math.min(1, value))), at: now() } };
        break;
      }
      case 'todos':
        requireValue(accessStates.has(event.access) && Array.isArray(event.items) && event.items.length <= 500);
        patch = { todos: [...event.items].map(normalizeTodo), todosAccess: event.access };
        break;
      default:
        throw new Error('unknown-event');
    }
    // No partial writes: every field/item is checked before publishing the patch.
    store.set(patch);
  } catch {
    console.warn(`bridge: ignored invalid event ${eventName}`);
  }
}

export function createBridge(store, {
  target = globalThis,
  native = target.webkit?.messageHandlers?.shell,
  mock,
  now = () => Date.now(),
} = {}) {
  const mode = native && typeof native.postMessage === 'function' ? 'native' : 'mock';
  const transport = mode === 'mock' ? (mock ?? createMock()) : null;
  const eventListeners = new Set();
  function subscribeEvents(listener) {
    if (typeof listener !== 'function') throw new TypeError('bridge: event listener must be a function');
    const subscription = { listener };
    eventListeners.add(subscription);
    return () => eventListeners.delete(subscription);
  }
  const receive = event => {
    let name = '?';
    try { const value = event?.event; if (typeof value === 'string') name = value; }
    catch { /* Malformed envelopes are diagnosed by applyEvent below. */ }
    try { applyEvent(store, event, now); }
    catch { console.warn('bridge: receive failed'); }
    // Observe transport receipts, not state changes or request replies. Never expose payloads.
    for (const { listener } of [...eventListeners]) {
      try { listener(name); }
      catch { console.warn('bridge: event listener failed'); }
    }
  };
  target.shell = { receive };

  async function send(action, params = {}) {
    try {
      const message = { ...params, action };
      return await (mode === 'native'
        ? new Promise(resolve => resolve(native.postMessage(message)))
        : transport.handle(message));
    } catch (original) {
      const code = typeof original?.message === 'string' ? original.message : String(original);
      console.warn(`bridge: ${action} 失败：${code}`);
      const error = new Error(code);
      error.code = code;
      throw error;
    }
  }

  let started;
  function start() {
    if (!started) {
      // Defer work until the shared promise is assigned, including reentrant listeners.
      started = Promise.resolve().then(() => {
        if (mode === 'mock') transport.start(receive);
        return send('getConfig');
      }).then(reply => {
        store.set(normalizeReply(reply));
      }).catch(() => {
        console.error('bridge: getConfig failed or returned an invalid reply');
        store.set({ ready: true });
      });
    }
    return started;
  }

  return { mode, send, start, subscribeEvents, mock: transport };
}
