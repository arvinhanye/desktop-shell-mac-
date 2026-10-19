const isPlainObject = value => value !== null && typeof value === 'object'
  && [Object.prototype, null].includes(Object.getPrototypeOf(value));
const freezeValue = value => value !== null && typeof value === 'object' ? Object.freeze(value) : value;

export function createStore(initialState) {
  const state = Object.fromEntries(Object.entries(initialState).map(([key, value]) => [key, freezeValue(value)]));
  const listeners = new Map(Object.keys(state).map(key => [key, []]));
  const notify = (listener, value, previous) => {
    try { listener(value, previous); }
    catch (error) { console.error('store: listener failed', error); }
  };

  return {
    get: key => state[key],
    getState: () => ({ ...state }),
    set(patch) {
      if (!isPlainObject(patch)) {
        console.warn('store: patch must be a plain object');
        return;
      }
      const changes = [];
      for (const [key, value] of Object.entries(patch)) {
        if (!listeners.has(key)) {
          console.warn(`store: unknown key ${key}`);
          continue;
        }
        const previous = state[key];
        if (Object.is(value, previous)) continue;
        state[key] = freezeValue(value);
        changes.push({ key, value, previous });
      }
      // Snapshot the whole notification round before any callback can subscribe or unsubscribe.
      const notifications = changes.map(change => ({ ...change, callbacks: [...listeners.get(change.key)] }));
      for (const { value, previous, callbacks } of notifications) {
        for (const { listener } of callbacks) notify(listener, value, previous);
      }
    },
    subscribe(key, listener, { immediate = false } = {}) {
      if (!listeners.has(key) || typeof listener !== 'function') {
        console.warn('store: invalid subscription');
        return () => {};
      }
      // Each subscription has its own identity, even when callbacks are shared.
      const subscription = { listener };
      listeners.get(key).push(subscription);
      if (immediate) notify(listener, state[key], undefined);
      return () => {
        const entries = listeners.get(key);
        const index = entries.indexOf(subscription);
        if (index !== -1) entries.splice(index, 1);
      };
    },
  };
}

export const initialState = {
  ready: false,
  config: null,
  media: { avatars: [], backgrounds: [], voices: [] },
  ui: { avatarId: null, backgroundId: null, voiceEnabled: true },
  todos: [],
  todosAccess: 'unknown',
  safeArea: { top: 0, right: 0, bottom: 0, left: 0 },
  paused: false,
  systemStats: null,
  audioSpectrum: null,
  phase: 'day',
  selectedProject: null,
  now: null,
  appearanceOpen: false,
  voiceRequest: 0,
  voicePlaying: false,
};

export const store = createStore(initialState);
