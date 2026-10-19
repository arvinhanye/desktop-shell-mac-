import { test } from 'node:test';
import assert from 'node:assert/strict';
import voice, { createVoicePlayer, pickVoice } from '../../web/widgets/voice.js';
import { createStore, initialState } from '../../web/js/store.js';

const voices = ['a', 'b', 'c'].map(id => ({ id, url: `/media/voice/${id}.mp3` }));
const deferred = () => {
  let resolve, reject;
  const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
};
const flush = () => new Promise(resolve => setImmediate(resolve));

class FakeAudio {
  constructor(url, play = () => Promise.resolve()) {
    this.url = url; this.playImpl = play; this.plays = 0; this.pauses = 0; this.listeners = new Map();
  }
  play() { this.plays++; return this.playImpl(); }
  pause() { this.pauses++; }
  addEventListener(type, fn) {
    if (!this.listeners.has(type)) this.listeners.set(type, new Set());
    this.listeners.get(type).add(fn);
  }
  removeEventListener(type, fn) { this.listeners.get(type)?.delete(fn); }
  emit(type) { for (const fn of [...(this.listeners.get(type) ?? [])]) fn(); }
  get listenerCount() { return [...this.listeners.values()].reduce((n, set) => n + set.size, 0); }
}
function fixture(initial = {}, play) {
  const store = createStore({ ...initialState, media: { avatars: [], backgrounds: [], voices }, ...initial });
  const audios = [], changes = [];
  store.subscribe('voicePlaying', value => changes.push(value));
  const cleanup = createVoicePlayer({ store, random: () => 0, createAudio: url => {
    const audio = new FakeAudio(url, play); audios.push(audio); return audio;
  } });
  const request = () => store.set({ voiceRequest: store.get('voiceRequest') + 1 });
  return { store, audios, changes, cleanup, request };
}

