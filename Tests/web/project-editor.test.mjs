import test from 'node:test';
import assert from 'node:assert/strict';
import editor, { projectNameLength, projectEditPatch } from '../../web/widgets/project-editor.js';
import projects, { moveProjectIds } from '../../web/widgets/projects.js';
import { createStore, initialState } from '../../web/js/store.js';
import { createMock } from '../../web/js/mock.js';
import { createBrowser, byClass, one } from './helpers/linkage-browser.mjs';
const flush = () => new Promise(resolve => setImmediate(resolve));
const deferred = () => { let resolve, reject; const promise = new Promise((a,b) => { resolve=a; reject=b; }); return { promise, resolve, reject }; };
const config = { projects: [{id:'a',name:'A'},{id:'b',name:'B'}] };
const options = id => ({project:{id,name:id.toUpperCase()},access:'granted',binding:{status:'none',optionId:null},lists:[
  {id:'list-1',title:'<b>Same</b>',source:'One',canWrite:true,assignedProjectId:null},
  {id:'list-2',title:'Same',source:'Two',canWrite:false,assignedProjectId:null},
]});
function fixture(send = async (action, p) => options(p.projectId)) {
  const browser = createBrowser(0), host = browser.doc.createElement('section'); browser.desktop.append(host);
  const store = createStore({...initialState, config:structuredClone(config)}), calls=[];
  const bridge={send(action,payload){calls.push({action,payload});return send(action,payload);}};
  return {...browser,host,store,bridge,calls};
}
test('editor: grapheme counts and changed-field patches preserve untouched bindings', () => {
  assert.equal(projectNameLength('  '),0); assert.equal(projectNameLength('👨‍👩‍👧‍👦'),1);
  assert.equal(projectNameLength('家'.repeat(100)),100); assert.equal(projectNameLength('家'.repeat(101)),101);
  const original={name:'Name'};
  assert.deepEqual(projectEditPatch(original,{...original,name:' Name '}),{});
  assert.deepEqual(projectEditPatch(original,{...original,reminderListOptionId:null}),{reminderListOptionId:null});
  assert.deepEqual(projectEditPatch(original,{...original,name:'New'}),{name:'New'});
});
test('editor: project options need only identity and name, and the panel edits name and reminder lists', async () => {
  const f=fixture(async (action,payload)=>action==='getProjectEditOptions'?options(payload.projectId):null);
  const stop=editor.mount(f.host,f);f.store.set({editingProjectId:'a'});await flush();
  assert.doesNotMatch(f.host.textContent,/默认打开应用/);
  const groups=byClass(f.host,'project-editor-options');
  assert.deepEqual(groups.map(group=>group.getAttribute('aria-label')),['提醒事项列表']);
  const name=one(f.host,'project-editor-name');assert.equal(name.value,'A');
  name.value='Renamed';await name.emit('input');
  const list=byClass(f.host,'project-editor-option').find(button=>button.textContent.includes('<b>Same</b>'));
  await list.emit('click');await one(f.host,'project-editor-save').emit('click');
  assert.deepEqual(f.calls,[
    {action:'getProjectEditOptions',payload:{projectId:'a'}},
    {action:'updateProject',payload:{projectId:'a',name:'Renamed',reminderListOptionId:'list-1'}},
  ]);
  assert.equal(f.store.get('editingProjectId'),null);stop();f.assertClean();
});
test('projects: move uses complete latest IDs and guards boundaries', () => {
  assert.deepEqual(moveProjectIds(config.projects,'b',-1),['b','a']);
  assert.equal(moveProjectIds(config.projects,'a',-1),null); assert.equal(moveProjectIds(config.projects,'b',1),null);
  assert.equal(moveProjectIds(config.projects,'missing',1),null);
});
test('editor: cancel discards draft, failed saves preserve it, unsafe labels remain text', async () => {
  const f=fixture(async (a,p)=>{if(a==='updateProject')throw new Error('failed');return options(p.projectId);});
  const stop=editor.mount(f.host,f);f.store.set({editingProjectId:'a'});await flush();
  assert.equal(f.store.get('appearanceOpen'),false);
  const name=one(f.host,'project-editor-name'); name.value='Changed';await name.emit('input');
  assert.match(f.host.textContent,/<b>Same<\/b>/);assert.equal(byClass(f.host,'project-editor-option').find(n=>n.textContent.includes('<b>')).children.length,0);
  await one(f.host,'project-editor-save').emit('click');
  assert.equal(name.value,'Changed');assert.match(one(f.host,'project-editor-message').textContent,/保存失败/);
  one(f.host,'project-editor-scroll').scrollTop=120;await one(f.host,'project-editor-cancel').emit('click');f.store.set({editingProjectId:'a'});await flush();
  assert.equal(one(f.host,'project-editor-scroll').scrollTop,0);
  assert.equal(name.value,'A');stop();f.assertClean();
});
test('editor: failed loading is an error, reopening clears it before loading new options', async () => {
  let pending=deferred();const f=fixture(()=>pending.promise);
  const stop=editor.mount(f.host,f);f.store.set({editingProjectId:'a'});
  const message=one(f.host,'project-editor-message');
  assert.match(message.textContent,/读取项目设置/);assert.equal(message.classList.contains('error'),false);
  pending.reject(new Error('failed'));await flush();
  assert.match(message.textContent,/读取失败/);assert.equal(message.classList.contains('error'),true);
  await one(f.host,'project-editor-cancel').emit('click');pending=deferred();f.store.set({editingProjectId:'b'});
  assert.match(message.textContent,/读取项目设置/);assert.equal(message.classList.contains('error'),false);
  pending.resolve(options('b'));await flush();
  assert.equal(message.textContent,'');assert.equal(message.classList.contains('error'),false);
  stop();f.assertClean();
});
test('editor: validation and save failures are errors, correction and saving clear the error state', async () => {
  let pending=deferred();const f=fixture((action,p)=>action==='updateProject'?pending.promise:Promise.resolve(options(p.projectId)));
  const stop=editor.mount(f.host,f);f.store.set({editingProjectId:'a'});await flush();
  const name=one(f.host,'project-editor-name'),message=one(f.host,'project-editor-message'),save=one(f.host,'project-editor-save');
  name.value=' ';await name.emit('input');
  assert.equal(save.disabled,true);assert.equal(message.classList.contains('error'),true);
  name.value='Changed';await name.emit('input');
  assert.equal(save.disabled,false);assert.equal(message.textContent,'');assert.equal(message.classList.contains('error'),false);
  const first=save.emit('click');assert.match(message.textContent,/正在保存/);assert.equal(message.classList.contains('error'),false);
  pending.reject(Object.assign(new Error('not-found'),{code:'not-found'}));await first;
  assert.match(message.textContent,/保存失败.*已变化/);assert.equal(message.classList.contains('error'),true);assert.equal(name.value,'Changed');
  pending=deferred();const retry=save.emit('click');
  assert.match(message.textContent,/正在保存/);assert.equal(message.classList.contains('error'),false);
  pending.reject(new Error('failed'));await retry;
  assert.match(message.textContent,/保存失败.*权限/);assert.equal(message.classList.contains('error'),true);
  name.value='Corrected';await name.emit('input');assert.equal(message.textContent,'');assert.equal(message.classList.contains('error'),false);
  stop();f.assertClean();
});
test('editor: stale options and late save never replace new editor; remote deletion closes', async () => {
  const pending=deferred();const f=fixture((a,p)=>p.projectId==='a'?pending.promise:Promise.resolve(options('b')));
  const stop=editor.mount(f.host,f);f.store.set({editingProjectId:'a'});f.store.set({editingProjectId:'b'});await flush();
  pending.resolve(options('a'));await flush();assert.equal(one(f.host,'project-editor-name').value,'B');
  f.store.set({config:{...config,projects:[config.projects[0]]}});assert.equal(f.store.get('editingProjectId'),null);
  assert.equal(one(f.host,'project-editor-overlay').hidden,true);assert.equal(one(f.host,'project-editor-notice').textContent,'项目已被移除');stop();f.assertClean();
});
test('editor: pending saves deduplicate; close releases text focus before hiding', async () => {
  const pending=deferred();const f=fixture((a,p)=>a==='updateProject'?pending.promise:Promise.resolve(options(p.projectId)));
  const stop=editor.mount(f.host,f);f.store.set({editingProjectId:'a'});await flush();
  const name=one(f.host,'project-editor-name');name.value='New';await name.emit('input');
  const save=one(f.host,'project-editor-save');const click=save.emit('click');await save.emit('click');
  assert.equal(f.calls.filter(c=>c.action==='updateProject').length,1);
  f.doc.activeElement=name;let blurred=false;name.blur=()=>{blurred=true;assert.equal(one(f.host,'project-editor-overlay').hidden,false);f.doc.activeElement=null;};
  await one(f.host,'project-editor-cancel').emit('click');assert.equal(blurred,true);
  pending.resolve({});await click;assert.equal(f.store.get('editingProjectId'),null);stop();f.assertClean();
});
test('projects: management buttons do not select, reorder is pending-safe and push-owned', async () => {
  const pending=deferred();const f=fixture(()=>pending.promise);const stop=projects.mount(f.host,f);
  await one(f.host,'project-manage-toggle').emit('click');
  assert.equal(byClass(f.host,'project-up')[0].disabled,true);
  await byClass(f.host,'project-edit')[1].emit('click');assert.equal(f.store.get('editingProjectId'),'b');assert.equal(f.store.get('selectedProject'),null);
  const up=byClass(f.host,'project-up')[1];const click=up.emit('click');await up.emit('click');
  assert.deepEqual(f.calls,[{action:'reorderProjects',payload:{projectIds:['b','a']}}]);
  assert.deepEqual(f.store.get('config').projects.map(p=>p.id),['a','b']);pending.resolve(null);await click;stop();f.assertClean();
});
test('mock: edit options, duplicate titles, read-only denial, binding and order match native', async () => {
  const mock=createMock();const first=await mock.handle({action:'getProjectEditOptions',projectId:'photos'});
  assert.equal(first.project.id,'photos');assert.equal(first.binding.status,'none');
  const free=first.lists.find(x=>x.canWrite&&!x.assignedProjectId);
  const readonly=first.lists.find(x=>!x.canWrite);
  await assert.rejects(mock.handle({action:'updateProject',projectId:'photos',reminderListOptionId:readonly.id}),/failed/);
  await mock.handle({action:'updateProject',projectId:'photos',name:' Pictures ',reminderListOptionId:free.id});
  const linked=await mock.handle({action:'getProjectEditOptions',projectId:'photos'});assert.equal(linked.project.name,'Pictures');assert.equal(linked.binding.status,'linked');
  await assert.rejects(mock.handle({action:'updateProject',projectId:'budget',reminderListOptionId:free.id}),/failed/);
  await mock.handle({action:'updateProject',projectId:'photos',reminderListOptionId:null});
  mock.setTodosAccess('denied');await mock.handle({action:'updateProject',projectId:'photos',name:'Allowed'});
  await assert.rejects(mock.handle({action:'updateProject',projectId:'photos',reminderListOptionId:free.id}),/failed/);
  const ids=(await mock.handle({action:'getConfig'})).config.projects.map(p=>p.id).reverse();
  await mock.handle({action:'reorderProjects',projectIds:ids});assert.deepEqual((await mock.handle({action:'getConfig'})).config.projects.map(p=>p.id),ids);
  await assert.rejects(mock.handle({action:'reorderProjects',projectIds:['photos']}),/not-found/);
});

