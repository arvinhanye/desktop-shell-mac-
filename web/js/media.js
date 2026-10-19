export function avatarUrl(media, ui) {
  const avatars = media?.avatars ?? [];
  return avatars.find(item => item.id === ui?.avatarId)?.url ?? avatars[0]?.url ?? null;
}

export function backgroundUrl(media, ui) {
  if (ui?.backgroundId == null) return null;
  return media?.backgrounds?.find(item => item.id === ui.backgroundId)?.url ?? null;
}
