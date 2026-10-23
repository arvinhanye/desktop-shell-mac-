import { test } from 'node:test';
import assert from 'node:assert/strict';
import stats, { formatPercent, batteryView, sparkPoints } from '../../web/widgets/stats.js';
import { createStore, initialState } from '../../web/js/store.js';

for (const [value, expected] of [[0, '0.0'], [18.46, '18.5'], [100, '100.0'], [NaN, '—'], [Infinity, '—'], [-Infinity, '—'], [undefined, '—'], [null, '—'], ['15', '—']]) {
  test(`stats: percent ${String(value)} displays a finite number or missing marker`, () => {
    assert.equal(formatPercent(value), expected);
  });
}
for (const [battery, expected] of [
  [{ level: 15, onBattery: true, charging: false }, { value: '15', detail: '% 用电池', scale: 0.15, low: true }],
  [{ level: 0, onBattery: true, charging: false }, { value: '0', detail: '% 用电池', scale: 0, low: true }],
  [{ level: 20, onBattery: true, charging: false }, { value: '20', detail: '% 用电池', scale: 0.2, low: false }],
  [{ level: 50, onBattery: false, charging: true }, { value: '50', detail: '% 充电中', scale: 0.5, low: false }],
  [{ level: 15, onBattery: false, charging: false }, { value: '15', detail: '% 电源', scale: 0.15, low: false }],
  [{ level: 85.6, onBattery: false, charging: false }, { value: '86', detail: '% 电源', scale: 0.856, low: false }],
]) {
  test(`stats: battery ${JSON.stringify(battery)} selects value, source and warning`, () => {
    assert.deepEqual(batteryView(battery), expected);
  });
}
for (const battery of [null, undefined, {}, { level: null }, { level: NaN }, { level: Infinity }, { level: '15' }]) {
  test(`stats: absent or invalid battery ${JSON.stringify(battery)} has no source suffix or warning`, () => {
    assert.deepEqual(batteryView(battery), { value: '—', detail: '', scale: 0, low: false });
  });
}
for (const history of [[], [50], [20, NaN], [20, undefined]]) {
  test(`stats: ${JSON.stringify(history)} does not draw an incomplete or invalid line`, () => {
    assert.deepEqual(sparkPoints(history), { line: '', area: '' });
  });
}
test('stats: two samples align right and map 0/100 to the padded vertical limits', () => {
  assert.deepEqual(sparkPoints([0, 100]), {
    line: '57.39,25.00 60.00,1.00',
    area: '57.39,26 57.39,25.00 60.00,1.00 60,26',
  });
});
test('stats: 24 samples fill the width with two decimal coordinates', () => {
  const result = sparkPoints(Array(24).fill(50));
  assert.ok(result, 'valid history produces line and area coordinates');
  const { line, area } = result;
  const points = line.split(' ');
  assert.equal(points.length, 24);
  assert.deepEqual(points.slice(0, 2), ['0.00,13.00', '2.61,13.00']);
  assert.equal(points.at(-1), '60.00,13.00');
  assert.ok(area.startsWith('0.00,26 0.00,13.00 '));
  assert.ok(area.endsWith('60.00,13.00 60,26'));
});
test('stats: only the newest 24 samples are plotted without mutating history', () => {
  const history = Object.freeze([100, 100, 0, ...Array(23).fill(50)]);
  const result = sparkPoints(history);
  assert.ok(result, 'rolling history produces coordinates');
  const points = result.line.split(' ');
  assert.equal(points.length, 24);
  assert.deepEqual(points.slice(0, 2), ['0.00,25.00', '2.61,13.00']);
  assert.equal(points.at(-1), '60.00,13.00');
  assert.equal(history.length, 26);
});