test('voice: pickVoice covers the pool without repeating the last id', () => {
  assert.equal(pickVoice([], null, () => 0), null);
  assert.equal(pickVoice(voices, null, () => 0), voices[0]);
  assert.equal(pickVoice(voices, null, () => 0.999), voices[2]);
  assert.equal(pickVoice(voices, 'a', () => 0), voices[1]);
  assert.equal(pickVoice(voices, 'b', () => 0.999), voices[2]);
  assert.equal(pickVoice([voices[0]], 'a', () => 0), voices[0]);
  assert.equal(pickVoice(voices, 'removed', () => 0), voices[0]);
});
test('voice: no immediate playback; one request plays synchronously and ended resets once', () => {
  const f = fixture({ voiceRequest: 7 });
  assert.equal(f.audios.length, 0);
  f.request();
  assert.equal(f.audios.length, 1); assert.equal(f.audios[0].url, voices[0].url);
  assert.equal(f.audios[0].plays, 1); assert.equal(f.store.get('voicePlaying'), true);
  f.audios[0].emit('ended'); f.audios[0].emit('error');
  assert.equal(f.store.get('voicePlaying'), false); assert.equal(f.audios[0].listenerCount, 0);
  assert.deepEqual(f.changes, [true, false]); f.cleanup();
});
test('voice: pending and playing requests are ignored; the next play gets a new Audio and another voice', () => {
  const pending = deferred(), f = fixture({}, () => pending.promise);
  f.request(); f.request(); f.request(); assert.equal(f.audios.length, 1);
  f.audios[0].emit('ended'); f.request();
  assert.equal(f.audios.length, 2); assert.notEqual(f.audios[0], f.audios[1]);
  assert.equal(f.audios[1].url, voices[1].url); f.cleanup(); pending.resolve();
});
for (const failure of ['error', 'reject', 'throw']) {
  test(`voice: ${failure} resets state and listeners, allowing retry`, async () => {
    let first = true;
    const pending = deferred();
    const f = fixture({}, () => {
      if (!first) return Promise.resolve();
      first = false;
      if (failure === 'throw') throw new Error('play failed');
      return pending.promise;
    });
    f.request();
    if (failure === 'error') f.audios[0].emit('error');
    if (failure === 'reject') pending.reject(new Error('play denied'));
    await flush();
    assert.equal(f.store.get('voicePlaying'), false); assert.equal(f.audios[0].listenerCount, 0);
    f.request(); assert.equal(f.audios.length, 2); assert.equal(f.store.get('voicePlaying'), true);
    f.cleanup(); pending.resolve();
  });
}
test('voice: disabled, externally playing and empty media requests do not allocate Audio', () => {
  for (const initial of [
    { ui: { ...initialState.ui, voiceEnabled: false } },
    { voicePlaying: true },
    { media: { avatars: [], backgrounds: [], voices: [] } },
  ]) {
    const f = fixture(initial); f.request(); assert.equal(f.audios.length, 0); f.cleanup();
  }
});
test('voice: paused does not prevent or stop playback', () => {
  const f = fixture({ paused: true }); f.request();
  assert.equal(f.audios.length, 1); assert.equal(f.store.get('voicePlaying'), true);
  f.store.set({ paused: false }); f.store.set({ paused: true });
  assert.equal(f.audios[0].pauses, 0); f.cleanup();
});
test('voice: disabling while playing pauses, detaches and resets; re-enabling does not auto-play', () => {
  const f = fixture(); f.request();
  f.store.set({ ui: { ...initialState.ui, voiceEnabled: false } });
  assert.equal(f.audios[0].pauses, 1); assert.equal(f.audios[0].listenerCount, 0);
  assert.equal(f.store.get('voicePlaying'), false);
  f.request(); assert.equal(f.audios.length, 1);
  f.store.set({ ui: initialState.ui }); assert.equal(f.audios.length, 1);
  f.request(); assert.equal(f.audios.length, 2); f.cleanup();
});
test('voice: an unrelated UI update does not stop playback; current media is read per request', () => {
  const f = fixture(); f.request();
  f.store.set({ ui: { ...initialState.ui, avatarId: '2' } });
  assert.equal(f.audios[0].pauses, 0);
  f.audios[0].emit('ended');
  f.store.set({ media: { voices: [{ id: 'new', url: '/provided/new.mp3' }] } });
  f.request(); assert.equal(f.audios[1].url, '/provided/new.mp3'); f.cleanup();
});
test('voice: stale completion or rejection never ends a newer playback', async () => {
  const pending = deferred(), f = fixture({}, () => pending.promise);
  f.request(); const oldEnd = [...f.audios[0].listeners.get('ended')][0];
  f.audios[0].emit('ended'); f.request();
  oldEnd(); assert.equal(f.store.get('voicePlaying'), true);
  // Both play calls share this promise only in this fixture; isolate the late rejection below.
  f.cleanup(); pending.resolve(); await flush();
  const first = deferred(); let count = 0;
  const g = fixture({}, () => ++count === 1 ? first.promise : Promise.resolve());
  g.request(); g.audios[0].emit('ended'); g.request(); first.reject(new Error('late'));
  await flush(); assert.equal(g.store.get('voicePlaying'), true); g.cleanup();
});
test('voice: cleanup is idempotent, stops active audio and removes subscriptions', async () => {
  const pending = deferred(), f = fixture({}, () => pending.promise);
  f.request(); f.cleanup(); f.cleanup();
  assert.equal(f.audios[0].pauses, 1); assert.equal(f.audios[0].listenerCount, 0);
  assert.equal(f.store.get('voicePlaying'), false);
  f.request(); f.store.set({ ui: { ...initialState.ui, voiceEnabled: false } });
  pending.reject(new Error('late after cleanup')); await flush();
  assert.equal(f.audios.length, 1); assert.deepEqual(f.changes, [true, false]);
});
test('voice: synchronous UI disable while publishing playing prevents play()', () => {
  const f = fixture();
  const off = f.store.subscribe('voicePlaying', playing => {
    if (playing) f.store.set({ ui: { ...initialState.ui, voiceEnabled: false } });
  });
  f.request(); assert.equal(f.audios[0].plays, 0); assert.equal(f.audios[0].pauses, 1);
  assert.equal(f.store.get('voicePlaying'), false); off(); f.cleanup();
});
test('voice: Audio construction failure leaves future requests usable', () => {
  const store = createStore({ ...initialState, media: { voices } }); let attempts = 0;
  const cleanup = createVoicePlayer({ store, random: () => 0, createAudio: url => {
    if (++attempts === 1) throw new Error('Audio failed');
    return new FakeAudio(url);
  } });
  store.set({ voiceRequest: 1 }); assert.equal(store.get('voicePlaying'), false);
  store.set({ voiceRequest: 2 }); assert.equal(attempts, 2);
  assert.equal(store.get('voicePlaying'), true); cleanup();
});
test('voice: mount is hidden, empty, synchronous, and allocates default Audio only on request', t => {
  const original = Object.getOwnPropertyDescriptor(globalThis, 'Audio');
  const audios = [];
  globalThis.Audio = class extends FakeAudio { constructor(url) { super(url); audios.push(this); } };
  t.after(() => { if (original) Object.defineProperty(globalThis, 'Audio', original); else delete globalThis.Audio; });
  const host = { hidden: false, children: [] };
  const store = createStore({ ...initialState, media: { voices } });
  assert.equal(voice.name, 'voice'); assert.equal(voice.css, undefined);
  const cleanup = voice.mount(host, { store });
  assert.equal(host.hidden, true); assert.deepEqual(host.children, []);
  assert.equal(typeof cleanup, 'function'); assert.equal(audios.length, 0);
  store.set({ voiceRequest: 1 }); assert.equal(audios.length, 1); cleanup();
});
