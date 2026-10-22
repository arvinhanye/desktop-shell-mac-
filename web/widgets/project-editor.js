const segmenter = new Intl.Segmenter(undefined, { granularity: 'grapheme' });
export const projectNameLength = text => [...segmenter.segment(text.trim())].length;
export function projectEditPatch(original, draft) {
  const patch = {};
  if (draft.name.trim() !== original.name) patch.name = draft.name.trim();
  if (draft.appId !== original.appId) patch.appId = draft.appId;
  if (Object.hasOwn(draft, 'reminderListOptionId')) patch.reminderListOptionId = draft.reminderListOptionId;
  return patch;
}

export default {
  name: 'project-editor', css: 'project-editor.css',
  mount(host, { store, bridge }) {
    const doc = host.ownerDocument, win = doc.defaultView;
    const node = (tag, cls, text) => { const n = doc.createElement(tag); n.className = cls; if (text !== undefined) n.textContent = text; return n; };
    const overlay = node('div', 'project-editor-overlay'); overlay.hidden = true; overlay.setAttribute('data-hit', '');
    const panel = node('div', 'project-editor-panel'); panel.setAttribute('data-glass', ''); panel.setAttribute('role', 'dialog'); panel.setAttribute('aria-label', '编辑项目');
    const head = node('div', 'card-head'), cancel = node('button', 'project-editor-cancel ghost-button', '取消'), save = node('button', 'project-editor-save primary-button', '保存');
    cancel.type = save.type = 'button'; head.append(node('h2', 'card-title', '编辑项目'), cancel, save);
    const scroll = node('div', 'project-editor-scroll scroll-list'), label = node('label', 'project-editor-label', '显示名称');
    const name = node('input', 'project-editor-name'); name.type = 'text'; name.setAttribute('autocomplete', 'off'); name.setAttribute('spellcheck', 'false'); label.append(name);
    const apps = node('div', 'project-editor-options'), lists = node('div', 'project-editor-options');
    apps.setAttribute('role', 'group'); apps.setAttribute('aria-label', '默认打开应用'); lists.setAttribute('role', 'group'); lists.setAttribute('aria-label', '提醒事项列表');
    const binding = node('p', 'card-meta'), message = node('p', 'project-editor-message'); message.setAttribute('role', 'status');
    scroll.append(label, node('h3', '', '默认打开应用'), apps, node('h3', '', '提醒事项列表'), binding, lists, message);
    panel.append(head, scroll); overlay.append(panel); host.append(overlay);
    const notice = node('p', 'project-editor-notice'); notice.hidden = true; notice.setAttribute('role', 'status'); host.append(notice);
    let noticeTimer;
    let disposed = false, generation = 0, current = null, original, draft, options, pending = false;
    let choiceCleanups = [];
    const clearChoices = () => { choiceCleanups.forEach(off => off()); choiceCleanups = []; };
    const blur = () => { if (doc.activeElement === name) name.blur(); };
    const close = () => store.set({ editingProjectId: null });
    const valid = () => draft && projectNameLength(draft.name) > 0 && projectNameLength(draft.name) <= 100;
    const updateSave = () => { save.disabled = pending || !valid(); name.disabled = !draft || pending; };
    const renderChoices = () => {
      clearChoices(); apps.replaceChildren(); lists.replaceChildren();
      const choice = (parent, text, selected, disabled, select) => {
        const button = node('button', 'project-editor-option', text); button.type = 'button'; button.disabled = disabled || pending;
        button.setAttribute('aria-pressed', String(selected));
        const click = () => { if (disposed || button.disabled) return; select(); renderChoices(); updateSave(); };
        button.addEventListener('click', click); choiceCleanups.push(() => button.removeEventListener('click', click)); parent.append(button);
      };
      if (!draft) return;
      for (const app of store.get('config')?.apps ?? []) choice(apps, app.name, draft.appId === app.id, false, () => { draft.appId = app.id; });
      if (!apps.children.length) apps.append(node('p', 'card-meta', '未配置应用，仍可在访达打开'));
      const status = {none:'未关联，新增待办使用系统默认列表',linked:'已关联',missing:'关联列表已失联，请重新选择或解除',
        'read-only':'当前列表只读',unavailable:'提醒事项权限未就绪，仍可修改其他字段',shared:'历史共享列表，保留原有归属'};
      binding.textContent = status[options.binding.status] ?? '请检查关联状态';
      choice(lists, '保持当前关联', !Object.hasOwn(draft,'reminderListOptionId'), false, () => { delete draft.reminderListOptionId; });
      choice(lists, '不关联（使用默认列表）', draft.reminderListOptionId === null, false, () => { draft.reminderListOptionId = null; });
      options.lists.forEach((list, index) => {
        const occupied = list.assignedProjectId !== null && list.assignedProjectId !== current;
        const suffix = !list.canWrite ? ' · 只读' : occupied ? ' · 已占用' : '';
        const linked = options.binding.optionId === list.id ? ' · 当前' : '';
        choice(lists, `${list.title} · ${list.source} · ${index + 1}${suffix}${linked}`, draft.reminderListOptionId === list.id,
          !list.canWrite || occupied || options.access !== 'granted', () => { draft.reminderListOptionId = list.id; });
      });
    };
    const open = async id => {
      const version = ++generation; blur(); scroll.scrollTop = 0; current = id; original = draft = options = null; pending = false;
      clearChoices(); apps.replaceChildren(); lists.replaceChildren(); name.value = ''; binding.textContent = ''; message.textContent = '';
      overlay.hidden = id === null; updateSave(); if (id === null || disposed) return;
      store.set({ appearanceOpen: false, layoutOpen: false });
      message.textContent = '读取项目设置…';
      try {
        const reply = await bridge.send('getProjectEditOptions', { projectId: id });
        if (disposed || version !== generation) return;
        options = reply; original = { name: reply.project.name, appId: reply.project.appId }; draft = { ...original };
        name.value = draft.name; message.textContent = ''; renderChoices(); updateSave();
      } catch {
        if (!disposed && version === generation) message.textContent = '读取失败，请关闭后重试';
      }
    };
    const input = () => { if (!draft || pending) return; draft.name = name.value; message.textContent = valid() ? '' : '名称需为 1–100 个字'; updateSave(); };
    const submit = async () => {
      if (disposed || pending || !valid()) return;
      const patch = projectEditPatch(original, draft);
      if (!Object.keys(patch).length) { close(); return; }
      const version = ++generation, id = current; pending = true; updateSave(); renderChoices(); message.textContent = '正在保存…';
      try {
        await bridge.send('updateProject', { projectId: id, ...patch });
        if (!disposed && version === generation) close();
      } catch (error) {
        if (!disposed && version === generation) message.textContent = error.code === 'not-found'
          ? '保存失败，项目、应用或列表已变化，请重新打开检查' : '保存失败，请检查列表权限或占用情况后重试';
      } finally {
        if (!disposed && version === generation) { pending = false; updateSave(); renderChoices(); }
      }
    };
    const escape = event => { if (event.key === 'Escape' && !event.isComposing) close(); };
    const clickOverlay = event => { if (event.target === overlay) close(); };
    name.addEventListener('input', input); save.addEventListener('click', submit); cancel.addEventListener('click', close);
    overlay.addEventListener('keydown', escape); overlay.addEventListener('click', clickOverlay);
    const subscriptions = [store.subscribe('editingProjectId', open, { immediate: true }), store.subscribe('config', config => {
      if (current !== null && !config?.projects.some(p => p.id === current)) {
        close(); win.clearTimeout(noticeTimer); notice.textContent = '项目已被移除'; notice.hidden = false;
        noticeTimer = win.setTimeout(() => { notice.hidden = true; }, 3000);
      }
    })];
    return () => {
      if (disposed) return; blur(); win.clearTimeout(noticeTimer); disposed = true; generation++; clearChoices(); subscriptions.forEach(off => off());
      name.removeEventListener('input', input); save.removeEventListener('click', submit); cancel.removeEventListener('click', close);
      overlay.removeEventListener('keydown', escape); overlay.removeEventListener('click', clickOverlay);
    };
  },
};
