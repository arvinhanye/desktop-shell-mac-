import { store } from './store.js';
import { createBridge } from './bridge.js';
import { mountWidgets } from './widgets.js';
import { installDropRegions } from './drop-regions.js';
import { installHitRegions } from './hit-regions.js';
import { installGlassRegions } from './glass-regions.js';
import { installKeyboardFocus } from './keyboard-focus.js';

const bridge = createBridge(store, { target: window, now: () => performance.now() });
installKeyboardFocus({ send: action => bridge.send(action) });
document.addEventListener('contextmenu', event => event.preventDefault());
document.addEventListener('dragstart', event => {
  if (!event.target.closest?.('input, textarea, [contenteditable="true"]')) event.preventDefault();
});
const hitRegions = installHitRegions({ send: regions => bridge.send('setHitRegions', { regions }) });
const dropRegions = installDropRegions({ send: regions => bridge.send('setDropRegions', { regions }) });
store.subscribe('safeArea', insets => {
  for (const edge of ['top', 'right', 'bottom', 'left']) document.documentElement.style.setProperty(`--safe-${edge}`, `${insets[edge]}px`);
  hitRegions.schedule();
  dropRegions.schedule();
}, { immediate: true });
store.subscribe('phase', phase => {
  if (['morning', 'day', 'evening', 'night'].includes(phase)) document.documentElement.dataset.phase = phase;
  else console.warn('忽略不合法的时段');
}, { immediate: true });
store.subscribe('paused', paused => document.documentElement.toggleAttribute('data-paused', paused), { immediate: true });
const WIDGETS = ['clock', 'greeting', 'projects', 'launcher', 'todos', 'stats', 'character', 'appearance', 'project-editor', 'voice', 'visualizer'];
await mountWidgets(document.getElementById('desktop'), WIDGETS, { store, bridge, hitRegions });
await bridge.start();

if (bridge.mode === 'native') {
  installGlassRegions({ send: async regions => {
    await bridge.send('setGlassRegions', { regions });
    if (document.documentElement.dataset.glass !== 'on') document.documentElement.dataset.glass = 'on';
  } });
}
