import { avatarUrl, backgroundUrl } from '../js/media.js';

export default {
  name: 'character',
  css: 'character.css',
  mount(host, { store }) {
    const doc = host.ownerDocument;
    const element = (tag, className) => {
      const node = doc.createElement(tag);
      node.className = className;
      return node;
    };
    host.setAttribute('aria-label', '角色卡');
    const card = element('div', 'card character-card');
    const art = element('div', 'card-art');
    const avatar = element('button', 'avatar-button');
    avatar.type = 'button';
    avatar.setAttribute('aria-label', '播放一句语音');
    const image = doc.createElement('img');
    image.alt = '';
    image.draggable = false;
    const ring = element('span', 'avatar-ring');
    ring.setAttribute('aria-hidden', 'true');
    avatar.append(image, ring);
    const appearance = element('button', 'appearance-button');
    appearance.type = 'button';
    appearance.innerHTML = '<svg viewBox="0 0 16 16" aria-hidden="true"><path fill="none" stroke="currentColor" stroke-width="1.3" d="M8 1.8a6.2 6.2 0 1 0 0 12.4c.9 0 1.3-.6 1.3-1.2 0-.8-.6-1-.6-1.8 0-.6.5-1.1 1.2-1.1h1.4a2.9 2.9 0 0 0 2.9-2.9C14.2 4.1 11.4 1.8 8 1.8Z"/><circle cx="4.9" cy="7.6" r=".9" fill="currentColor"/><circle cx="6.7" cy="4.9" r=".9" fill="currentColor"/><circle cx="10" cy="4.9" r=".9" fill="currentColor"/></svg>';
    appearance.append('外观');
    const info = element('div', 'character-info');
    const name = element('div', 'character-name');
    const motto = element('div', 'character-motto');
    info.append(name, motto);
    card.append(art, avatar, appearance, info);
    host.append(card);

    const requestVoice = () => {
      if (!store.get('voicePlaying')) store.set({ voiceRequest: store.get('voiceRequest') + 1 });
    };
    const openAppearance = () => store.set({ appearanceOpen: true });
    avatar.addEventListener('click', requestVoice);
    appearance.addEventListener('click', openAppearance);
    const updateMedia = () => {
      const media = store.get('media'), ui = store.get('ui');
      const avatarSource = avatarUrl(media, ui);
      image.hidden = avatarSource === null;
      if (avatarSource === null) image.removeAttribute('src');
      else image.src = avatarSource;
      const background = backgroundUrl(media, ui);
      art.style.backgroundImage = background === null ? 'none' : `url(${JSON.stringify(background)})`;
    };
    const subscriptions = [
      store.subscribe('config', config => {
        name.textContent = config?.character?.name ?? '';
        motto.textContent = config?.character?.motto ?? '';
      }, { immediate: true }),
      store.subscribe('media', updateMedia, { immediate: true }),
      store.subscribe('ui', updateMedia, { immediate: true }),
      store.subscribe('voicePlaying', playing => avatar.classList.toggle('playing', playing), { immediate: true }),
    ];
    return () => {
      subscriptions.forEach(off => off());
      avatar.removeEventListener('click', requestVoice);
      appearance.removeEventListener('click', openAppearance);
    };
  },
};
