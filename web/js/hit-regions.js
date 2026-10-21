export function toRegions(rects, viewport, { limit = 64, label = 'hit regions' } = {}) {
  if (!Number.isFinite(viewport?.width) || !Number.isFinite(viewport?.height)
      || viewport.width <= 0 || viewport.height <= 0 || !Array.isArray(rects)) return [];
  const regions = [];
  const seen = new Set();
  for (const rect of rects) {
    if (!rect) continue;
    const { x, y, width, height } = rect;
    if (![x, y, width, height].every(Number.isFinite) || width <= 0 || height <= 0
        || x >= viewport.width || y >= viewport.height || x + width <= 0 || y + height <= 0) continue;
    const left = Math.max(0, Math.floor(x));
    const top = Math.max(0, Math.floor(y));
    const right = Math.min(viewport.width, Math.ceil(x + width));
    const bottom = Math.min(viewport.height, Math.ceil(y + height));
    const region = [left, top, right - left, bottom - top];
    const key = region.join(',');
    if (seen.has(key)) continue;
    if (regions.length === limit) { console.warn(`${label}: truncated to ${limit} regions`); break; }
    seen.add(key);
    regions.push(region);
  }
  return regions;
}

export function affectsHitRegions(records, selector = '.card, [data-hit]') {
  const containsRegion = node => node.nodeType === 1
    && (node.matches(selector) || node.querySelector(selector) !== null);
  return records.some(record => {
    if (record.type === 'attributes') return containsRegion(record.target);
    if (record.type === 'childList') {
      return [...record.addedNodes, ...record.removedNodes].some(containsRegion);
    }
    return false;
  });
}

export function installHitRegions(options) {
  return installRegionReporter(options);
}

// Both reports use the same geometry, invalidation and per-frame deduplication.
export function installRegionReporter({ send, root = document, win = window,
  selector = '.card, [data-hit]', attribute = 'data-hit', limit = 64, label = 'hit regions' }) {
  let pending = false;
  let last = Object.freeze([]);
  let previousJSON;
  let elements = [];
  let observed = new Set();
  const doc = root.ownerDocument ?? root;
  const resizeObserver = new win.ResizeObserver(schedule);
  function collect() {
    elements = [...root.querySelectorAll(selector)].filter(element =>
      (attribute !== 'data-hit' || element.getAttribute('data-hit') !== 'none') && win.getComputedStyle(element).visibility === 'visible');
    const next = new Set([doc.documentElement, ...elements]);
    for (const element of observed) if (!next.has(element)) resizeObserver.unobserve(element);
    for (const element of next) if (!observed.has(element)) resizeObserver.observe(element);
    observed = next;
  }
  function schedule() {
    if (pending) return;
    pending = true;
    win.requestAnimationFrame(() => {
      pending = false;
      // CSS transitions and media queries can change visibility without a DOM mutation.
      collect();
      const regions = toRegions(elements.map(element => element.getBoundingClientRect()),
        { width: win.innerWidth, height: win.innerHeight }, { limit, label });
      const json = JSON.stringify(regions);
      if (json === previousJSON) return;
      previousJSON = json;
      last = Object.freeze(regions.map(region => Object.freeze(region)));
      try { Promise.resolve(send(last)).catch(() => {}); }
      catch { /* The bridge already reports transport failures. */ }
    });
  }
  collect();
  new win.MutationObserver(records => {
    // Decorative descendants (e.g. spectrum bars) do not change the hit rectangle.
    // If their content changes the card's size, ResizeObserver schedules that update.
    if (affectsHitRegions(records, selector)
        || records.some(record => record.type === 'attributes' && observed.has(record.target))) schedule();
  }).observe(root, {
    subtree: true, childList: true, attributes: true,
    attributeFilter: ['class', 'style', 'hidden', attribute],
  });
  win.addEventListener('resize', schedule);
  win.addEventListener('load', schedule);
  doc.addEventListener('load', schedule, true);
  doc.addEventListener('transitionend', schedule, true);
  doc.addEventListener('animationend', schedule, true);
  doc.fonts?.ready.then(schedule).catch(() => {});
  schedule();
  return { schedule, get last() { return last; } };
}
