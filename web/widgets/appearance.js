export function appearanceSelection(media, ui) {
  const avatars = media?.avatars ?? [];
  return {
    avatarId: avatars.find(item => item.id === ui?.avatarId)?.id ?? avatars[0]?.id ?? null,
    backgroundId: media?.backgrounds?.find(item => item.id === ui?.backgroundId)?.id ?? null,
  };
}

export function appearanceChange(media, ui, key, id) {
  if (key === 'reset') return { avatarId: null, backgroundId: null };
  const items = key === 'avatarId' ? media?.avatars : key === 'backgroundId' ? media?.backgrounds : null;
  if (!items?.some(item => item.id === id) || appearanceSelection(media, ui)[key] === id) return null;
  return { [key]: id };
}

export default {
  name: 'appearance',
  css: 'appearance.css',
  mount(host, { store, bridge }) {
    const doc = host.ownerDocument, win = doc.defaultView;
    const element = (tag, className = '', text) => {
      const node = doc.createElement(tag);
      node.className = className;
      if (text !== undefined) node.textContent = text;
      return node;
    };
    const overlay = element('div', 'appearance-overlay');
    overlay.hidden = true;
    overlay.setAttribute('data-hit', '');
    const panel = element('div', 'appearance-panel');
    panel.setAttribute('role', 'dialog');
    panel.setAttribute('aria-label', '外观');
    panel.setAttribute('data-glass', '');
    const head = element('div', 'appearance-head');
    const actions = element('div', 'appearance-actions');
    const message = element('span', 'card-meta');
    const reset = element('button', 'ghost-button', '恢复默认');
    const done = element('button', 'primary-button', '完成');
    reset.type = done.type = 'button';
    actions.append(message, reset, done);
    head.append(element('h2', '', '外观'), actions);
    const scroll = element('div', 'appearance-scroll');
    const avatars = element('div', 'thumb-grid avatars');
    const backgrounds = element('div', 'thumb-grid backgrounds');
    for (const [grid, label] of [[avatars, '头像'], [backgrounds, '背景']]) {
      grid.setAttribute('role', 'radiogroup');
      grid.setAttribute('aria-label', label);
    }
    scroll.append(element('h3', '', '头像'), avatars, element('h3', '', '启动栏和卡片的背景'), backgrounds);
    panel.append(head, scroll);
    overlay.append(panel);
    host.append(overlay);

    let disposed = false;
    let errorTimer = null;
    let thumbCleanups = [];
    let thumbs = [];
    const clearError = () => {
      if (errorTimer !== null) win.clearTimeout(errorTimer);
      errorTimer = null;
      message.textContent = '';
    };
    const save = async (key, id) => {
      if (disposed) return;
      const params = appearanceChange(store.get('media'), store.get('ui'), key, id);
      if (!params) return;
      try {
        await bridge.send('saveUiState', params);
        if (!disposed) clearError();
      } catch {
        if (disposed) return;
        clearError();
        message.textContent = '保存失败，请再试一次';
        errorTimer = win.setTimeout(clearError, 3000);
      }
    };
    const updateSelection = () => {
      if (disposed) return;
      const selected = appearanceSelection(store.get('media'), store.get('ui'));
      for (const { button, key, id } of thumbs) button.setAttribute('aria-checked', String(selected[key] === id));
    };
    const renderMedia = () => {
      if (disposed) return;
      thumbCleanups.forEach(off => off());
      thumbCleanups = [];
      thumbs = [];
      const media = store.get('media');
      for (const [grid, items, key] of [
        [avatars, media?.avatars ?? [], 'avatarId'],
        [backgrounds, media?.backgrounds ?? [], 'backgroundId'],
      ]) {
        grid.replaceChildren();
        for (const item of items) {
          const button = element('button', `thumb${key === 'backgroundId' ? ' background-thumb' : ''}`);
          button.type = 'button';
          button.setAttribute('role', 'radio');
          button.dataset.id = item.id;
          const image = doc.createElement('img');
          image.alt = '';
          image.draggable = false;
          image.loading = 'lazy';
          image.src = item.url;
          button.append(image);
          const click = () => save(key, item.id);
          button.addEventListener('click', click);
          thumbCleanups.push(() => button.removeEventListener('click', click));
          thumbs.push({ button, key, id: item.id });
          grid.append(button);
        }
      }
      updateSelection();
    };
    const close = () => store.set({ appearanceOpen: false });
    const resetAppearance = () => save('reset');
    const clickOverlay = event => { if (event.target === overlay) close(); };
    done.addEventListener('click', close);
    reset.addEventListener('click', resetAppearance);
    overlay.addEventListener('click', clickOverlay);
    const subscriptions = [
      store.subscribe('appearanceOpen', open => { if (!disposed) overlay.hidden = !open; }, { immediate: true }),
      store.subscribe('media', renderMedia, { immediate: true }),
      store.subscribe('ui', updateSelection, { immediate: true }),
    ];
    return () => {
      disposed = true;
      subscriptions.forEach(off => off());
      thumbCleanups.forEach(off => off());
      thumbCleanups = [];
      thumbs = [];
      clearError();
      done.removeEventListener('click', close);
      reset.removeEventListener('click', resetAppearance);
      overlay.removeEventListener('click', clickOverlay);
    };
  },
};
