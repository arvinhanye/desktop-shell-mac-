export function scrollHintState({ scrollTop, clientHeight, scrollHeight }) {
  const scrollable = scrollHeight - clientHeight > 1;
  return {
    above: scrollable && scrollTop > 1,
    below: scrollable && scrollTop + clientHeight < scrollHeight - 1,
  };
}

export function installScrollHints(list, { win = window } = {}) {
  let disposed = false;
  const update = () => {
    if (disposed) return;
    const { above, below } = scrollHintState(list);
    list.classList.toggle('more-above', above);
    list.classList.toggle('more-below', below);
  };
  const resizeObserver = new win.ResizeObserver(update);
  const mutationObserver = new win.MutationObserver(update);
  list.addEventListener('scroll', update, { passive: true });
  resizeObserver.observe(list);
  mutationObserver.observe(list, { childList: true, subtree: true });
  update();
  return () => {
    disposed = true;
    resizeObserver.disconnect();
    mutationObserver.disconnect();
    list.removeEventListener('scroll', update);
  };
}
