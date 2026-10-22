import { installScrollHints } from '../js/scroll-hints.js';

export function projectActions(project, apps) {
  const actions = [{ label: '访达', title: '在访达中打开', action: 'openProject', payload: { projectId: project.id } }];
  const app = (project.apps ?? []).map(id => apps.find(app => app.id === id)).find(Boolean);
  if (app) actions.push({ label: app.name, title: `用 ${app.name} 打开`, action: 'openProjectWith', payload: { projectId: project.id, appId: app.id } });
  return actions;
}

export function moveProjectIds(projects, projectId, direction) {
  const ids = projects.map(project => project.id), index = ids.indexOf(projectId), next = index + direction;
  if (![-1, 1].includes(direction) || index < 0 || next < 0 || next >= ids.length) return null;
  [ids[index], ids[next]] = [ids[next], ids[index]];
  return ids;
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
    const svg = (viewBox, paths) => {
      const node = doc.createElementNS('http://www.w3.org/2000/svg', 'svg');
      node.setAttribute('viewBox', viewBox);
      node.setAttribute('aria-hidden', 'true');
      for (const attributes of paths) {
        const path = doc.createElementNS('http://www.w3.org/2000/svg', 'path');
        for (const [key, value] of Object.entries(attributes)) path.setAttribute(key, value);
        node.append(path);
      }
      return node;
    };
    const removeIcon = () => svg('0 0 16 16', [{ fill: 'none', stroke: 'currentColor', 'stroke-width': '1.4', 'stroke-linecap': 'round', d: 'M4.5 4.5l7 7M11.5 4.5l-7 7' }]);
    host.setAttribute('aria-label', '项目');
    const card = element('div', 'card projects-card');
    card.setAttribute('data-drop', 'projects');
    const head = element('div', 'card-head');
    const status = element('span', 'card-meta');
    const manage = element('button', 'project-manage-toggle', '管理'); manage.type = 'button';
    head.append(element('h2', 'card-title', '项目'), status, manage);
    const list = element('div', 'project-list scroll-list');
    const add = element('label', 'project-add');
    const input = element('input', '');
    input.type = 'text';
    input.value = '';
    input.placeholder = '粘贴文件夹路径，或把文件夹拖进来';
    input.setAttribute('spellcheck', 'false');
    input.setAttribute('autocomplete', 'off');
    const plus = element('span', '', '＋');
    plus.setAttribute('aria-hidden', 'true');
    add.append(plus, input);
    const hint = element('p', 'project-hint');
    const drop = element('div', 'project-drop');
    drop.setAttribute('aria-hidden', 'true');
    drop.append(svg('0 0 24 24', [
      { fill: 'none', stroke: 'currentColor', 'stroke-width': '1.5', 'stroke-linejoin': 'round', d: 'M3 6.5A1.5 1.5 0 0 1 4.5 5h4.6l2 2.2h8.4A1.5 1.5 0 0 1 21 8.7v9.8a1.5 1.5 0 0 1-1.5 1.5h-15A1.5 1.5 0 0 1 3 18.5Z' },
      { fill: 'none', stroke: 'currentColor', 'stroke-width': '1.5', 'stroke-linecap': 'round', d: 'M12 10.5v6M9 13.5h6' },
    ]), element('span', '', '松开，添加为项目'));
    card.append(head, add, hint, list, drop);
    host.append(card);

    let disposed = false;
    let managing = false, reordering = false, configGeneration = 0;
    let generation = 0;
    let messageTimer;
    let rowCleanups = [];
    let adding = false;
    let confirmation;
    const removing = new Set();
    const awaitingScroll = new Set();
    const clearConfirmation = () => {
      if (!confirmation) return;
      win.clearTimeout(confirmation.timer);
      confirmation.button.classList.toggle('confirm', false);
      confirmation.button.replaceChildren(removeIcon());
      confirmation = undefined;
    };
    const showHint = code => {
      const messages = {
        'not-found': '找不到这个文件夹',
        'not-directory': '这不是文件夹',
        'outside-home': '只能添加个人文件夹（~）里的文件夹',
        duplicate: '这个文件夹已经是项目了',
      };
      hint.textContent = code ? (messages[code] ?? '没能添加，请再试一次') : '';
      hint.classList.toggle('error', Boolean(code));
    };
    const scrollToAdded = () => {
      const ids = new Set((store.get('config')?.projects ?? []).map(project => project.id));
      if (awaitingScroll.size && [...awaitingScroll].every(id => ids.has(id))) {
        list.scrollTop = list.scrollHeight;
        awaitingScroll.clear();
      }
    };
    const rows = new Map();
    const on = (node, type, callback) => {
      node.addEventListener(type, callback);
      rowCleanups.push(() => node.removeEventListener(type, callback));
    };
    const clearMessage = () => {
      win.clearTimeout(messageTimer);
      messageTimer = undefined;
      status.textContent = '';
    };
    const showMessage = text => {
      clearMessage();
      status.textContent = text;
      const timer = win.setTimeout(() => {
        if (!disposed && messageTimer === timer) clearMessage();
      }, 3000);
      messageTimer = timer;
    };
    const added = items => {
      input.value = '';
      showHint(null);
      showMessage(items.length === 1 ? `已添加「${items[0].name}」` : `已添加 ${items.length} 个项目`);
      for (const item of items) awaitingScroll.add(item.id);
      scrollToAdded();
    };
    const onInput = () => showHint(null);
    const onAdd = async event => {
      if (disposed || event.key !== 'Enter' || event.isComposing || event.keyCode === 229) return;
      const path = input.value.trim();
      if (!path) return;
      event.preventDefault();
      if (adding) return;
      adding = true;
      try {
        const project = await bridge.send('addProject', { path });
        if (!disposed) added([project]);
      } catch (error) {
        if (!disposed) showHint(error.code ?? error.message ?? 'failed');
      } finally { adding = false; }
    };
    input.addEventListener('input', onInput);
    input.addEventListener('keydown', onAdd);
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
      clearConfirmation();
      const config = store.get('config');
      const projects = config?.projects ?? [];
      if (config && store.get('selectedProject') !== null && !projects.some(project => project.id === store.get('selectedProject'))) {
        store.set({ selectedProject: null });
      }
      if (!projects.length) list.append(element('p', 'card-meta', '还没有项目，在上面粘贴文件夹路径，或把文件夹拖进来'));
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
              if (!disposed && version === generation) showMessage('没能打开');
            } finally { pending = false; }
          });
          actions.append(button);
        }
        if (managing) {
          actions.replaceChildren();
          const edit = element('button', 'project-edit', '编辑'); edit.type = 'button';
          on(edit, 'click', event => { event.stopPropagation(); store.set({ editingProjectId: project.id, appearanceOpen: false, layoutOpen: false }); });
          actions.append(edit);
          for (const [direction, label, cls] of [[-1, '↑', 'project-up'], [1, '↓', 'project-down']]) {
            const move = element('button', cls, label); move.type = 'button'; move.title = direction === -1 ? '上移' : '下移';
            move.setAttribute('aria-label', `${move.title} ${project.name}`);
            move.disabled = reordering || moveProjectIds(projects, project.id, direction) === null;
            on(move, 'click', async event => {
              event.stopPropagation(); if (disposed || reordering || move.disabled) return;
              const projectIds = moveProjectIds(store.get('config')?.projects ?? [], project.id, direction);
              if (!projectIds) return;
              reordering = true; render();
              try { await bridge.send('reorderProjects', { projectIds }); }
              catch {
                if (!disposed) {
                  const refreshVersion = configGeneration;
                  showMessage('排序失败，正在刷新');
                  try {
                    const reply = await bridge.send('getConfig');
                    if (!disposed && refreshVersion === configGeneration) store.set({ config: reply.config });
                  } catch { if (!disposed && refreshVersion === configGeneration) showMessage('刷新失败，请重试'); }
                }
              } finally { reordering = false; if (!disposed) render(); }
            });
            actions.append(move);
          }
        }
        const remove = element('button', 'project-remove');
        remove.type = 'button';
        remove.title = '从列表移除（不会删除文件夹）';
        remove.setAttribute('aria-label', `移除 ${project.name}`);
        remove.append(removeIcon());
        on(remove, 'click', async event => {
          event.stopPropagation();
          if (disposed || removing.has(project.id)) return;
          if (confirmation?.button !== remove) {
            clearConfirmation();
            remove.classList.toggle('confirm', true);
            remove.textContent = '移除？';
            const current = { button: remove };
            current.timer = win.setTimeout(() => {
              if (!disposed && confirmation === current) clearConfirmation();
            }, 3000);
            confirmation = current;
            return;
          }
          clearConfirmation();
          removing.add(project.id);
          try {
            await bridge.send('removeProject', { projectId: project.id });
            if (!disposed) showMessage(`已移除「${project.name}」，文件夹没有动`);
          } catch {
            if (!disposed) showMessage('没能移除');
          } finally { removing.delete(project.id); }
        });
        actions.append(remove);
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
      scrollToAdded();
    };
    const toggleManagement = () => { managing = !managing; manage.textContent = managing ? '完成' : '管理'; manage.setAttribute('aria-pressed', String(managing)); card.classList.toggle('managing', managing); render(); };
    manage.addEventListener('click', toggleManagement);
    const unsubscribeConfig = store.subscribe('config', () => { configGeneration++; render(); }, { immediate: true });
    const unsubscribeSelection = store.subscribe('selectedProject', updateSelection, { immediate: true });
    card.classList.toggle('drop-target', store.get('projectDrop')?.over === true);
    // Results are one-shot: subscribe to new envelopes, not a previous mount's result.
    const unsubscribeDrop = store.subscribe('projectDrop', value => {
      if (disposed) return;
      card.classList.toggle('drop-target', value.over);
      if (value.result) {
        if (value.result.added.length) added(value.result.added);
        if (value.result.error !== null) showHint(value.result.error);
      }
    });
    const cleanupScrollHints = installScrollHints(list, { win });
    return () => {
      disposed = true;
      generation++;
      unsubscribeConfig();
      manage.removeEventListener('click', toggleManagement);
      unsubscribeSelection();
      unsubscribeDrop();
      input.removeEventListener('input', onInput);
      input.removeEventListener('keydown', onAdd);
      clearConfirmation();
      awaitingScroll.clear();
      cleanupScrollHints();
      clearMessage();
      rowCleanups.forEach(off => off());
      rowCleanups = [];
    };
  },
};
