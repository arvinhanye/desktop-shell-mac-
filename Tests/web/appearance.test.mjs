import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import appearance, { appearanceSelection, appearanceChange } from '../../web/widgets/appearance.js';
import character from '../../web/widgets/character.js';
import launcher from '../../web/widgets/launcher.js';
import { createStore, initialState } from '../../web/js/store.js';
import { applyEvent } from '../../web/js/bridge.js';

const media = {
  avatars: [{ id: '1', url: '/provided/first.png' }, { id: '2', url: '/provided/second.png' }],
  backgrounds: [{ id: 'bg', url: '/provided/background.jpg' }], voices: [],
};
for (const [ui, expected] of [
  [{ avatarId: null, backgroundId: null }, { avatarId: '1', backgroundId: null }],
  [{ avatarId: 'missing', backgroundId: 'missing' }, { avatarId: '1', backgroundId: null }],
  [{ avatarId: '2', backgroundId: 'bg' }, { avatarId: '2', backgroundId: 'bg' }],
  [undefined, { avatarId: '1', backgroundId: null }],
]) {
  test(`appearance: selected ids for ${JSON.stringify(ui)}`, () => {
    assert.deepEqual(appearanceSelection(media, ui), expected);
  });
}
test('appearance: no media has no selected ids', () => {
  assert.deepEqual(appearanceSelection(null, initialState.ui), { avatarId: null, backgroundId: null });
  assert.deepEqual(appearanceSelection({ avatars: [], backgrounds: [] }, { avatarId: '2', backgroundId: 'bg' }), { avatarId: null, backgroundId: null });
});
for (const [ui, key, id, expected] of [
  [initialState.ui, 'avatarId', '1', null],
  [{ avatarId: 'missing' }, 'avatarId', '1', null],
  [initialState.ui, 'avatarId', '2', { avatarId: '2' }],
  [initialState.ui, 'backgroundId', 'bg', { backgroundId: 'bg' }],
  [{ backgroundId: 'bg' }, 'backgroundId', 'bg', null],
  [initialState.ui, 'avatarId', 'missing', null],
  [initialState.ui, 'backgroundId', 'missing', null],
  [initialState.ui, 'other', '2', null],
  [{ avatarId: '2', backgroundId: 'bg' }, 'reset', null, { avatarId: null, backgroundId: null }],
  [initialState.ui, 'reset', null, { avatarId: null, backgroundId: null }],
]) {
  test(`appearance: request ${key}=${id} from ${JSON.stringify(ui)}`, () => {
    assert.deepEqual(appearanceChange(media, ui, key, id), expected);
  });
}

// Minimal DOM/event model, matching the existing web tests; browser checks cover layout.
function fixture(initial = {}, send = async () => null) {
  const timers = new Map(), calls = [], nodes = [];
  let nextTimer = 0;
  class Element {
    constructor(tag) {
      this.tagName = tag.toUpperCase(); this.ownerDocument = doc; this.children = [];
      this.parentElement = null; this.className = ''; this.attributes = {}; this.dataset = {};
      this.style = {}; this.listeners = new Map(); this._text = ''; this.hidden = false; nodes.push(this);
    }
    append(...children) {
      for (let child of children) {
        if (typeof child === 'string') { const text = new Element('#text'); text._text = child; child = text; }
        child.parentElement = this; this.children.push(child);
      }
    }
    replaceChildren(...children) {
      this.children.forEach(child => { child.parentElement = null; });
      this.children = []; this._text = ''; this.append(...children);
    }
    setAttribute(key, value) { this.attributes[key] = String(value); }
    getAttribute(key) { return this.attributes[key] ?? null; }
    removeAttribute(key) { delete this.attributes[key]; delete this[key]; }
    set textContent(text) { this.replaceChildren(); this._text = String(text); }
    get textContent() { return this._text + this.children.map(child => child.textContent).join(''); }
    set innerHTML(value) {
      assert.ok(value.startsWith('<svg ') && value.endsWith('</svg>'), 'Only a static SVG uses innerHTML');
      const svg = new Element('svg'); svg.source = value; this.replaceChildren(svg);
    }
    get classList() {
      return { contains: name => this.className.split(' ').includes(name), toggle: (name, force) => {
        const names = new Set(this.className.split(' ').filter(Boolean));
        if (force) names.add(name); else names.delete(name); this.className = [...names].join(' ');
      } };
    }
    addEventListener(type, fn) {
      if (!this.listeners.has(type)) this.listeners.set(type, new Set()); this.listeners.get(type).add(fn);
    }
    removeEventListener(type, fn) { this.listeners.get(type)?.delete(fn); }
    emit(type, detail = {}) {
      const event = { type, target: this, ...detail };
      for (let node = this; node; node = node.parentElement) {
        for (const fn of [...(node.listeners.get(type) ?? [])]) fn(event);
      }
    }
  }
  const win = {
    setTimeout(callback, delay) { timers.set(++nextTimer, { callback, delay }); return nextTimer; },
    clearTimeout(id) { timers.delete(id); },
  };
  const doc = { defaultView: win, createElement: tag => new Element(tag) };
  const store = createStore({ ...initialState, media, ...initial });
  const bridge = { send(action, payload) { calls.push({ action, payload }); return send(action, payload); } };
  return { host: doc.createElement('section'), doc, store, bridge, timers, calls, nodes };
}
const all = (root, cls) => [root, ...root.children.flatMap(child => all(child, cls))].filter(node => node.className.split(' ').includes(cls));
const one = (root, cls) => { const result = all(root, cls)[0]; assert.ok(result, `missing .${cls}`); return result; };
const flush = () => new Promise(resolve => setImmediate(resolve));
const deferred = () => {
  let resolve, reject; const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
};
const publishUI = (f, patch) => applyEvent(f.store, { event: 'uiState', ...f.store.get('ui'), ...patch });

