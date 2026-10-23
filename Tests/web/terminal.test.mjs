import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createStore, initialState } from '../../web/js/store.js';
import { createBrowser, one } from './helpers/linkage-browser.mjs';

async function fixture(config = null, send = async () => null) {
  const { default: widget } = await import('../../web/widgets/terminal.js');
  const browser = createBrowser(0);
  const host = browser.doc.createElement('section');
  const store = createStore({ ...initialState, config });
  const calls = [];
  const cleanup = widget.mount(host, { store, bridge: { send(...args) { calls.push(args); return send(...args); } } });
  return { ...browser, widget, host, store, calls, cleanup };
}

test('terminal: accessible card button shows configured shortcut as literal text', async () => {
  const f = await fixture({ terminal: { hotkey: '⌥`' } });
  assert.equal(f.widget.name, 'terminal');
  assert.equal(f.widget.css, 'terminal.css');
  assert.equal(f.host.getAttribute('aria-label'), '终端');
  const button = one(f.host, 'terminal-entry');
  assert.equal(button.tagName, 'BUTTON');
  assert.equal(button.type, 'button');
  assert.ok(button.classList.contains('card'));
  assert.equal(button.children[0].tagName, 'SVG');
  assert.equal(one(button, 'terminal-entry-label').textContent, '终端');
  const hint = one(button, 'key-hint');
  assert.equal(hint.tagName, 'KBD');
  assert.equal(hint.textContent, '⌥`');
  assert.equal(hint.hidden, false);
  f.store.set({ config: { terminal: { hotkey: '<b>⌘K</b>' } } });
  assert.equal(hint.textContent, '<b>⌘K</b>');
  assert.equal(hint.children.length, 0);
  f.cleanup(); f.assertClean();
});

test('terminal: missing or invalid shortcut hides hint and clears previous text', async () => {
  const f = await fixture();
  const hint = one(f.host, 'key-hint');
  assert.equal(hint.hidden, true);
  for (const config of [{}, { terminal: null }, { terminal: { hotkey: null } }, { terminal: { hotkey: 1 } }]) {
    f.store.set({ config: { terminal: { hotkey: '⌘K' } } });
    assert.equal(hint.hidden, false);
    f.store.set({ config });
    assert.equal(hint.hidden, true);
    assert.equal(hint.textContent, '');
  }
  f.cleanup(); f.assertClean();
});

test('terminal: click sends only openTerminal; failures are consumed and cleanup detaches', async () => {
  const f = await fixture({ terminal: { hotkey: '⌥`' } }, async () => { throw new Error('unknown-action'); });
  const button = one(f.host, 'terminal-entry');
  const before = f.host.textContent;
  await button.emit('click');
  assert.deepEqual(f.calls, [['openTerminal']]);
  assert.equal(f.host.textContent, before);
  f.cleanup(); f.cleanup();
  await button.emit('click');
  f.store.set({ config: { terminal: { hotkey: '⌘K' } } });
  assert.equal(f.calls.length, 1);
  assert.equal(f.host.textContent, before);
  f.assertClean();
});
