import { execFileSync } from 'node:child_process';
import fs from 'node:fs';

fs.mkdirSync('docs/screenshots', { recursive: true });

console.log('Capturing Desktop 1440px...');
execFileSync('npx.cmd', ['-y', 'playwright', 'screenshot', '--viewport-size=1440,900', '--full-page', 'http://localhost:8089', 'docs/screenshots/landing-desktop-1440.png']);
console.log('✔ Desktop captured');

console.log('Capturing Tablet 1024px...');
execFileSync('npx.cmd', ['-y', 'playwright', 'screenshot', '--viewport-size=1024,768', '--full-page', 'http://localhost:8089', 'docs/screenshots/landing-tablet-1024.png']);
console.log('✔ Tablet captured');

console.log('Capturing Mobile 375px...');
execFileSync('npx.cmd', ['-y', 'playwright', 'screenshot', '--viewport-size=375,812', '--full-page', 'http://localhost:8089', 'docs/screenshots/landing-mobile-375.png']);
console.log('✔ Mobile captured');

console.log('All screenshots captured successfully in docs/screenshots/');