test('projects: leaving management during failed reorder still reports and refreshes config', async () => {
  const pending=deferred(); const f=fixture((action)=>action==='reorderProjects'?pending.promise:Promise.resolve({config}));
  const stop=projects.mount(f.host,f); await one(f.host,'project-manage-toggle').emit('click');
  const click=byClass(f.host,'project-up')[1].emit('click');
  await one(f.host,'project-manage-toggle').emit('click'); pending.reject(new Error('not-found')); await click;
  assert.deepEqual(f.calls.map(c=>c.action),['reorderProjects','getConfig']);
  assert.match(one(one(f.host,'card-head'),'card-meta').textContent,/排序失败/);stop();f.assertClean();
});

test('mock: revoked options expire, renamed IDs stay linked, read-only and missing writes fail', async () => {
  const mock=createMock();const get=()=>mock.handle({action:'getProjectEditOptions',projectId:'photos'});
  const first=await get();const old=first.lists.find(x=>x.canWrite&&!x.assignedProjectId).id;
  mock.setTodosAccess('denied');await get();mock.setTodosAccess('granted');
  await assert.rejects(mock.handle({action:'updateProject',projectId:'photos',reminderListOptionId:old}),/not-found/);
  const token=(await get()).lists.find(x=>x.canWrite&&!x.assignedProjectId).id;
  await mock.handle({action:'updateProject',projectId:'photos',reminderListOptionId:token});
  mock.setReminderList(token,{title:'Renamed'});assert.equal((await get()).binding.status,'linked');
  mock.setReminderList(token,{canWrite:false});assert.equal((await get()).binding.status,'read-only');
  await assert.rejects(mock.handle({action:'addTodo',text:'Test',projectId:'photos'}),/failed/);
  mock.setReminderList(token,null);assert.equal((await get()).binding.status,'missing');
  await assert.rejects(mock.handle({action:'addTodo',text:'Test',projectId:'photos'}),/not-found/);
});

