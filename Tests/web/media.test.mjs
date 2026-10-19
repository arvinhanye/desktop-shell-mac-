import { test } from 'node:test';
import assert from 'node:assert/strict';
import { avatarUrl, backgroundUrl } from '../../web/js/media.js';

const media = Object.freeze({
  avatars: Object.freeze([{ id: 'first', url: '/avatars/first.png' }, { id: 'second', url: '/avatars/second.png' }]),
  backgrounds: Object.freeze([{ id: 'bg', url: '/backgrounds/bg.png' }]),
});
for (const [id, expected] of [['second', '/avatars/second.png'], [null, '/avatars/first.png'], ['missing', '/avatars/first.png']]) {
  test(`media: avatar ${id} resolves or falls back to the first supplied item`, () => {
    assert.equal(avatarUrl(media, { avatarId: id }), expected);
  });
}
for (const id of [null, 'missing']) {
  test(`media: empty avatars with ${id} return null`, () => assert.equal(avatarUrl({ avatars: [] }, { avatarId: id }), null));
}
for (const [id, expected] of [['bg', '/backgrounds/bg.png'], [null, null], ['missing', null]]) {
  test(`media: background ${id} never falls back to the first item`, () => {
    assert.equal(backgroundUrl(media, { backgroundId: id }), expected);
  });
}
test('media: empty backgrounds return null', () => assert.equal(backgroundUrl({ backgrounds: [] }, { backgroundId: 'bg' }), null));
test('media: not-yet-loaded media/ui resolve to null rather than throwing', () => {
  assert.equal(avatarUrl(null, null), null);
  assert.equal(backgroundUrl(null, null), null);
});
