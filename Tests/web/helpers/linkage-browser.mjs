import assert from 'node:assert/strict';

// Only browser/platform boundaries are faked. Components, store and bridge stay real.
// No layout engine, CSS renderer, network, real audio or wall-clock timers here.
export function createBrowser(startTime) {
  let time = startTime, nextId = 0, frameRequests = 0;
  const timers = new Map(), frames = new Map(), nodes = [], observers = [], audios = [];
  const schedule = (callback, delay, interval = false) => {
    assert.ok(Number.isFinite(delay) && delay > 0, 'timer must have a positive delay');
    const id = ++nextId;
    timers.set(id, { callback, at: time + delay, delay, interval });
    return id;
  };
  const advance = milliseconds => {
    const end = time + milliseconds;
    for (let count = 0; ; count++) {
      const next = [...timers].filter(([, timer]) => timer.at <= end)
        .sort((a, b) => a[1].at - b[1].at || a[0] - b[0])[0];
      if (!next) break;
      assert.ok(count < 10000, 'fake timer loop did not settle');
      const [id, timer] = next;
      time = timer.at;
      if (timer.interval) timer.at += timer.delay;
      else timers.delete(id);
      timer.callback();
    }
    time = end;
  };
  class Events {
    listeners = new Map();
    addEventListener(type, callback) {
      if (!this.listeners.has(type)) this.listeners.set(type, new Set());
      this.listeners.get(type).add(callback);
    }
    removeEventListener(type, callback) { this.listeners.get(type)?.delete(callback); }
    // Return listener promises to let tests await actual asynchronous event work.
    emit(type, details = {}) {
      const event = { target: this, defaultPrevented: false, stopped: false,
        preventDefault() { this.defaultPrevented = true; },
        stopPropagation() { this.stopped = true; }, ...details };
      const results = [];
      for (let node = this; node; node = node.parentElement) {
        event.currentTarget = node;
        for (const callback of [...(node.listeners.get(type) ?? [])]) results.push(callback(event));
        if (event.stopped) break;
      }
      return Promise.all(results);
    }
  }
  class Style {
    transform = '';
    setProperty(name, value) { this[name] = String(value); }
    getPropertyValue(name) { return this[name] ?? ''; }
    removeProperty(name) { const old = this[name] ?? ''; this[name] = ''; return old; }
  }
  class Element extends Events {
    constructor(tag) {
      super();
      this.tagName = tag.toUpperCase(); this.ownerDocument = doc;
      this.children = []; this.parentElement = null; this.attributes = {};
      this.className = ''; this.dataset = {}; this.style = new Style();
      this.hidden = false; this.value = ''; this._text = '';
      this.scrollTop = 0; this.clientHeight = 100; this.scrollHeight = 100;
      nodes.push(this);
    }
    append(...children) {
      for (let child of children) {
        if (typeof child === 'string') child = doc.createTextNode(child);
        child.parentElement = this;
        this.children.push(child);
      }
    }
    replaceChildren(...children) {
      this.children.forEach(child => { child.parentElement = null; });
      this.children = []; this._text = ''; this.append(...children);
    }
    setAttribute(key, value) {
      if (key === 'class') this.className = String(value);
      else this.attributes[key] = String(value);
    }
    getAttribute(key) { return key === 'class' ? this.className : this.attributes[key] ?? null; }
    removeAttribute(key) { delete this.attributes[key]; delete this[key]; }
    set textContent(text) { this.replaceChildren(); this._text = String(text); }
    get textContent() { return this._text + this.children.map(child => child.textContent).join(''); }
    set innerHTML(value) {
      assert.ok(value.startsWith('<svg ') && value.endsWith('</svg>'), 'only static SVG markup is expected');
      const svg = new Element('svg'); svg.source = value; this.replaceChildren(svg);
    }
    get classList() {
      return {
        contains: name => this.className.split(/\s+/).includes(name),
        toggle: (name, force) => {
          const names = new Set(this.className.split(/\s+/).filter(Boolean));
          const enabled = force ?? !names.has(name);
          if (enabled) names.add(name); else names.delete(name);
          this.className = [...names].join(' ');
          return enabled;
        },
      };
    }
  }
  class Observer {
    constructor() { this.connected = false; observers.push(this); }
    observe() { this.connected = true; }
    disconnect() { this.connected = false; }
  }
  class Audio extends Events {
    constructor(url) { super(); this.url = url; this.plays = 0; this.pauses = 0; audios.push(this); }
    play() { this.plays++; return Promise.resolve(); }
    pause() { this.pauses++; }
  }
  const win = {
    Date: class extends Date {
      constructor(...args) { super(...(args.length ? args : [time])); }
      static now() { return time; }
    },
    setTimeout: (callback, delay) => schedule(callback, delay),
    clearTimeout: id => timers.delete(id),
    setInterval: (callback, delay) => schedule(callback, delay, true),
    clearInterval: id => timers.delete(id),
    requestAnimationFrame(callback) { frameRequests++; const id = ++nextId; frames.set(id, callback); return id; },
    cancelAnimationFrame: id => frames.delete(id),
    ResizeObserver: Observer, MutationObserver: Observer,
    getComputedStyle: () => ({ getPropertyValue: name => {
      assert.equal(name, '--viz-bar-rest'); return '0.02';
    } }),
  };
  const doc = new Events();
  Object.assign(doc, {
    defaultView: win, visibilityState: 'visible',
    createElement: tag => new Element(tag),
    createElementNS: (_namespace, tag) => new Element(tag),
    createTextNode: text => { const node = new Element('#text'); node.textContent = text; return node; },
  });
  doc.documentElement = doc.createElement('html');
  const desktop = doc.createElement('main'); desktop.setAttribute('id', 'desktop');
  doc.documentElement.append(desktop);
  return {
    doc, win, desktop, nodes, observers, audios, Audio, timers, frames,
    now: () => time, advance,
    get frameRequests() { return frameRequests; },
    draw() {
      for (const [id, callback] of [...frames]) {
        if (frames.delete(id)) callback(time);
      }
    },
    assertClean() {
      assert.equal(timers.size, 0, 'all widget and mock timers must be canceled');
      assert.equal(frames.size, 0, 'all animation frames must be canceled');
      assert.ok(observers.every(observer => !observer.connected), 'all observers must disconnect');
      assert.ok([doc, ...nodes, ...audios].every(target =>
        [...target.listeners.values()].every(listeners => listeners.size === 0)), 'all listeners must be removed');
    },
  };
}

export const descendants = root => root.children.flatMap(child => [child, ...descendants(child)]);
export const byClass = (root, name) => descendants(root).filter(node => node.classList.contains(name));
export function one(root, name) {
  const matches = byClass(root, name);
  assert.equal(matches.length, 1, `expected exactly one .${name}`);
  return matches[0];
}
