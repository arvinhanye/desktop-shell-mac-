import { test } from 'node:test';
import assert from 'node:assert/strict';
import { isTextEntry, installKeyboardFocus } from '../../web/js/keyboard-focus.js';

const element = (tagName, properties = {}) => ({ tagName, ...properties });
const input = (type = 'text') => element('INPUT', { type });

test('keyboard focus: recognizes text entry types, textarea and editable content', () => {
  for (const type of ['text', 'search', 'email', 'url', 'tel', 'password', 'number']) {
    assert.equal(isTextEntry(input(type)), true, type);
  }
  assert.equal(isTextEntry(element('INPUT')), true);
  assert.equal(isTextEntry(element('TEXTAREA')), true);
  assert.equal(isTextEntry(element('DIV', { isContentEditable: true })), true);
  assert.equal(isTextEntry(element('SPAN', { isContentEditable: true })), true);
});

test('keyboard focus: ignores non-text controls, plain elements and missing targets', () => {
  for (const type of ['checkbox', 'radio', 'button', 'range', 'submit', 'reset', 'file', 'color', 'date', 'hidden']) {
    assert.equal(isTextEntry(input(type)), false, type);
  }
  for (const target of [element('BUTTON'), element('DIV'), element('DIV', { isContentEditable: false }), null, undefined]) {
    assert.equal(isTextEntry(target), false);
  }
});

function eventTarget() {
  const listeners = new Map();
  return {
    listeners,
    addEventListener(type, callback, capture) { listeners.set(type, { callback, capture }); },
    emit(type, event = {}) { listeners.get(type)?.callback(event); },
  };
}

function fixture(send) {
  const doc = eventTarget();
  const win = eventTarget();
  const sent = [];
  installKeyboardFocus({ doc, win, send: send ?? (action => { sent.push(action); return Promise.resolve(null); }) });
  return { doc, win, sent };
}

test('keyboard focus: document handlers run in capture phase', () => {
  const { doc } = fixture();
  for (const type of ['focusin', 'focusout', 'keydown']) assert.equal(doc.listeners.get(type)?.capture, true);
});

test('keyboard focus: focusin requests keyboard only for text entry', () => {
  const { doc, sent } = fixture();
  doc.emit('focusin', { target: input('checkbox') });
  doc.emit('focusin', { target: element('BUTTON') });
  assert.deepEqual(sent, []);
  doc.emit('focusin', { target: input() });
  doc.emit('focusin', { target: element('TEXTAREA') });
  assert.deepEqual(sent, ['focusInput', 'focusInput']);
});

test('keyboard focus: leaving text entry for blank space or a checkbox releases keyboard', () => {
  const { doc, sent } = fixture();
  doc.emit('focusout', { target: input(), relatedTarget: null });
  doc.emit('focusout', { target: input(), relatedTarget: input('checkbox') });
  doc.emit('focusout', { target: input('checkbox'), relatedTarget: null });
  assert.deepEqual(sent, ['blurInput', 'blurInput']);
});

test('keyboard focus: moving between text entries never releases keyboard', () => {
  const { doc, sent } = fixture();
  doc.emit('focusout', { target: input(), relatedTarget: input('search') });
  doc.emit('focusin', { target: input('search') });
  doc.emit('focusout', { target: input('search'), relatedTarget: element('DIV', { isContentEditable: true }) });
  assert.deepEqual(sent, ['focusInput']);
});

test('keyboard focus: Escape blurs text entry and normal focusout sends blurInput', () => {
  const { doc, sent } = fixture();
  let blurred = 0;
  const target = { ...input(), blur() { blurred++; doc.emit('focusout', { target, relatedTarget: null }); } };
  doc.emit('keydown', { target, key: 'Escape', isComposing: false });
  assert.equal(blurred, 1);
  assert.deepEqual(sent, ['blurInput']);
});

test('keyboard focus: composing Escape, other keys and non-text controls retain their focus', () => {
  const { doc, sent } = fixture();
  let blurred = 0;
  const target = { ...input(), blur() { blurred++; } };
  doc.emit('keydown', { target, key: 'Escape', isComposing: true });
  doc.emit('keydown', { target, key: 'Enter', isComposing: false });
  doc.emit('keydown', { target: { ...target, type: 'checkbox' }, key: 'Escape', isComposing: false });
  assert.equal(blurred, 0);
  assert.deepEqual(sent, []);
});

test('keyboard focus: page blur clears active text entry so WebKit cannot restore stale focus', () => {
  const { doc, win, sent } = fixture();
  let blurred = 0;
  const target = { ...input(), blur() { blurred++; doc.activeElement = null; doc.emit('focusout', { target, relatedTarget: null }); } };
  doc.activeElement = target;
  win.emit('blur');
  win.emit('blur');
  assert.equal(blurred, 1);
  assert.deepEqual(sent, ['blurInput']);
  doc.activeElement = { ...input('checkbox'), blur() { assert.fail('checkbox blurred'); } };
  win.emit('blur');
});

test('keyboard focus: failed bridge promises are consumed without duplicate logging', async t => {
  const warnings = t.mock.method(console, 'warn', () => {});
  const { doc } = fixture(() => Promise.reject(new Error('failed')));
  doc.emit('focusin', { target: input() });
  doc.emit('focusout', { target: input(), relatedTarget: null });
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(warnings.mock.callCount(), 0);
});
