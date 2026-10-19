import { backgroundUrl } from '../js/media.js';

const segmenter = new Intl.Segmenter(undefined, { granularity: 'grapheme' });
export function firstGrapheme(text) {
  return segmenter.segment(text)[Symbol.iterator]().next().value?.segment ?? '';
}

export function relatedAppIds(config, selectedProject) {
  return config?.projects?.find(project => project.id === selectedProject)?.apps ?? [];
}

export default {
  name: 'launcher',
  css: 'launcher.css',
  mount(host, { store, bridge }) {
    const doc = host.ownerDocument;
    const element = (tag, className) => {
      const node = doc.createElement(tag);
      node.className = className;
      return node;
    };
    host.setAttribute('aria-label', '应用启动栏');
    const card = element('div', 'card launcher-card');
    const art = element('div', 'card-art');
    const row = element('div', 'app-row');
    card.append(art, row);
    host.append(card);
    let disposed = false;
    let appCleanups = [];
    const buttons = new Map();
    const on = (node, type, callback) => {
      node.addEventListener(type, callback);
      appCleanups.push(() => node.removeEventListener(type, callback));
    };
    const updateRelated = () => {
      if (disposed) return;
      const related = new Set(relatedAppIds(store.get('config'), store.get('selectedProject')));
      for (const [id, button] of buttons) button.classList.toggle('related', related.has(id));
    };
    const updateBackground = () => {
      if (disposed) return;
      const url = backgroundUrl(store.get('media'), store.get('ui'));
      art.style.backgroundImage = url === null ? 'none' : `url(${JSON.stringify(url)})`;
    };
    const render = () => {
      if (disposed) return;
      appCleanups.forEach(off => off());
      appCleanups = [];
      buttons.clear();
      row.replaceChildren();
      for (const app of store.get('config')?.apps ?? []) {
        const button = element('button', 'app');
        button.type = 'button';
        button.title = `启动 ${app.name}`;
        const fallback = () => {
          const icon = element('span', 'app-icon app-icon-fallback');
          icon.textContent = firstGrapheme(app.name);
          return icon;
        };
        if (app.iconUrl != null) {
          const image = element('img', 'app-icon');
          image.alt = '';
          image.draggable = false;
          on(image, 'error', () => { if (!disposed) image.replaceWith(fallback()); });
          image.src = app.iconUrl;
          button.append(image);
        } else button.append(fallback());
        const name = element('span', 'app-name');
        name.textContent = app.name;
        button.append(name);
        on(button, 'click', async () => {
          if (disposed) return;
          try { await bridge.send('launchApp', { appId: app.id }); }
          catch { /* Bridge already logs the failure; this card has no error slot. */ }
        });
        row.append(button);
        buttons.set(app.id, button);
      }
      updateRelated();
    };
    const subscriptions = [
      store.subscribe('config', render, { immediate: true }),
      store.subscribe('selectedProject', updateRelated, { immediate: true }),
      store.subscribe('ui', updateBackground, { immediate: true }),
      store.subscribe('media', updateBackground, { immediate: true }),
    ];
    return () => {
      disposed = true;
      subscriptions.forEach(off => off());
      appCleanups.forEach(off => off());
      appCleanups = [];
    };
  },
};
