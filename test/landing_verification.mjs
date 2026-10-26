import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert';

const htmlPath = path.resolve('landing/index.html');
const jsonPath = path.resolve('landing/release.json');
const cssPath = path.resolve('landing/styles.css');

const html = fs.readFileSync(htmlPath, 'utf8');
const json = JSON.parse(fs.readFileSync(jsonPath, 'utf8'));
const css = fs.readFileSync(cssPath, 'utf8');

console.log('--- Verifying TeloPlay Landing Page Requirements ---');

// 1. Verify forbidden claims are absent
const forbiddenTerms = [
  /lossless/i,
  /audiophile/i,
  /edge-resolved stream URL bypass/i,
  /free forever/i,
  /zero telemetry/i,
  /zero ad tracking/i,
  /true gapless/i
];

for (const term of forbiddenTerms) {
  assert(!term.test(html), `FAIL: Forbidden term "${term}" found in index.html!`);
}
console.log('✔ No false/risky claims found in HTML.');

// 2. Verify required statements
assert(html.includes('Your music, your way. A clean, cross-platform player.'), 'FAIL: Hero headline mismatch!');
assert(html.includes('TeloPlay is an independent open-source project and is not affiliated with, endorsed by, or associated with YouTube or Google LLC.'), 'FAIL: Disclaimer missing!');
assert(html.includes('Windows SmartScreen:'), 'FAIL: SmartScreen note missing!');
assert(html.includes('Install unknown apps'), 'FAIL: Android install note missing!');
console.log('✔ All required disclaimers, notes, and approved copy verified.');

// 3. Verify Links
assert(html.includes('https://teloplay.pages.dev'), 'FAIL: teloplay.pages.dev link missing!');
assert(json.windows.downloadUrl.includes('github.com'), 'FAIL: Windows download not on GitHub!');
assert(json.android.downloadUrl.includes('github.com'), 'FAIL: Android download not on GitHub!');
console.log('✔ Web Player link and GitHub Release links verified.');

// 4. Verify Accessibility & Motion
assert(css.includes('prefers-reduced-motion'), 'FAIL: prefers-reduced-motion missing from CSS!');
assert(css.includes(':focus-visible'), 'FAIL: :focus-visible missing from CSS!');
console.log('✔ Accessibility & reduced motion media queries verified.');

console.log('All verification assertions passed!');
