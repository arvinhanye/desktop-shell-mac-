import { test } from 'node:test';
import assert from 'node:assert/strict';
import { terminalOptions, decodeOutput, splitInput, createTerminalController } from '../../web/terminal/terminal.js';

function fixture(nativeMode = true, responder = () => null) {
  const sent = [], writes = [], warnings = [], infos = [], handlers = {};
  const term = { cols: 80, rows: 24, focuses: 0, blurs: 0,
    write: data => writes.push(data), focus() { this.focuses++; }, blur() { this.blurs++; },
    onData(fn) { handlers.data = fn; }, onResize(fn) { handlers.resize = fn; }, onTitleChange(fn) { handlers.title = fn; },
  };
  const element = () => ({ textContent: '', innerHTML: '', hidden: true, attributes: {},
    setAttribute(k, v) { this.attributes[k] = v; }, addEventListener(k, fn) { this[k] = fn; } });
  const elements = { meta: element(), key: element(), maximize: element(), close: element() };
  const target = {};
  if (nativeMode) target.webkit = { messageHandlers: { shell: { postMessage(message) { sent.push(message); return responder(message); } } } };
  let fits = 0;
  const controller = createTerminalController({ term, fit: () => { fits++; handlers.resize({ cols: term.cols, rows: term.rows }); },
    elements, target, warn: (...args) => warnings.push(args), info: (...args) => infos.push(args) });
  return { controller, term, elements, target, handlers, sent, writes, warnings, infos, fits: () => fits };
}
const state = (patch = {}) => ({ event: 'terminalState', visible: true, maximized: false, hotkey: '⌥`', shell: 'zsh', ...patch });

test('terminal: all xterm settings come from tokens', () => {
  const options = terminalOptions(key => key === '--terminal-font-size' ? ' 13px ' : key === '--terminal-line-height' ? '1.25' : ` ${key} `);
  assert.equal(options.fontFamily, '--font-mono'); assert.equal(options.fontSize, 13); assert.equal(options.lineHeight, 1.25);
  assert.equal(options.allowTransparency, true); assert.equal(options.cursorBlink, true); assert.equal(options.scrollback, 5000);
  const colors = ['black', 'red', 'green', 'yellow', 'blue', 'magenta', 'cyan', 'white'];
  for (const color of colors) {
    assert.equal(options.theme[color], `--ansi-${color}`);
    assert.equal(options.theme[`bright${color[0].toUpperCase()}${color.slice(1)}`], `--ansi-bright-${color}`);
  }
  assert.deepEqual(Object.keys(options.theme).sort(), [...colors, ...colors.map(c => `bright${c[0].toUpperCase()}${c.slice(1)}`),
    'background', 'foreground', 'cursor', 'cursorAccent', 'selectionBackground'].sort());
  assert.equal(options.theme.background, 'rgba(0,0,0,0)');
  assert.equal(options.theme.foreground, '--terminal-fg'); assert.equal(options.theme.cursor, '--terminal-cursor');
  assert.equal(options.theme.cursorAccent, '--terminal-cursor-text'); assert.equal(options.theme.selectionBackground, '--terminal-selection');
});

test('terminal: base64 remains bytes when UTF-8 characters cross events', () => {
  const bytes = Buffer.from('中文🙂');
  const pieces = [bytes.subarray(0, 2), bytes.subarray(2, 7), bytes.subarray(7)];
  const f = fixture();
  for (const part of pieces) {
    assert.deepEqual(decodeOutput(part.toString('base64')), new Uint8Array(part));
    f.target.shell.receive({ event: 'terminalOutput', data: part.toString('base64') });
  }
  assert.ok(f.writes.every(v => v instanceof Uint8Array));
  assert.equal(Buffer.concat(f.writes).toString('utf8'), '中文🙂');
});

test('terminal: first fit sends ready once and only subsequent changed dimensions resize', async () => {
  const f = fixture();
  f.controller.start(); f.controller.start(); f.controller.fit();
  await f.controller.whenIdle();
  assert.equal(f.fits(), 2); assert.deepEqual(f.sent, [{ action: 'terminalReady', cols: 80, rows: 24 }]);
  f.handlers.resize({ cols: 100, rows: 30 }); f.handlers.resize({ cols: 100, rows: 30 });
  await f.controller.whenIdle();
  assert.deepEqual(f.sent.at(-1), { action: 'terminalResize', cols: 100, rows: 30 }); assert.equal(f.sent.length, 2);
});

