import { installScrollHints } from '../js/scroll-hints.js';

const segmenter = new Intl.Segmenter(undefined, { granularity: 'grapheme' });

export function dueLabel(due, now = Date.now()) {
  if (!due) return null;
  const current = new Date(now ?? Date.now());
  const [year, month, day] = due.date.split('-').map(Number);
  const target = new Date(year, month - 1, day);
  const today = new Date(current.getFullYear(), current.getMonth(), current.getDate());
  // Local midnights may be 23 or 25 hours apart around daylight-saving changes.
  const difference = Math.round((target - today) / 86400000);
  const label = difference === 0 ? '今天' : difference === 1 ? '明天' : difference === -1 ? '昨天' : `${month}月${day}日`;
  const time = `${String(current.getHours()).padStart(2, '0')}:${String(current.getMinutes()).padStart(2, '0')}`;
  return {
    text: due.time ? `${label} ${due.time}` : label,
    overdue: difference < 0 || (difference === 0 && due.time != null && due.time < time),
  };
}

export function visibleTodos(todos, selectedProject) {
  const visible = todos.filter(todo => selectedProject == null || todo.projectId === selectedProject);
  return { open: visible.filter(todo => !todo.done), done: visible.filter(todo => todo.done) };
}

export function accessView(access) {
  if (access === 'granted') return { canEdit: true, title: '', message: '' };
  if (access === 'unknown') return { canEdit: false, title: '', message: '' };
  if (access === 'notDetermined') return { canEdit: false, title: '正在等待提醒事项权限', message: '在弹出的对话框里点「允许」' };
  return { canEdit: false, title: '还不能读取提醒事项', message: '到「系统设置 → 隐私与安全性 → 提醒事项」里允许 DesktopShell' };
}

export function graphemeCount(text) {
  return Array.from(segmenter.segment(text)).length;
}

export function scopeText(project) {
  return project ? `只看「${project.name}」` : '全部列表';
}

export function hintText(project) {
  return project?.hasReminders === false ? '这个项目没有对应的提醒事项列表，新增的提醒会放进默认列表' : '';
}

