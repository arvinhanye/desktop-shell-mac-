const textInputTypes = new Set(['text', 'search', 'email', 'url', 'tel', 'password', 'number']);

export function isTextEntry(element) {
  if (!element) return false;
  return element.isContentEditable === true || element.tagName === 'TEXTAREA'
    || (element.tagName === 'INPUT' && textInputTypes.has(element.type ?? 'text'));
}

export function installKeyboardFocus({ doc = document, win = window, send }) {
  // Bridge owns failure logging; event handlers must consume rejected replies.
  const notify = action => { send(action).catch(() => {}); };
  doc.addEventListener('focusin', event => {
    if (isTextEntry(event.target)) notify('focusInput');
  }, true);
  doc.addEventListener('focusout', event => {
    if (isTextEntry(event.target) && !isTextEntry(event.relatedTarget)) notify('blurInput');
  }, true);
  doc.addEventListener('keydown', event => {
    if (event.key === 'Escape' && !event.isComposing && isTextEntry(event.target)) event.target.blur();
  }, true);
  win.addEventListener('blur', () => {
    // Prevent WebKit from restoring the last input when the app is activated later.
    if (isTextEntry(doc.activeElement)) doc.activeElement.blur();
  });
}
