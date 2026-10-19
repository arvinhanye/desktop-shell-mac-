export function greetingFor(greetings, hour) {
  const sorted = [...greetings].sort((a, b) => a.from - b.from);
  return sorted.filter(item => item.from <= hour).at(-1) ?? sorted.at(-1) ?? null;
}

export default {
  name: 'greeting',
  css: 'greeting.css',
  mount(host, { store }) {
    const doc = host.ownerDocument;
    const win = doc.defaultView;
    host.setAttribute('aria-label', '问候语');
    const title = doc.createElement('p');
    title.className = 'greeting-title';
    const label = doc.createElement('span');
    const comma = doc.createElement('span');
    const name = doc.createElement('span');
    name.className = 'greeting-name';
    title.append(label, comma, name);
    const wish = doc.createElement('p');
    wish.className = 'greeting-wish';
    host.append(title, wish);

    const render = () => {
      const config = store.get('config');
      const now = store.get('now');
      const hour = (now === null ? new win.Date() : new win.Date(now)).getHours();
      const greeting = greetingFor(config?.greetings ?? [], hour);
      const userName = greeting ? config?.user?.name ?? null : null;
      label.textContent = greeting?.title ?? '';
      comma.textContent = userName === null ? '' : '，';
      comma.hidden = name.hidden = userName === null;
      name.textContent = userName ?? '';
      wish.textContent = greeting?.wish ?? '';
    };
    const unsubscribeConfig = store.subscribe('config', render, { immediate: true });
    const unsubscribeNow = store.subscribe('now', render, { immediate: true });
    return () => {
      unsubscribeConfig();
      unsubscribeNow();
    };
  },
};