export default {
  name: 'todos',
  css: 'todos.css',
  mount(host, { store, bridge }) {
    const doc = host.ownerDocument;
    const element = (tag, className, text) => {
      const node = doc.createElement(tag);
      node.className = className;
      if (text !== undefined) node.textContent = text;
      return node;
    };
    host.setAttribute('aria-label', '待办');
    const card = element('div', 'card todos-card');
    const head = element('div', 'card-head');
    const scope = element('span', 'card-meta');
    head.append(element('h2', 'card-title', '待办'), scope);
    const add = element('label', 'todo-add');
    const plus = element('span', '', '＋');
    plus.setAttribute('aria-hidden', 'true');
    const input = element('input', '');
    input.type = 'text';
    input.placeholder = '添加提醒，按回车保存';
    add.append(plus, input);
    const hint = element('p', 'todo-hint');
    const list = element('ul', 'todo-list scroll-list');
    card.append(head, add, hint, list);
    host.append(card);

    let disposed = false;
    let adding = false;
    let error = '';
    let rowCleanups = [];
    const pending = new Map();
    const selectedProject = () => store.get('config')?.projects?.find(project => project.id === store.get('selectedProject'));
    const updateHint = () => { hint.textContent = error || hintText(selectedProject()); };
    const checkIcon = () => {
      const svg = doc.createElementNS('http://www.w3.org/2000/svg', 'svg');
      svg.setAttribute('viewBox', '0 0 10 10');
      svg.setAttribute('aria-hidden', 'true');
      const path = doc.createElementNS('http://www.w3.org/2000/svg', 'path');
      for (const [key, value] of Object.entries({ d: 'M1.5 5.2 4 7.6 8.6 2.6', fill: 'none', stroke: 'currentColor', 'stroke-width': '1.8', 'stroke-linecap': 'round', 'stroke-linejoin': 'round' })) path.setAttribute(key, value);
      svg.append(path);
      return svg;
    };
    const setDone = async todo => {
      if (disposed || store.get('todosAccess') !== 'granted' || pending.get(todo.id)?.inFlight) return;
      const previous = pending.get(todo.id);
      const done = !todo.done;
      const change = { done, inFlight: true, snapshot: store.get('todos') };
      pending.set(todo.id, change);
      render();
      try {
        await bridge.send('setTodoDone', { todoId: todo.id, done });
        if (!disposed) {
          change.inFlight = false;
          // A native reply can precede its debounced push. Retain the accepted
          // state unless a fresh snapshot already confirms it (or removes it).
          const source = store.get('todos');
          const current = source.find(item => item.id === todo.id);
          if (source !== change.snapshot && (!current || current.done === done)) pending.delete(todo.id);
          error = '';
        }
      } catch {
        if (!disposed) {
          if (previous && store.get('todos') === change.snapshot) pending.set(todo.id, previous);
          else pending.delete(todo.id);
          error = '没能更新这条提醒，请再试一次';
        }
      } finally {
        if (!disposed) render();
      }
    };
    const appendTodo = todo => {
      const row = element('li', `todo${todo.done ? ' done' : ''}`);
      const button = element('button', 'todo-check');
      button.type = 'button';
      button.setAttribute('aria-label', todo.done ? '取消完成' : '完成');
      button.append(checkIcon());
      const click = () => setDone(todo);
      button.addEventListener('click', click);
      rowCleanups.push(() => button.removeEventListener('click', click));
      const content = element('div', '');
      content.append(element('span', 'todo-text', todo.text));
      const due = dueLabel(todo.due, store.get('now'));
      if (!todo.done && due) content.append(element('span', `todo-due${due.overdue ? ' overdue' : ''}`, `${due.overdue ? '已过期 ' : ''}${due.text}`));
      row.append(button, content);
      list.append(row);
    };
    const render = () => {
      if (disposed) return;
      scope.textContent = scopeText(selectedProject());
      updateHint();
      const access = accessView(store.get('todosAccess'));
      add.hidden = !access.canEdit;
      input.disabled = !access.canEdit;
      const scrollTop = list.scrollTop;
      rowCleanups.forEach(off => off());
      rowCleanups = [];
      list.replaceChildren();
      const source = store.get('todos');
      if (access.canEdit) {
        // Overlay only in this view. Bridge remains the sole writer of shared todos.
        const items = source.map(todo => pending.has(todo.id) ? { ...todo, done: pending.get(todo.id).done } : todo);
        const { open, done } = visibleTodos(items, store.get('selectedProject'));
        if (!open.length && !done.length) list.append(element('li', 'todo-empty', '没有待办。在上面输入一条，按回车保存'));
        open.forEach(appendTodo);
        if (done.length) {
          list.append(element('li', 'todo-section', '今天完成'));
          done.forEach(appendTodo);
        }
      } else if (access.title) {
        const denied = element('li', 'todo-denied');
        denied.append(element('strong', '', access.title), doc.createTextNode(access.message));
        list.append(denied);
      }
      list.scrollTop = scrollTop;
    };
    const onInput = () => {
      if (disposed) return;
      error = '';
      updateHint();
    };
    const onKeydown = async event => {
      if (disposed || event.key !== 'Enter' || event.isComposing || store.get('todosAccess') !== 'granted') return;
      event.preventDefault();
      if (adding) return;
      const draft = input.value;
      const text = draft.trim();
      if (!text) return;
      if (graphemeCount(text) > 500) {
        error = '最多 500 个字';
        updateHint();
        return;
      }
      const payload = { text };
      const projectId = store.get('selectedProject');
      if (projectId != null) payload.projectId = projectId;
      adding = true;
      try {
        await bridge.send('addTodo', payload);
        if (!disposed) {
          if (input.value === draft) input.value = '';
          error = '';
          updateHint();
        }
      } catch {
        if (!disposed) {
          error = '没能添加，请再试一次';
          updateHint();
        }
      } finally { adding = false; }
    };
    input.addEventListener('input', onInput);
    input.addEventListener('keydown', onKeydown);
    const subscriptions = ['config', 'selectedProject', 'todosAccess', 'now']
      .map(key => store.subscribe(key, render, { immediate: true }));
    subscriptions.push(store.subscribe('todos', () => {
      // A later snapshot is authoritative even if another client has already
      // undone our change. Only requests still in flight retain their overlay.
      for (const [id, change] of pending) if (!change.inFlight) pending.delete(id);
      render();
    }, { immediate: true }));
    const cleanupScrollHints = installScrollHints(list, { win: doc.defaultView });
    return () => {
      disposed = true;
      subscriptions.forEach(off => off());
      cleanupScrollHints();
      input.removeEventListener('input', onInput);
      input.removeEventListener('keydown', onKeydown);
      rowCleanups.forEach(off => off());
      rowCleanups = [];
      pending.clear();
    };
  },
};
