export async function mountWidgets(container, names, ctx, {
  load = name => import(new URL(`../widgets/${name}.js`, import.meta.url)),
} = {}) {
  const doc = container.ownerDocument;
  const slots = names.map(name => {
    try {
      if (typeof name !== 'string' || !/^[a-z][a-z0-9-]*$/.test(name)) throw new Error('组件名不合法');
      const host = doc.createElement('section');
      host.className = 'widget';
      host.dataset.widget = name;
      container.append(host);
      return { name, host };
    } catch (error) { console.error(`组件 ${name} 加载失败`, error); return null; }
  });
  const loaded = await Promise.all(slots.map(async slot => {
    if (!slot) return null;
    const { name, host } = slot;
    try {
      const module = (await load(name)).default;
      if (!module || module.name !== name || typeof module.mount !== 'function') throw new Error('组件导出不合法');
      if (module.css !== undefined) {
        if (typeof module.css !== 'string' || !/^[a-z][a-z0-9-]*\.css$/.test(module.css)) throw new Error('组件样式文件名不合法');
        const link = doc.createElement('link');
        link.rel = 'stylesheet';
        link.href = new URL(`../widgets/${module.css}`, import.meta.url).href;
        await new Promise(resolve => {
          link.addEventListener('load', resolve, { once: true });
          link.addEventListener('error', resolve, { once: true });
          doc.head.append(link);
        });
      }
      const cleanup = await module.mount(host, ctx);
      if (typeof cleanup === 'function') host.widgetCleanup = cleanup;
      return name;
    } catch (error) {
      console.error(`组件 ${name} 加载失败`, error);
      host.remove();
      return null;
    }
  }));
  return loaded.filter(name => name !== null);
}
