import { test } from 'node:test';
import assert from 'node:assert/strict';
import character from '../../web/widgets/character.js';
import { createStore, initialState } from '../../web/js/store.js';
import { createBrowser, one } from './helpers/linkage-browser.mjs';

test('character: avatar ring is decorative and follows voice playback state', () => {
  const browser = createBrowser(0);
  const host = browser.doc.createElement('section');
  const store = createStore({ ...initialState });
  const cleanup = character.mount(host, { store });
  const avatar = one(host, 'avatar-button');
  const ring = one(host, 'avatar-ring');
  assert.equal(avatar.children[0].tagName, 'IMG');
  assert.equal(avatar.children[1], ring);
  assert.equal(ring.getAttribute('aria-hidden'), 'true');
  assert.equal(avatar.classList.contains('playing'), false);
  store.set({ voicePlaying: true });
  assert.equal(avatar.classList.contains('playing'), true);
  store.set({ voicePlaying: false });
  assert.equal(avatar.classList.contains('playing'), false);
  cleanup(); browser.assertClean();
});
