import { affectsHitRegions } from './hit-regions.js';

const selector = '.card, [data-glass]';

export function toGlassRegions(entries, viewport) {
  if (!Number.isFinite(viewport?.width) || !Number.isFinite(viewport?.height)
      || viewport.width <= 0 || viewport.height <= 0 || !Array.isArray(entries)) return [];
  const regions = [];
  for (const entry of entries) {
    if (!entry) continue;
    const { x, y, width, height, radius } = entry;
    if (![x, y, width, height, radius].every(Number.isFinite)
        || width <= 0 || height <= 0 || radius < 0 || radius > Math.min(width, height) / 2
        || x >= viewport.width || y >= viewport.height || x + width <= 0 || y + height <= 0) continue;
    regions.push([x, y, width, height, radius]);
    if (regions.length === 64) break;
  }
  return regions;
}

export function installGlassRegions({ send, root = document, win = window }) {
  let pending = false, previousJSON;
  let observed = new Set();
  let elements = [];
  const doc = root.ownerDocument ?? root;
  const resizeObserver = new win.ResizeObserver(schedule);
  function collect() {
    elements = [...root.querySelectorAll(selector)]
      // The root's data-glass flag enables tokens; it is not a glass surface.
      .filter(element => element !== doc.documentElement && win.getComputedStyle(element).visibility === 'visible');
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
      // Re-collect for CSS-only visibility changes, not just DOM mutations.
      collect();
      const regions = toGlassRegions(elements.map(element => {
        const { x, y, width, height } = element.getBoundingClientRect();
        const radius = parseFloat(win.getComputedStyle(element).borderTopLeftRadius) || 0;
        return { x, y, width, height, radius };
      }), { width: win.innerWidth, height: win.innerHeight });
      const json = JSON.stringify(regions);
      if (json === previousJSON) return;
      previousJSON = json;
      try { Promise.resolve(send(regions)).catch(() => {}); }
      catch { /* The bridge already reports transport failures. */ }
    });
  }
  collect();
  new win.MutationObserver(records => {
    // Remember former matches too: removing .card/data-glass must clear its old blur.
    // Ignore animated decorative descendants; ResizeObserver covers size changes.
    if (affectsHitRegions(records, selector)
        || records.some(record => record.type === 'attributes' && observed.has(record.target))) schedule();
  }).observe(root, {
    subtree: true, childList: true, attributes: true,
    attributeFilter: ['class', 'style', 'hidden', 'data-glass'],
  });
  win.addEventListener('resize', schedule);
  win.addEventListener('load', schedule);
  doc.addEventListener('load', schedule, true);
  doc.addEventListener('transitionend', schedule, true);
  doc.addEventListener('animationend', schedule, true);
  doc.fonts?.ready.then(schedule).catch(() => {});
  schedule();
  return { schedule };
}
