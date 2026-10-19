export function formatPercent(value) {
  return Number.isFinite(value) ? value.toFixed(1) : '—';
}

export function batteryView(battery) {
  if (!Number.isFinite(battery?.level)) return { value: '—', detail: '', scale: 0, low: false };
  return {
    value: battery.level.toFixed(0),
    detail: battery.onBattery ? '% 用电池' : battery.charging ? '% 充电中' : '% 电源',
    scale: battery.level / 100,
    low: battery.onBattery === true && battery.level < 20,
  };
}

export function sparkPoints(history) {
  const samples = history.slice(-24);
  if (samples.length < 2 || samples.some(value => !Number.isFinite(value))) return { line: '', area: '' };
  const points = samples.map((value, i) => {
    const x = (60 - (samples.length - 1 - i) * 60 / 23).toFixed(2);
    const y = (26 - value / 100 * 24 - 1).toFixed(2);
    return `${x},${y}`;
  });
  const line = points.join(' ');
  return { line, area: `${points[0].split(',')[0]},26 ${line} 60,26` };
}

export default {
  name: 'stats',
  css: 'stats.css',
  mount(host, { store }) {
    const doc = host.ownerDocument;
    const element = (tag, className, text) => {
      const node = doc.createElement(tag);
      node.className = className;
      if (text !== undefined) node.textContent = text;
      return node;
    };
    const svgElement = tag => doc.createElementNS('http://www.w3.org/2000/svg', tag);
    host.setAttribute('aria-label', '系统状态');
    const card = element('div', 'card stats-card');
    const head = element('div', 'card-head');
    head.append(element('h2', 'card-title', '系统状态'));
    card.append(head);

    const spark = svgElement('svg');
    spark.setAttribute('class', 'stat-spark');
    spark.setAttribute('viewBox', '0 0 60 26');
    spark.setAttribute('preserveAspectRatio', 'none');
    spark.setAttribute('aria-hidden', 'true');
    const area = svgElement('polygon');
    const line = svgElement('polyline');
    spark.append(area, line);
    const memoryBar = element('div', 'stat-bar');
    const memoryFill = element('span', '');
    memoryBar.append(memoryFill);
    const batteryBar = element('div', 'stat-bar');
    const batteryFill = element('span', '');
    batteryBar.append(batteryFill);

    const row = (label, visual, className = 'stat-row') => {
      const container = element('div', className);
      const value = element('span', 'stat-value');
      const number = doc.createTextNode('—');
      const detail = element('small', '');
      value.append(number, detail);
      container.append(element('span', 'stat-label', label), visual, value);
      card.append(container);
      return (text, suffix) => { number.textContent = text; detail.textContent = suffix; };
    };
    const cpuValue = row('CPU', spark);
    const memoryValue = row('内存', memoryBar);
    const batteryValue = row('电量', batteryBar, 'stat-row stat-battery');
    card.append(element('p', 'power-hint', '电量低于 20%，已暂停背景视频和动画来省电'));
    host.append(card);

    let history = [];
    return store.subscribe('systemStats', stats => {
      const cpu = stats?.cpu;
      const memory = stats?.memory?.percent;
      cpuValue(formatPercent(cpu), Number.isFinite(cpu) ? '%' : '');
      memoryValue(formatPercent(memory), Number.isFinite(memory) ? '%' : '');
      memoryFill.style.transform = `scaleX(${Number.isFinite(memory) ? memory / 100 : 0})`;
      const battery = batteryView(stats?.battery);
      batteryValue(battery.value, battery.detail);
      batteryFill.style.transform = `scaleX(${battery.scale})`;
      card.classList.toggle('low-battery', battery.low);

      // Missing samples break continuity; never plot them as zero or join across gaps.
      history = Number.isFinite(cpu) ? [...history, cpu].slice(-24) : [];
      const points = sparkPoints(history);
      line.setAttribute('points', points.line);
      area.setAttribute('points', points.area);
    }, { immediate: true });
  },
};
