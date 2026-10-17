export function toRegions(rects, viewport) {
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
    if (regions.length === 64) { console.warn('hit regions: truncated to 64 regions'); break; }
    seen.add(key);
    regions.push(region);
  }
  return regions;
}

export function installHitRegions({ send, root = document, win = window }) {
  let pending = false;
  let last = Object.freeze([]);
  let previousJSON;
  let elements = [];
  let observed = new Set();
  const doc = root.ownerDocument ?? root;
  const resizeObserver = new win.ResizeObserver(schedule);
  function collect() {
    elements = [...root.querySelectorAll('.card, [data-hit]')].filter(element =>
      element.getAttribute('data-hit') !== 'none' && win.getComputedStyle(element).visibility === 'visible');
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
        { width: win.innerWidth, height: win.innerHeight });
      const json = JSON.stringify(regions);
      if (json === previousJSON) return;
      previousJSON = json;
      last = Object.freeze(regions.map(region => Object.freeze(region)));
      try { Promise.resolve(send(last)).catch(() => {}); }
      catch { /* The bridge already reports transport failures. */ }
    });
  }
  collect();
  new win.MutationObserver(schedule).observe(root, {
    subtree: true, childList: true, attributes: true,
    attributeFilter: ['class', 'style', 'hidden', 'data-hit'],
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