// Only the DOM boundary is doubled; the widget and store run unchanged.
function mounted(systemStats = null) {
  class Element {
    constructor(tag, namespaceURI = null) { this.tagName = tag.toUpperCase(); this.namespaceURI = namespaceURI; this.children = []; this.attributes = {}; this.className = ''; this.style = {}; this._text = ''; this.ownerDocument = doc; }
    append(...children) { this.children.push(...children); }
    setAttribute(name, value) { this.attributes[name] = String(value); }
    getAttribute(name) { return this.attributes[name] ?? null; }
    set textContent(value) { this._text = String(value); this.children = []; }
    get textContent() { return this._text + this.children.map(child => child.textContent).join(''); }
    set innerHTML(_) { throw new Error('Values must not be parsed as HTML'); }
    get classList() { return { contains: name => this.className.split(' ').includes(name), toggle: (name, force) => { const names = new Set(this.className.split(' ').filter(Boolean)); if (force) names.add(name); else names.delete(name); this.className = [...names].join(' '); } }; }
  }
  const doc = {
    createElement: tag => new Element(tag),
    createElementNS: (ns, tag) => new Element(tag, ns),
    createTextNode: text => { const node = new Element('#text'); node.textContent = text; return node; },
    defaultView: { setInterval() { throw new Error('Sampling belongs to the native bridge'); } },
  };
  const host = doc.createElement('section');
  const store = createStore({ ...initialState, systemStats });
  const writes = [];
  const cleanup = stats.mount(host, { store: { ...store, set(patch) { writes.push(patch); store.set(patch); } } });
  assert.ok(host.children.length > 0, 'mount creates the system stats card');
  assert.equal(typeof cleanup, 'function');
  return { host, store, writes, cleanup };
}
const descendants = node => node.children.flatMap(child => [child, ...descendants(child)]);
const byClass = (host, name) => descendants(host).filter(node => node.classList.contains(name));
const byTag = (host, name) => descendants(host).filter(node => node.tagName === name.toUpperCase());
const snapshot = (cpu = 20, battery = { level: 85, charging: false, onBattery: false }, percent = 50) => ({ cpu, battery, memory: { usedBytes: 1, totalBytes: 2, percent } });
const values = f => byClass(f.host, 'stat-value').map(node => node.textContent);
const line = f => byTag(f.host, 'polyline')[0].getAttribute('points');