test('terminal: long input preserves all text and surrogate pairs; calls remain ordered across input events', async () => {
  const text = 'x'.repeat(65535) + '🙂' + '中'.repeat(65536) + 'tail';
  const chunks = splitInput(text);
  assert.equal(chunks.join(''), text); assert.ok(chunks.every(s => s.length > 0 && s.length <= 65536 && s.isWellFormed()));
  assert.deepEqual(splitInput(''), []);
  let release;
  const f = fixture(true, message => message.action === 'terminalInput' && !release ? new Promise(r => { release = r; }) : null);
  f.controller.start(); f.handlers.data(text); f.handlers.data('after');
  await new Promise(r => setImmediate(r));
  assert.equal(f.sent.filter(v => v.action === 'terminalInput').length, 1);
  release(); await f.controller.whenIdle();
  assert.equal(f.sent.filter(v => v.action === 'terminalInput').map(v => v.data).join(''), text + 'after');
});

test('terminal: malformed and unknown events are discarded with content-free warnings', () => {
  const f = fixture();
  for (const value of [null, [], 'secret', {}, { event: 'secret' }, { event: 'terminalOutput', data: 1 },
    { event: 'terminalOutput', data: 'secret%%%==' }, { event: 'terminalExited', status: 'secret' },
    { event: 'terminalExited', status: NaN }, state({ visible: 1 }), state({ maximized: null }),
    state({ hotkey: 4 }), state({ shell: {} })]) f.target.shell.receive(value);
  assert.equal(f.warnings.length, 13); assert.equal(f.writes.length, 0); assert.equal(f.term.focuses, 0);
  assert.ok(!JSON.stringify(f.warnings).includes('secret'));
});

test('terminal: state drives visibility, shortcut, maximize and title fallback, exit resets title', async () => {
  const f = fixture(); f.controller.start();
  f.target.shell.receive(state()); f.target.shell.receive(state());
  assert.equal(f.term.focuses, 1); assert.equal(f.elements.meta.textContent, 'zsh');
  assert.equal(f.elements.key.textContent, '⌥`'); assert.equal(f.elements.key.hidden, false);
  f.handlers.title('<b>running</b>'); f.target.shell.receive(state({ shell: 'bash' }));
  assert.equal(f.elements.meta.textContent, '<b>running</b>');
  f.handlers.title(''); assert.equal(f.elements.meta.textContent, 'bash');
  f.elements.maximize.click(); await f.controller.whenIdle();
  assert.equal(f.sent.at(-1).action, 'toggleTerminalMaximize');
  assert.equal(f.elements.maximize.attributes['aria-label'], '放大');
  const before = f.elements.maximize.innerHTML;
  f.target.shell.receive(state({ visible: false, maximized: true, hotkey: '' }));
  assert.equal(f.term.blurs, 1); assert.equal(f.elements.key.hidden, true);
  assert.equal(f.elements.maximize.attributes['aria-label'], '还原'); assert.notEqual(f.elements.maximize.innerHTML, before);
  f.target.shell.receive(state()); assert.equal(f.term.focuses, 2);
  f.handlers.title('running'); f.target.shell.receive({ event: 'terminalExited', status: 0 });
  assert.equal(f.elements.meta.textContent, 'zsh');
  assert.equal(f.writes.at(-1), '\r\n\x1b[2m[shell 已退出，按任意键重新开始]\x1b[0m\r\n');
  f.elements.close.click(); await f.controller.whenIdle(); assert.equal(f.sent.at(-1).action, 'hideTerminal');
});

test('terminal: sync and asynchronous bridge failures never leak data or break later requests', async () => {
  let calls = 0;
  const f = fixture(true, () => { calls++; if (calls === 1) throw new Error('secret'); if (calls === 2) return Promise.reject('secret'); });
  f.controller.start(); f.handlers.data('secret'); f.handlers.data('next'); await f.controller.whenIdle();
  assert.equal(calls, 3); assert.equal(f.warnings.length, 2); assert.ok(!JSON.stringify(f.warnings).includes('secret'));
});

test('terminal: preview echoes text, return, backspace and buttons without native messages', () => {
  const f = fixture(false); f.controller.start();
  assert.match(f.writes[0], /浏览器预览：没有真实的 shell，输入会原样显示/);
  f.handlers.data('abc\x7f\r中文\x7f');
  assert.match(f.writes.join(''), /abc/); assert.match(f.writes.join(''), /\r\n\$ /);
  assert.equal(f.elements.meta.textContent, 'zsh'); assert.equal(f.term.focuses, 1);
  f.elements.maximize.click(); assert.equal(f.elements.maximize.attributes['aria-label'], '还原');
  f.elements.maximize.click(); assert.equal(f.elements.maximize.attributes['aria-label'], '放大');
  f.elements.close.click(); assert.equal(f.infos.length, 1); assert.deepEqual(f.sent, []);
});

test('terminal: input while fonts are loading waits for first fit and ready', async () => {
  const f = fixture(); f.handlers.data('early'); await f.controller.whenIdle();
  assert.deepEqual(f.sent, []);
  f.controller.start(); await f.controller.whenIdle();
  assert.deepEqual(f.sent, [{ action: 'terminalReady', cols: 80, rows: 24 }, { action: 'terminalInput', data: 'early' }]);
});
