import { installScrollHints } from '../js/scroll-hints.js';

export function projectActions(project, apps) {
  const actions = [{ label: '访达', title: '在访达中打开', action: 'openProject', payload: { projectId: project.id } }];
  const app = (project.apps ?? []).map(id => apps.find(app => app.id === id)).find(Boolean);
  if (app) actions.push({ label: app.name, title: `用 ${app.name} 打开`, action: 'openProjectWith', payload: { projectId: project.id, appId: app.id } });
  return actions;
}

export function toggleSelection(current, id) {
  return current === id ? null : id;
}

export default {
  name: 'projects',
  css: 'projects.css',
  mount(host, { store, bridge }) {
    const doc = host.ownerDocument;
    const win = doc.defaultView;
    const element = (tag, className, text) => {
      const node = doc.createElement(tag);
      node.className = className;
      if (text !== undefined) node.textContent = text;
      return node;
    };
    host.setAttribute('aria-label', '项目');
    const card = element('div', 'card projects-card');
    const head = element('div', 'card-head');
    const status = element('span', 'card-meta');
    head.append(element('h2', 'card-title', '项目'), status);
    const list = element('div', 'project-list scroll-list');
    card.append(head, list);
    host.append(card);

    let disposed = false;
    let generation = 0;
    let messageTimer;
    let rowCleanups = [];
    const rows = new Map();
    const on = (node, type, callback) => {
      node.addEventListener(type, callback);
      rowCleanups.push(() => node.removeEventListener(type, callback));
    };
    const clearError = () => {
      win.clearTimeout(messageTimer);
      messageTimer = undefined;
      status.textContent = '';
    };
    const showError = () => {
      clearError();
      status.textContent = '没能打开';
      const timer = win.setTimeout(() => {
        if (!disposed && messageTimer === timer) clearError();
      }, 3000);
      messageTimer = timer;
    };
    const updateSelection = () => {
      if (disposed) return;
      for (const [id, row] of rows) row.classList.toggle('selected', store.get('selectedProject') === id);
    };
    const render = () => {
      if (disposed) return;
      const version = ++generation;
      rowCleanups.forEach(off => off());
      rowCleanups = [];
      rows.clear();
      list.replaceChildren();
      clearError();
      const config = store.get('config');
      const projects = config?.projects ?? [];
      if (config && store.get('selectedProject') !== null && !projects.some(project => project.id === store.get('selectedProject'))) {
        store.set({ selectedProject: null });
      }
      if (!projects.length) list.append(element('p', 'card-meta', '还没有项目，在 config.json 的 projects 里添加'));
      for (const project of projects) {
        const row = element('div', 'project');
        row.setAttribute('role', 'button');
        row.tabIndex = 0;
        const info = element('div', '');
        const tags = element('div', 'project-tags');
        for (const tag of project.tags ?? []) tags.append(element('span', 'tag', tag));
        info.append(element('div', 'project-name', project.name), tags);
        const actions = element('div', 'project-actions');
        for (const action of projectActions(project, config.apps ?? [])) {
          const button = element('button', 'ghost-button', action.label);
          button.type = 'button';
          button.title = action.title;
          let pending = false;
          on(button, 'click', async event => {
            event.stopPropagation();
            if (disposed || pending) return;
            pending = true;
            try { await bridge.send(action.action, action.payload); }
            catch {
              // A reply for a replaced configuration must not change the new card.
              if (!disposed && version === generation) showError();
            } finally { pending = false; }
          });
          actions.append(button);
        }
        const select = () => {
          if (!disposed) store.set({ selectedProject: toggleSelection(store.get('selectedProject'), project.id) });
        };
        on(row, 'click', select);
        on(row, 'keydown', event => {
          if (event.target !== row || !['Enter', ' '].includes(event.key)) return;
          event.preventDefault();
          if (!event.repeat) select();
        });
        row.append(info, actions);
        rows.set(project.id, row);
        list.append(row);
      }
      updateSelection();
    };
    const unsubscribeConfig = store.subscribe('config', render, { immediate: true });
    const unsubscribeSelection = store.subscribe('selectedProject', updateSelection, { immediate: true });
    const cleanupScrollHints = installScrollHints(list, { win });
    return () => {
      disposed = true;
      generation++;
      unsubscribeConfig();
      unsubscribeSelection();
      cleanupScrollHints();
      clearError();
      rowCleanups.forEach(off => off());
      rowCleanups = [];
    };
  },
};
