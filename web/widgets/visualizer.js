export function createVisualizer({ bars, raf, cancelRaf, setTimer, clearTimer, rest }) {
  let frame = null, timer = null, latest = null;
  let paused = false, disposed = false;
  const reset = () => {
    if (frame !== null) cancelRaf(frame);
    if (timer !== null) clearTimer(timer);
    frame = timer = latest = null;
    for (const bar of [...bars.left, ...bars.right]) bar.style.removeProperty('transform');
  };
  return {
    update(spectrum) {
      if (disposed || paused) return;
      if (spectrum === null) { reset(); return; }
      latest = spectrum.bands;
      if (timer !== null) clearTimer(timer);
      const pendingTimer = setTimer(() => {
        // Ignore callbacks canceled by a newer spectrum, pause, or disposal.
        if (disposed || timer !== pendingTimer) return;
        timer = null;
        reset();
      }, 250);
      timer = pendingTimer;
      if (frame !== null) return;
      const pendingFrame = raf(() => {
        if (disposed || frame !== pendingFrame) return;
        frame = null;
        for (let i = 0; i < bars.left.length; i++) {
          const transform = `scaleY(${Math.max(latest[i], rest)})`;
          bars.left[i].style.transform = transform;
          bars.right[i].style.transform = transform;
        }
      });
      frame = pendingFrame;
    },
    setPaused(value) {
      if (disposed) return;
      paused = value;
      if (paused) reset();
    },
    dispose() {
      if (disposed) return;
      disposed = true;
      reset();
    },
  };
}

export default {
  name: 'visualizer',
  css: 'visualizer.css',
  mount(host, { store }) {
    const doc = host.ownerDocument, win = doc.defaultView;
    host.setAttribute('aria-hidden', 'true');
    const bars = { left: [], right: [] };
    for (const side of ['left', 'right']) {
      const group = doc.createElement('div');
      group.className = `viz-bars ${side}`;
      for (let i = 0; i < 12; i++) {
        const bar = doc.createElement('span');
        group.append(bar);
        bars[side].push(bar);
      }
      host.append(group);
    }
    const ornament = doc.createElement('img');
    ornament.className = 'viz-ornament';
    ornament.src = '/media/ornaments/heart.png';
    ornament.alt = '';
    ornament.draggable = false;
    host.append(ornament);
    const player = createVisualizer({
      bars,
      raf: callback => win.requestAnimationFrame(callback),
      cancelRaf: id => win.cancelAnimationFrame(id),
      setTimer: (callback, delay) => win.setTimeout(callback, delay),
      clearTimer: id => win.clearTimeout(id),
      rest: Number.parseFloat(win.getComputedStyle(doc.documentElement).getPropertyValue('--viz-bar-rest')),
    });
    const subscriptions = [
      // Read pause first so an initially paused page never schedules a stale spectrum.
      store.subscribe('paused', player.setPaused, { immediate: true }),
      store.subscribe('audioSpectrum', player.update, { immediate: true }),
    ];
    return () => {
      subscriptions.forEach(off => off());
      player.dispose();
    };
  },
};
