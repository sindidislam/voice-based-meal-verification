// Minimal static file server, used only to open the generated HTML
// deliverables in a real browser for a rendering check.
//   node tools/serve.js 8712
// Serves the project root.  No dependencies, no network access needed.
const http = require('http');
const fs = require('fs');
const path = require('path');

const root = process.cwd();
const port = Number(process.argv[2] || 8712);
const TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.csv': 'text/plain; charset=utf-8',
  '.m': 'text/plain; charset=utf-8',
  '.png': 'image/png',
  '.wav': 'audio/wav'
};

http.createServer((req, res) => {
  let rel = decodeURIComponent(req.url.split('?')[0]);
  if (rel === '/') rel = '/MEAL_SYSTEM_PRESENTATION.html';
  const file = path.join(root, rel);
  if (!file.startsWith(root)) { res.writeHead(403).end('forbidden'); return; }
  fs.readFile(file, (err, buf) => {
    if (err) { res.writeHead(404, { 'Content-Type': 'text/plain' }).end('not found: ' + rel); return; }
    res.writeHead(200, { 'Content-Type': TYPES[path.extname(file).toLowerCase()] || 'application/octet-stream' });
    res.end(buf);
  });
}).listen(port, () => console.log('serving ' + root + ' on http://localhost:' + port));
