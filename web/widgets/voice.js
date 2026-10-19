export function pickVoice(voices, lastId, random = Math.random) {
  const candidates = voices.length > 1 ? voices.filter(voice => voice.id !== lastId) : voices;
  return candidates[Math.floor(random() * candidates.length)] ?? null;
}

export function createVoicePlayer({ store, createAudio = url => new Audio(url), random = Math.random }) {
  let lastId = null;
  let stopActive = null;
  let disposed = false;

  const request = () => {
    if (disposed || stopActive || !store.get('ui')?.voiceEnabled || store.get('voicePlaying')) return;
    const voice = pickVoice(store.get('media')?.voices ?? [], lastId, random);
    if (!voice) return;
    let audio;
    try { audio = createAudio(voice.url); }
    catch { return; }
    lastId = voice.id;
    let finished = false;
    const finish = (stop = false) => {
      if (finished) return;
      finished = true;
      audio.removeEventListener('ended', onFinish);
      audio.removeEventListener('error', onFinish);
      stopActive = null;
      try { if (stop) audio.pause(); }
      finally { store.set({ voicePlaying: false }); }
    };
    const onFinish = () => finish();
    audio.addEventListener('ended', onFinish);
    audio.addEventListener('error', onFinish);
    stopActive = () => finish(true);
    store.set({ voicePlaying: true });
    // A synchronous subscriber can disable voice while this state change is delivered.
    if (finished) return;
    try { Promise.resolve(audio.play()).catch(() => finish()); }
    catch { finish(); }
  };

  const subscriptions = [
    store.subscribe('voiceRequest', request),
    store.subscribe('ui', ui => { if (!ui?.voiceEnabled) stopActive?.(); }),
  ];
  return () => {
    if (disposed) return;
    disposed = true;
    subscriptions.forEach(off => off());
    stopActive?.();
  };
}

export default {
  name: 'voice',
  mount(host, { store }) {
    host.hidden = true;
    return createVoicePlayer({ store });
  },
};
