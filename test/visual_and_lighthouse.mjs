import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { chromium } from 'playwright';

const PORT = 8089;
const LANDING_DIR = path.resolve('landing');

const MIME_TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.png': 'image/png',
  '.svg': 'image/svg+xml'
};

const server = http.createServer((req, res) => {
  let reqPath = req.url === '/' ? '/index.html' : req.url;
  let filePath = path.join(LANDING_DIR, reqPath);

  if (reqPath.startsWith('/assets/')) {
    filePath = path.join(path.resolve('.'), reqPath);
  }

  if (fs.existsSync(filePath) && fs.statSync(filePath).isFile()) {
    const ext = path.extname(filePath);
    res.writeHead(200, { 'Content-Type': MIME_TYPES[ext] || 'application/octet-stream' });
    fs.createReadStream(filePath).pipe(res);
  } else {
    res.writeHead(404);
    res.end('Not found');
  }
});

server.listen(PORT, async () => {
  console.log(`Server running at http://localhost:${PORT}`);
  fs.mkdirSync('docs/screenshots', { recursive: true });

  const browser = await chromium.launch();
  const context = await browser.newContext();

  // 1440px Desktop
  const pageDesktop = await context.newPage();
  await pageDesktop.setViewportSize({ width: 1440, height: 900 });
  await pageDesktop.goto(`http://localhost:${PORT}`);
  await pageDesktop.waitForTimeout(1000);
  await pageDesktop.screenshot({ path: 'docs/screenshots/landing-desktop-1440.png', fullPage: true });
  console.log('✔ Desktop 1440px screenshot captured');

  // 1024px Tablet
  const pageTablet = await context.newPage();
  await pageTablet.setViewportSize({ width: 1024, height: 768 });
  await pageTablet.goto(`http://localhost:${PORT}`);
  await pageTablet.waitForTimeout(500);
  await pageTablet.screenshot({ path: 'docs/screenshots/landing-tablet-1024.png', fullPage: true });
  console.log('✔ Tablet 1024px screenshot captured');

  // 375px Mobile
  const pageMobile = await context.newPage();
  await pageMobile.setViewportSize({ width: 375, height: 812 });
  await pageMobile.goto(`http://localhost:${PORT}`);
  await pageMobile.waitForTimeout(500);
  await pageMobile.screenshot({ path: 'docs/screenshots/landing-mobile-375.png', fullPage: true });
  console.log('✔ Mobile 375px screenshot captured');

  await browser.close();
  server.close();
  console.log('All screenshots done successfully!');
  process.exit(0);
});
