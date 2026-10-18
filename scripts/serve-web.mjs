import http from 'node:http';
import { open, realpath } from 'node:fs/promises';
import { dirname, extname, join, resolve, sep } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';

const repository = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const types = {
  html: 'text/html', js: 'text/javascript', mjs: 'text/javascript', css: 'text/css', json: 'application/json',
  png: 'image/png', jpg: 'image/jpeg', jpeg: 'image/jpeg', svg: 'image/svg+xml', webp: 'image/webp',
  mp3: 'audio/mpeg', mp4: 'video/mp4', woff2: 'font/woff2', woff: 'font/woff', ttf: 'font/ttf', otf: 'font/otf', txt: 'text/plain',
};
function rangeFor(header, size) {
  if (header === undefined || header === '') return { status: 200, start: 0, end: size - 1 };
  const match = /^bytes=(\d*)-(\d*)$/.exec(header);
  if (!match || size === 0 || (!match[1] && !match[2])) return null;
  const total = BigInt(size);
  const first = match[1] ? BigInt(match[1]) : null;
  const last = match[2] ? BigInt(match[2]) : null;
  if (first === null) {
    if (last === 0n) return null;
    return { status: 206, start: Number(last >= total ? 0n : total - last), end: size - 1 };
  }
  if (first >= total || (last !== null && last < first)) return null;
  return { status: 206, start: Number(first), end: Number(last === null || last >= total ? total - 1n : last) };
}

export function createDevServer({
  webRoot = join(repository, 'web'),
  mediaRoot = join(process.env.DESKTOPSHELL_SUPPORT_DIR || join(homedir(), 'Library/Application Support/DesktopShell'), 'media'),
  designRoot = join(repository, 'docs/design'),
} = {}) {
  return http.createServer(async (request, response) => {
    response.setHeader('Cache-Control', 'no-store');
    const empty = status => { response.writeHead(status, { 'Content-Length': 0 }); response.end(); };
    if (!['GET', 'HEAD'].includes(request.method)) {
      response.setHeader('Allow', 'GET, HEAD'); empty(405); return;
    }
    let handle;
    try {
      // Do not use URL.pathname: URL parsing normalizes away traversal before validation.
      const path = decodeURIComponent(request.url.split('?')[0]);
      if (!path.startsWith('/') || path.includes('\0')) { empty(404); return; }
      let root = webRoot;
      let relative = path === '/' ? 'index.html' : path.slice(1);
      if (path.startsWith('/media/')) { root = mediaRoot; relative = path.slice(7); }
      else if (path.startsWith('/design/')) { root = designRoot; relative = path.slice(8); }
      if (relative.split('/').some(part => !part || part.startsWith('.'))) { empty(404); return; }
      const resolvedRoot = await realpath(root);
      const file = await realpath(join(resolvedRoot, relative));
      if (!file.startsWith(resolvedRoot.endsWith(sep) ? resolvedRoot : resolvedRoot + sep)) { empty(404); return; }
      handle = await open(file, 'r');
      const info = await handle.stat();
      if (!info.isFile()) { empty(404); return; }
      const range = rangeFor(request.headers.range, info.size);
      response.setHeader('Accept-Ranges', 'bytes');
      if (!range) {
        response.setHeader('Content-Range', `bytes */${info.size}`); empty(416); return;
      }
      const type = types[extname(file).slice(1).toLowerCase()] ?? 'application/octet-stream';
      response.setHeader('Content-Type', type.startsWith('text/') || ['application/json', 'image/svg+xml'].includes(type) ? `${type}; charset=utf-8` : type);
      response.setHeader('Content-Length', range.end - range.start + 1);
      if (range.status === 206) response.setHeader('Content-Range', `bytes ${range.start}-${range.end}/${info.size}`);
      response.writeHead(range.status);
      if (request.method === 'HEAD' || info.size === 0) { response.end(); return; }
      const stream = handle.createReadStream({ start: range.start, end: range.end });
      handle = null; // The stream owns and closes the descriptor, including client disconnects.
      stream.on('error', error => response.destroy(error));
      response.on('close', () => stream.destroy());
      stream.pipe(response);
    } catch {
      if (!response.headersSent) empty(404);
      else response.destroy();
    } finally {
      if (handle) await handle.close();
    }
  });
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const args = process.argv.slice(2);
  const port = args.length === 0 ? 8765 : args.length === 2 && args[0] === '--port' && /^\d+$/.test(args[1]) ? Number(args[1]) : NaN;
  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    console.error('用法：node scripts/serve-web.mjs [--port 8765]');
    process.exitCode = 1;
  } else {
    const server = createDevServer();
    server.on('error', error => { console.error(`开发服务器启动失败：${error.message}`); process.exitCode = 1; });
    server.listen(port, '127.0.0.1', () => console.log(`DesktopShell 开发服务器：http://127.0.0.1:${port}/`));
  }
}
