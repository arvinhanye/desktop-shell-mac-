const MAX_ICON = '<svg viewBox="0 0 16 16" aria-hidden="true"><path fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round" d="M9.5 2.5h4v4M6.5 13.5h-4v-4M13.5 2.5 9.5 6.5M2.5 13.5l4-4"/></svg>';
const RESTORE_ICON = '<svg viewBox="0 0 16 16" aria-hidden="true"><path fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round" d="M13.5 6.5h-4v-4M2.5 9.5h4v4M9.5 6.5l4-4M6.5 9.5l-4 4"/></svg>';
const EXIT_MESSAGE = '\r\n\x1b[2m[shell 已退出，按任意键重新开始]\x1b[0m\r\n';

export function terminalOptions(getToken) {
  const token = name => getToken(name).trim();
  const theme = {
    background: 'rgba(0,0,0,0)', foreground: token('--terminal-fg'),
    cursor: token('--terminal-cursor'), cursorAccent: token('--terminal-cursor-text'),
    selectionBackground: token('--terminal-selection'),
  };
  for (const color of ['black', 'red', 'green', 'yellow', 'blue', 'magenta', 'cyan', 'white']) {
    theme[color] = token(`--ansi-${color}`);
    theme[`bright${color[0].toUpperCase()}${color.slice(1)}`] = token(`--ansi-bright-${color}`);
  }
  return { fontFamily: token('--font-mono'), fontSize: parseFloat(token('--terminal-font-size')),
    lineHeight: Number(token('--terminal-line-height')), theme,
    allowTransparency: true, cursorBlink: true, scrollback: 5000 };
}

export function decodeOutput(data) {
  if (typeof data !== 'string' || !/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(data)) {
    throw new TypeError('Invalid terminal output');
  }
  return Uint8Array.from(atob(data), char => char.charCodeAt(0));
}

export function splitInput(data) {
  const chunks = [];
  for (let start = 0; start < data.length;) {
    let end = Math.min(start + 65536, data.length);
    // Never split a UTF-16 surrogate pair between native messages.
    if (end < data.length && /[\uD800-\uDBFF]/.test(data[end - 1]) && /[\uDC00-\uDFFF]/.test(data[end])) end--;
    chunks.push(data.slice(start, end));
    start = end;
  }
  return chunks;
}

const validSize = ({ cols, rows }) => Number.isInteger(cols) && cols >= 1 && cols <= 1000
  && Number.isInteger(rows) && rows >= 1 && rows <= 1000;