test('mock: disappeared list no longer owns existing reminder snapshots', async () => {
  const browser=createBrowser(0), mock=createMock({timers:browser.win,now:browser.now}), events=[];
  mock.start(event=>events.push(event));
  try {
    const reply=await mock.handle({action:'getProjectEditOptions',projectId:'desktop-shell'});
    mock.setReminderList(reply.binding.optionId,null);
    const items=events.filter(e=>e.event==='todos').at(-1).items;
    assert.ok(items.filter(i=>['t1','t2','t12','t13'].includes(i.id)).every(i=>i.projectId===null));
  } finally {mock.stop();browser.assertClean();}
});

test('editor: shared current list is disabled even for first owner; keeping binding allows other edits', async () => {
  const reply=options('a'); reply.binding={status:'shared',optionId:'list-1'};
  reply.lists[0].assignedProjectId='a';
  const f=fixture(async action=>action==='getProjectEditOptions'?reply:null);
  const stop=editor.mount(f.host,f);f.store.set({editingProjectId:'a'});await flush();
  const shared=byClass(f.host,'project-editor-option').find(n=>n.textContent.includes('<b>Same</b>'));
  assert.equal(shared.disabled,true);assert.match(shared.textContent,/共享占用/);
  await shared.emit('click');
  const keep=byClass(f.host,'project-editor-option').find(n=>n.textContent==='保持当前关联');
  assert.equal(keep.disabled,false);assert.equal(keep.getAttribute('aria-pressed'),'true');
  const name=one(f.host,'project-editor-name');name.value='Changed';await name.emit('input');await one(f.host,'project-editor-save').emit('click');
  assert.deepEqual(f.calls.at(-1),{action:'updateProject',payload:{projectId:'a',name:'Changed'}});
  stop();f.assertClean();
});