test('stats: initial missing snapshot shows empty values, bars and plot in accessible card', () => {
  const f = mounted();
  assert.equal(f.host.getAttribute('aria-label'), '系统状态');
  assert.equal(byClass(f.host, 'card-title')[0].textContent, '系统状态');
  assert.deepEqual(values(f), ['—', '—', '—']);
  assert.deepEqual(byClass(f.host, 'stat-bar').map(node => node.children[0].style.transform), ['scaleX(0)', 'scaleX(0)']);
  assert.equal(line(f), ''); assert.equal(byTag(f.host, 'polygon')[0].getAttribute('points'), '');
  const svg = byTag(f.host, 'svg')[0];
  assert.equal(svg.namespaceURI, 'http://www.w3.org/2000/svg');
  assert.equal(svg.getAttribute('viewBox'), '0 0 60 26');
  assert.equal(svg.getAttribute('preserveAspectRatio'), 'none'); assert.equal(svg.getAttribute('aria-hidden'), 'true');
  const hint = byClass(f.host, 'power-hint')[0];
  assert.equal(hint.textContent, '电量低，已暂停视频和动画');
  assert.equal(hint.tagName, 'SPAN');
  assert.ok(hint.classList.contains('card-meta'));
  assert.equal(byClass(f.host, 'card-head')[0].children[1], hint);
  assert.equal(byClass(f.host, 'low-battery').length, 0); f.cleanup();
});
test('stats: initial snapshot renders numbers with small suffixes and the second push draws a line', () => {
  const f = mounted(snapshot());
  assert.deepEqual(values(f), ['20.0%', '50.0%', '85% 电源']);
  assert.deepEqual(byTag(f.host, 'small').map(node => node.textContent), ['%', '%', '% 电源']);
  assert.deepEqual(byClass(f.host, 'stat-bar').map(node => node.children[0].style.transform), ['scaleX(0.5)', 'scaleX(0.85)']);
  assert.equal(line(f), '');
  f.store.set({ systemStats: snapshot(100) });
  assert.equal(line(f), '57.39,20.20 60.00,1.00');
  assert.equal(byTag(f.host, 'polygon')[0].getAttribute('points'), '57.39,26 57.39,20.20 60.00,1.00 60,26');
  assert.deepEqual(values(f), ['100.0%', '50.0%', '85% 电源']); f.cleanup();
});
test('stats: each snapshot adds exactly one sample and history rolls over at 24', () => {
  const f = mounted();
  f.store.set({ systemStats: snapshot(0) });
  assert.equal(line(f), '');
  for (let i = 0; i < 23; i++) f.store.set({ systemStats: snapshot(50) });
  assert.equal(line(f).split(' ').length, 24); assert.ok(line(f).startsWith('0.00,25.00 '));
  f.store.set({ systemStats: snapshot(100) });
  assert.equal(line(f).split(' ').length, 24); assert.ok(line(f).startsWith('0.00,13.00 '));
  assert.ok(line(f).endsWith('60.00,1.00')); f.cleanup();
});
test('stats: repeated equal CPU samples count but unrelated state updates do not', () => {
  const f = mounted(snapshot(0));
  f.store.set({ now: 60000, paused: true, phase: 'night', selectedProject: 'project' });
  assert.equal(line(f), '');
  f.store.set({ systemStats: snapshot(0) });
  assert.equal(line(f), '57.39,25.00 60.00,25.00');
  f.store.set({ now: 120000, paused: false });
  assert.equal(line(f), '57.39,25.00 60.00,25.00'); f.cleanup();
});
test('stats: low battery warning follows power source without changing shared pause policy', () => {
  const f = mounted(snapshot(20, { level: 15, onBattery: true, charging: false }));
  assert.equal(byClass(f.host, 'low-battery').length, 1); assert.equal(values(f)[2], '15% 用电池');
  assert.equal(f.store.get('paused'), false);
  f.store.set({ systemStats: snapshot(20, { level: 15, onBattery: false, charging: true }) });
  assert.equal(byClass(f.host, 'low-battery').length, 0); assert.equal(values(f)[2], '15% 充电中');
  f.store.set({ systemStats: snapshot(20, { level: 20, onBattery: true, charging: false }) });
  assert.equal(byClass(f.host, 'low-battery').length, 0);
  f.store.set({ systemStats: snapshot(20, { level: null, onBattery: true, charging: false }) });
  assert.equal(values(f)[2], '—'); assert.equal(byTag(f.host, 'small')[2].textContent, '');
  assert.equal(byClass(f.host, 'stat-bar')[1].children[0].style.transform, 'scaleX(0)');
  assert.deepEqual(f.writes, []); f.cleanup();
});
test('stats: missing CPU clears the plot instead of inventing a zero and valid samples recover', () => {
  const f = mounted(snapshot(0)); f.store.set({ systemStats: snapshot(100) });
  assert.notEqual(line(f), '');
  f.store.set({ systemStats: { cpu: NaN, battery: null, memory: {} } });
  assert.deepEqual(values(f), ['—', '—', '—']); assert.equal(line(f), '');
  assert.deepEqual(byClass(f.host, 'stat-bar').map(node => node.children[0].style.transform), ['scaleX(0)', 'scaleX(0)']);
  f.store.set({ systemStats: snapshot(10) }); assert.equal(line(f), '');
  f.store.set({ systemStats: snapshot(20) }); assert.equal(line(f), '57.39,22.60 60.00,20.20');
  f.cleanup();
});
test('stats: a missing memory field leaves the valid CPU and battery visible', () => {
  const f = mounted({ cpu: 18.46, battery: { level: 50, onBattery: false, charging: true } });
  assert.deepEqual(values(f), ['18.5%', '—', '50% 充电中']);
  assert.equal(byClass(f.host, 'stat-bar')[0].children[0].style.transform, 'scaleX(0)'); f.cleanup();
});
test('stats: cleanup unsubscribes and a new mount starts with fresh history', () => {
  const f = mounted(snapshot(20)); f.store.set({ systemStats: snapshot(100) });
  const previous = f.host.textContent, previousLine = line(f);
  f.cleanup(); f.cleanup();
  f.store.set({ systemStats: snapshot(0) });
  assert.equal(f.host.textContent, previous); assert.equal(line(f), previousLine);
  const next = mounted(snapshot(0)); assert.equal(line(next), ''); next.cleanup();
});
