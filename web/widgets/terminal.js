export default {
  name: 'terminal',
  css: 'terminal.css',
  mount(host, { store, bridge }) {
    const doc = host.ownerDocument;
    host.setAttribute('aria-label', '终端');
    const button = doc.createElement('button');
    button.className = 'card terminal-entry';
    button.type = 'button';
    button.innerHTML = '<svg class="terminal-entry-icon" viewBox="0 0 18 18" aria-hidden="true"><path fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" d="M3.5 5l4 4-4 4M9.5 13.5h5"/></svg>';
    const label = doc.createElement('span');
    label.className = 'terminal-entry-label';
    label.textContent = '终端';
    const hint = doc.createElement('kbd');
    hint.className = 'key-hint';
    button.append(label, hint);
    host.append(button);

    const unsubscribe = store.subscribe('config', config => {
      const hotkey = config?.terminal?.hotkey;
      hint.hidden = typeof hotkey !== 'string';
      hint.textContent = hint.hidden ? '' : hotkey;
    }, { immediate: true });
    const open = async () => {
      try { await bridge.send('openTerminal'); } catch { /* Swift 已记录错误。 */ }
    };
    button.addEventListener('click', open);
    return () => {
      unsubscribe();
      button.removeEventListener('click', open);
    };
  },
};