// The controller accepts a fake terminal for tests; no desktop-page bridge or store is shared.
export function createTerminalController({ term, fit, elements, target,
  warn = message => console.warn(message), info = message => console.info(message) }) {
  const native = target.webkit?.messageHandlers?.shell;
  const preview = typeof native?.postMessage !== 'function';
  let ready = false, dimensions = null, pending = Promise.resolve();
  let visible = false, maximized = false, shell = '', title = '';
  const previewCharacters = [];
  const earlyInput = [];

  function send(message) {
    if (preview) return;
    pending = pending.then(() => native.postMessage(message)).catch(() => {
      // Native errors can contain user data. Never print the error object or payload.
      warn('terminal: native request failed');
    });
  }

  function receive(event) {
    try {
      if (!event || typeof event !== 'object' || Array.isArray(event)) throw new TypeError();
      switch (event.event) {
        case 'terminalOutput':
          term.write(decodeOutput(event.data));
          return;
        case 'terminalExited':
          if (!Number.isSafeInteger(event.status)) throw new TypeError();
          // xterm parses writes asynchronously. Reset only after any earlier OSC
          // titles have been consumed, at the same queue position as the exit line.
          term.write(EXIT_MESSAGE, () => {
            title = '';
            elements.meta.textContent = shell;
          });
          return;
        case 'terminalState': {
          if (typeof event.visible !== 'boolean' || typeof event.maximized !== 'boolean'
              || typeof event.hotkey !== 'string' || typeof event.shell !== 'string') throw new TypeError();
          shell = event.shell;
          elements.meta.textContent = title || shell;
          elements.key.textContent = event.hotkey;
          elements.key.hidden = event.hotkey.length === 0;
          maximized = event.maximized;
          elements.maximize.innerHTML = maximized ? RESTORE_ICON : MAX_ICON;
          const label = maximized ? '还原' : '放大';
          elements.maximize.setAttribute('title', label);
          elements.maximize.setAttribute('aria-label', label);
          if (event.visible !== visible) {
            if (event.visible) term.focus();
            else term.blur();
          }
          visible = event.visible;
          return;
        }
        default: throw new TypeError();
      }
    } catch {
      warn('terminal: discarded invalid event');
    }
  }
  target.shell = { receive };

  function previewInput(data) {
    let output = '';
    for (const char of data.replace(/\r\n/g, '\r')) {
      if (char === '\r' || char === '\n') {
        output += '\r\n$ ';
        previewCharacters.length = 0;
      } else if (char === '\x7f' || char === '\b') {
        const previous = previewCharacters.pop();
        if (previous) {
          // Wide CJK/emoji glyphs occupy two cells; combining marks occupy none.
          const width = /\p{Mark}/u.test(previous) ? 0
            : /[\u1100-\u115f\u2329\u232a\u2e80-\ua4cf\uac00-\ud7a3\uf900-\ufaff\ufe10-\ufe19\ufe30-\ufe6f\uff01-\uff60\uffe0-\uffe6\u{20000}-\u{3fffd}]|\p{Extended_Pictographic}/u.test(previous) ? 2 : 1;
          output += '\b \b'.repeat(width);
        }
      } else if (char >= ' ' && char !== '\x7f') {
        previewCharacters.push(char);
        output += char;
      }
    }
    if (output) term.write(output);
  }

  function input(data) {
    if (!data) return;
    if (!ready) { earlyInput.push(data); return; }
    if (preview) previewInput(data);
    else for (const chunk of splitInput(data)) send({ action: 'terminalInput', data: chunk });
  }
  term.onData(input);
  term.onResize(size => {
    if (!ready || !validSize(size) || (dimensions.cols === size.cols && dimensions.rows === size.rows)) return;
    dimensions = { cols: size.cols, rows: size.rows };
    send({ action: 'terminalResize', ...dimensions });
  });
  term.onTitleChange(value => {
    if (typeof value !== 'string') return;
    title = value;
    elements.meta.textContent = title || shell;
  });
  elements.maximize.addEventListener('click', () => {
    if (preview) receive({ event: 'terminalState', visible, maximized: !maximized, hotkey: '⌥`', shell });
    else send({ action: 'toggleTerminalMaximize' });
  });
  elements.close.addEventListener('click', () => {
    if (preview) info('terminal: preview hide requested');
    else send({ action: 'hideTerminal' });
  });

  return {
    start() {
      if (ready) return;
      fit();
      if (!validSize(term)) return;
      dimensions = { cols: term.cols, rows: term.rows };
      ready = true;
      if (preview) {
        term.write('\x1b[?45h\x1b[2m浏览器预览：没有真实的 shell，输入会原样显示\x1b[0m\r\n$ ');
        receive({ event: 'terminalState', visible: true, maximized: false, hotkey: '⌥`', shell: 'zsh' });
      } else send({ action: 'terminalReady', ...dimensions });
      for (const data of earlyInput.splice(0)) input(data);
    },
    fit() { if (ready) fit(); else this.start(); },
    whenIdle: () => pending,
  };
}

function mountTerminal() {
  const screen = document.querySelector('.terminal-screen');
  if (!screen) return;
  document.addEventListener('contextmenu', event => event.preventDefault());
  const tokens = getComputedStyle(document.documentElement);
  const term = new window.Terminal(terminalOptions(name => tokens.getPropertyValue(name)));
  const fitAddon = new window.FitAddon.FitAddon();
  term.loadAddon(fitAddon);
  term.open(screen);
  const controller = createTerminalController({ term, fit: () => fitAddon.fit(), target: window,
    elements: { meta: document.querySelector('.terminal-meta'), key: document.querySelector('kbd.key-hint'),
      maximize: document.querySelector('#terminal-max'), close: document.querySelector('#terminal-close') } });
  const observer = new ResizeObserver(() => controller.fit());
  // Measure with the final fonts rather than announcing fallback-font dimensions.
  document.fonts.ready.then(() => { controller.start(); observer.observe(screen); }).catch(() => {
    console.warn('terminal: initialization failed');
  });
}

if (typeof window !== 'undefined' && typeof document !== 'undefined') mountTerminal();