test('appearance: synchronous mount creates specified dialog, controls, lazy radios and hidden hit region', () => {
  const f = fixture(); const cleanup = appearance.mount(f.host, f);
  assert.equal(appearance.name, 'appearance'); assert.equal(appearance.css, 'appearance.css');
  assert.equal(typeof cleanup, 'function');
  const overlay = one(f.host, 'appearance-overlay'), panel = one(overlay, 'appearance-panel');
  assert.equal(overlay.hidden, true); assert.equal(overlay.getAttribute('data-hit'), '');
  assert.equal(panel.getAttribute('data-glass'), ''); assert.equal(panel.getAttribute('role'), 'dialog');
  assert.equal(panel.getAttribute('aria-label'), '外观');
  assert.deepEqual(panel.children.map(node => node.className), ['appearance-head', 'appearance-scroll']);
  assert.equal(one(panel, 'appearance-head').children[0].textContent, '外观');
  const actions = one(panel, 'appearance-actions');
  assert.deepEqual(actions.children.map(node => node.className), ['card-meta', 'ghost-button', 'primary-button']);
  assert.equal(actions.children[0].textContent, ''); assert.equal(actions.children[1].textContent, '恢复默认');
  assert.equal(actions.children[2].textContent, '完成');
  for (const [cls, label, expected] of [['avatars', '头像', media.avatars], ['backgrounds', '背景', media.backgrounds]]) {
    const grid = one(panel, cls);
    assert.equal(grid.getAttribute('role'), 'radiogroup'); assert.equal(grid.getAttribute('aria-label'), label);
    assert.equal(grid.children.length, expected.length);
    for (const [i, button] of grid.children.entries()) {
      assert.equal(button.type, 'button'); assert.equal(button.getAttribute('role'), 'radio');
      assert.equal(button.dataset.id, expected[i].id); assert.equal(button.children[0].src, expected[i].url);
      assert.equal(button.children[0].loading, 'lazy'); assert.equal(button.children[0].draggable, false);
      assert.equal(button.children[0].alt, '');
      assert.equal(button.classList.contains('background-thumb'), cls === 'backgrounds');
    }
  }
  assert.equal(one(panel, 'avatars').children[0].getAttribute('aria-checked'), 'true');
  assert.equal(one(panel, 'backgrounds').children[0].getAttribute('aria-checked'), 'false'); cleanup();
});
test('appearance: saves only ids, ignores replies until push, and preserves thumbnail nodes on UI change', async () => {
  const request = deferred(); const f = fixture({}, () => request.promise); const cleanup = appearance.mount(f.host, f);
  const avatars = one(f.host, 'avatars'), backgrounds = one(f.host, 'backgrounds');
  const original = [...avatars.children];
  original[0].emit('click'); assert.equal(f.calls.length, 0);
  original[1].emit('click');
  assert.deepEqual(f.calls, [{ action: 'saveUiState', payload: { avatarId: '2' } }]);
  assert.equal(original[0].getAttribute('aria-checked'), 'true'); assert.equal(f.store.get('ui').avatarId, null);
  request.resolve({ avatarId: '2', backgroundId: 'bg' }); await flush();
  assert.equal(f.store.get('ui').avatarId, null); assert.equal(original[1].getAttribute('aria-checked'), 'false');
  publishUI(f, { avatarId: '2' }); assert.deepEqual(avatars.children, original);
  original[1].emit('click'); assert.equal(f.calls.length, 1);
  backgrounds.children[0].emit('click');
  assert.deepEqual(f.calls[1], { action: 'saveUiState', payload: { backgroundId: 'bg' } });
  publishUI(f, { backgroundId: 'bg' }); one(f.host, 'ghost-button').emit('click');
  assert.deepEqual(f.calls[2], { action: 'saveUiState', payload: { avatarId: null, backgroundId: null } });
  assert.equal(original[1].getAttribute('aria-checked'), 'true');
  publishUI(f, { avatarId: null, backgroundId: null });
  assert.equal(original[0].getAttribute('aria-checked'), 'true');
  assert.equal(backgrounds.children[0].getAttribute('aria-checked'), 'false'); cleanup();
});
test('appearance: media rebuilds grids, removes old listeners and applies fallback selection', () => {
  const f = fixture({ ui: { ...initialState.ui, avatarId: '2', backgroundId: 'bg' } });
  const cleanup = appearance.mount(f.host, f); const old = one(f.host, 'avatars').children[1];
  f.store.set({ media: { avatars: [{ id: '3', url: '/new.png' }], backgrounds: [], voices: [] } });
  assert.notEqual(one(f.host, 'avatars').children[0], old);
  assert.equal(one(f.host, 'avatars').children[0].getAttribute('aria-checked'), 'true');
  assert.equal(one(f.host, 'backgrounds').children.length, 0);
  old.emit('click'); assert.equal(f.calls.length, 0); cleanup();
});
test('appearance: only Done and the overlay itself close; panel clicks and Esc do not', () => {
  const f = fixture({ appearanceOpen: true }); const cleanup = appearance.mount(f.host, f);
  const overlay = one(f.host, 'appearance-overlay'); assert.equal(overlay.hidden, false);
  one(f.host, 'appearance-panel').emit('click'); assert.equal(f.store.get('appearanceOpen'), true);
  overlay.emit('keydown', { key: 'Escape' }); assert.equal(f.store.get('appearanceOpen'), true);
  overlay.emit('click'); assert.equal(f.store.get('appearanceOpen'), false); assert.equal(overlay.hidden, true);
  f.store.set({ appearanceOpen: true }); one(f.host, 'primary-button').emit('click');
  assert.equal(f.store.get('appearanceOpen'), false); assert.equal(overlay.hidden, true); cleanup();
});
test('appearance: failure message clears after 3 seconds; repeated failure restarts the timeout', async () => {
  const f = fixture({}, async () => { throw new Error('failed'); }); const cleanup = appearance.mount(f.host, f);
  one(f.host, 'ghost-button').emit('click'); await flush();
  const message = one(f.host, 'card-meta'); assert.equal(message.textContent, '保存失败，请再试一次');
  const firstId = [...f.timers.keys()][0]; assert.equal(f.timers.get(firstId).delay, 3000);
  one(f.host, 'ghost-button').emit('click'); await flush();
  assert.equal(f.timers.size, 1); assert.equal(f.timers.has(firstId), false);
  const [id, timer] = [...f.timers][0]; f.timers.delete(id); timer.callback();
  assert.equal(message.textContent, ''); cleanup();
});
test('appearance: sync send failure is handled and successful retry clears the message and timer', async () => {
  let fail = true; const f = fixture({}, () => { if (fail) throw new Error('failed'); return Promise.resolve(); });
  const cleanup = appearance.mount(f.host, f); one(f.host, 'ghost-button').emit('click'); await flush();
  assert.equal(one(f.host, 'card-meta').textContent, '保存失败，请再试一次');
  fail = false; one(f.host, 'ghost-button').emit('click'); await flush();
  assert.equal(one(f.host, 'card-meta').textContent, ''); assert.equal(f.timers.size, 0); cleanup();
});
test('appearance: cleanup removes timers/listeners/subscriptions and ignores in-flight failures', async () => {
  const pending = deferred(); let count = 0;
  const f = fixture({}, () => ++count === 1 ? Promise.reject(new Error('failed')) : pending.promise);
  const cleanup = appearance.mount(f.host, f); one(f.host, 'ghost-button').emit('click'); await flush();
  assert.equal(f.timers.size, 1); one(f.host, 'ghost-button').emit('click');
  const avatars = [...one(f.host, 'avatars').children], overlay = one(f.host, 'appearance-overlay');
  cleanup(); cleanup(); assert.equal(f.timers.size, 0);
  pending.reject(new Error('after cleanup')); await flush(); assert.equal(f.timers.size, 0);
  one(f.host, 'ghost-button').emit('click'); assert.equal(f.calls.length, 2);
  f.store.set({ appearanceOpen: true, media: { avatars: [] } }); publishUI(f, { avatarId: '2' });
  assert.equal(overlay.hidden, true); assert.deepEqual(one(f.host, 'avatars').children, avatars);
  assert.ok(f.nodes.every(node => [...node.listeners.values()].every(set => set.size === 0)));
});
test('character: specified DOM, literal user text, media defaults and null config', () => {
  const f = fixture({ config: { character: { name: '<img onerror=alert(1)>', motto: '<script>text</script>' } } });
  const cleanup = character.mount(f.host, f); assert.equal(typeof cleanup, 'function');
  assert.equal(character.name, 'character'); assert.equal(character.css, 'character.css');
  assert.equal(f.host.getAttribute('aria-label'), '角色卡'); const card = one(f.host, 'character-card');
  assert.ok(card.classList.contains('card'));
  assert.deepEqual(card.children.map(node => node.className), ['card-art', 'avatar-button', 'appearance-button', 'character-info']);
  const avatar = one(card, 'avatar-button'), image = avatar.children[0];
  assert.equal(avatar.type, 'button'); assert.equal(avatar.getAttribute('aria-label'), '播放一句语音');
  assert.equal(image.tagName, 'IMG'); assert.equal(image.alt, ''); assert.equal(image.draggable, false);
  assert.equal(image.src, media.avatars[0].url); assert.equal(image.hidden, false);
  assert.equal(one(card, 'card-art').style.backgroundImage, 'none');
  assert.equal(one(card, 'character-name').textContent, '<img onerror=alert(1)>');
  assert.equal(one(card, 'character-motto').textContent, '<script>text</script>');
  assert.equal(one(card, 'appearance-button').textContent.trim(), '外观');
  f.store.set({ config: { character: { name: '爱弥斯', motto: null } } });
  assert.equal(one(card, 'character-name').textContent, '爱弥斯'); assert.equal(one(card, 'character-motto').textContent, '');
  f.store.set({ config: null, media: { avatars: [], backgrounds: [] } });
  assert.equal(one(card, 'character-name').textContent, ''); assert.equal(image.hidden, true);
  assert.equal(image.getAttribute('src'), null); cleanup();
});
test('character: avatar requests voice only when idle; playback class and appearance opening use store', () => {
  const f = fixture({ ui: { ...initialState.ui, voiceEnabled: false }, paused: true });
  const cleanup = character.mount(f.host, f); const avatar = one(f.host, 'avatar-button');
  avatar.emit('click'); assert.equal(f.store.get('voiceRequest'), 1);
  f.store.set({ voicePlaying: true }); assert.equal(avatar.classList.contains('playing'), true);
  avatar.emit('click'); assert.equal(f.store.get('voiceRequest'), 1);
  f.store.set({ voicePlaying: false }); avatar.emit('click'); assert.equal(f.store.get('voiceRequest'), 2);
  assert.equal(avatar.classList.contains('playing'), false);
  one(f.host, 'appearance-button').emit('click'); assert.equal(f.store.get('appearanceOpen'), true);
  assert.deepEqual(f.calls, []); cleanup();
  avatar.emit('click'); assert.equal(f.store.get('voiceRequest'), 2);
  f.store.set({ voicePlaying: true, config: { character: { name: 'changed' } }, media: { avatars: [] } });
  publishUI(f, { backgroundId: 'bg' });
  assert.equal(avatar.classList.contains('playing'), false); assert.equal(one(f.host, 'character-name').textContent, '');
  assert.equal(one(f.host, 'card-art').style.backgroundImage, 'none');
  assert.ok(f.nodes.every(node => [...node.listeners.values()].every(set => set.size === 0)));
});
test('appearance integration: pushed selection updates character and launcher together without optimism', async () => {
  const f = fixture(); const cardHost = f.doc.createElement('section'), launcherHost = f.doc.createElement('section');
  const cleanups = [appearance.mount(f.host, f), character.mount(cardHost, f), launcher.mount(launcherHost, f)];
  one(f.host, 'avatars').children[1].emit('click'); one(f.host, 'backgrounds').children[0].emit('click'); await flush();
  assert.equal(one(cardHost, 'avatar-button').children[0].src, media.avatars[0].url);
  assert.equal(one(launcherHost, 'card-art').style.backgroundImage, 'none');
  publishUI(f, { avatarId: '2', backgroundId: 'bg' });
  assert.equal(one(cardHost, 'avatar-button').children[0].src, media.avatars[1].url);
  const background = `url(${JSON.stringify(media.backgrounds[0].url)})`;
  assert.equal(one(cardHost, 'card-art').style.backgroundImage, background);
  assert.equal(one(launcherHost, 'card-art').style.backgroundImage, background);
  publishUI(f, { avatarId: 'missing', backgroundId: 'missing' });
  assert.equal(one(cardHost, 'avatar-button').children[0].src, media.avatars[0].url);
  assert.equal(one(cardHost, 'card-art').style.backgroundImage, 'none');
  cleanups.forEach(cleanup => cleanup());
});
test('appearance integration: all three widgets are registered in main', async () => {
  const source = await readFile(new URL('../../web/js/main.js', import.meta.url), 'utf8');
  const list = source.match(/const WIDGETS = \[([^\]]+)\]/)?.[1] ?? '';
  for (const name of ['character', 'appearance', 'voice']) assert.ok(list.includes(`'${name}'`), name);
});
