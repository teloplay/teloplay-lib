import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert';
import { pathToFileURL } from 'node:url';

console.log('--- Running Task 4 Automated Unit & Logic Tests ---');

const mainJsPath = path.resolve('landing/main.js');
const indexHtmlPath = path.resolve('landing/index.html');
const releaseJsonPath = path.resolve('landing/release.json');

// 1. Verify files exist
assert(fs.existsSync(mainJsPath), 'landing/main.js must exist');
assert(fs.existsSync(indexHtmlPath), 'landing/index.html must exist');
assert(fs.existsSync(releaseJsonPath), 'landing/release.json must exist');
console.log('✔ Files exist.');

// 2. Syntax & module load check
const mainCode = fs.readFileSync(mainJsPath, 'utf8');
const mainModuleUrl = pathToFileURL(mainJsPath).href;
const { DEFAULT_RELEASE, LYRICS, DURATION, formatTime } = await import(mainModuleUrl);

assert(typeof formatTime === 'function', 'formatTime should be a function');
assert.strictEqual(formatTime(0), '00:00');
assert.strictEqual(formatTime(4), '00:04');
assert.strictEqual(formatTime(24), '00:24');
assert.strictEqual(formatTime(84), '01:24');
assert.strictEqual(formatTime(230), '03:50');
console.log('✔ formatTime correctly formats timestamps.');

// 3. Verify LYRICS array structure
assert(Array.isArray(LYRICS), 'LYRICS must be an array');
assert.strictEqual(LYRICS.length, 6, 'LYRICS should have 6 lines');
assert.strictEqual(LYRICS[0].time, 0);
assert.strictEqual(LYRICS[1].time, 4);
assert.strictEqual(LYRICS[2].time, 8);
assert.strictEqual(LYRICS[3].time, 12);
assert.strictEqual(LYRICS[4].time, 16);
assert.strictEqual(LYRICS[5].time, 20);
assert(LYRICS[0].text.includes('worst mood'));
console.log('✔ LYRICS data structure and timestamps verified.');

// 4. Verify DURATION
assert.strictEqual(DURATION, 24, 'DURATION should be 24 seconds');
console.log('✔ Playback duration verified.');

// 5. Verify DEFAULT_RELEASE fallback structure
assert(DEFAULT_RELEASE.version, 'Fallback version missing');
assert(DEFAULT_RELEASE.versionShort, 'Fallback versionShort missing');
assert(DEFAULT_RELEASE.windows.downloadUrl, 'Fallback windows downloadUrl missing');
assert(DEFAULT_RELEASE.windows.sha256, 'Fallback windows sha256 missing');
assert(DEFAULT_RELEASE.android.downloadUrl, 'Fallback android downloadUrl missing');
assert(DEFAULT_RELEASE.android.sha256, 'Fallback android sha256 missing');
assert(DEFAULT_RELEASE.web.url, 'Fallback web url missing');
console.log('✔ Safe fallback release metadata structure verified.');

// 6. Verify prefers-reduced-motion check in main.js
assert(mainCode.includes('prefers-reduced-motion: reduce'), 'prefers-reduced-motion check must be present');
assert(mainCode.includes('matchMedia'), 'window.matchMedia must be queried');
console.log('✔ prefers-reduced-motion check verified.');

// 7. Verify index.html connects to main.js and has all target IDs
const indexHtml = fs.readFileSync(indexHtmlPath, 'utf8');
assert(indexHtml.includes('src="main.js"'), 'index.html must load main.js');
assert(indexHtml.includes('id="hero-badge-version"'), 'Missing #hero-badge-version');
assert(indexHtml.includes('id="web-player-link"'), 'Missing #web-player-link');
assert(indexHtml.includes('id="win-download-btn"'), 'Missing #win-download-btn');
assert(indexHtml.includes('id="android-download-btn"'), 'Missing #android-download-btn');
assert(indexHtml.includes('id="win-sha256"'), 'Missing #win-sha256');
assert(indexHtml.includes('id="android-sha256"'), 'Missing #android-sha256');
assert(indexHtml.includes('id="lyrics-container"'), 'Missing #lyrics-container');
assert(indexHtml.includes('id="demo-scrubber"'), 'Missing #demo-scrubber');
assert(indexHtml.includes('id="demo-btn-play"'), 'Missing #demo-btn-play');
assert(indexHtml.includes('id="copy-toast"'), 'Missing #copy-toast');
console.log('✔ index.html elements and script linking verified.');

// 8. Simulated DOM test (using minimal mock DOM environment)
{
  const mockElements = {
    'hero-badge-version': { textContent: '' },
    'web-player-link': { href: '' },
    'win-download-btn': { href: '', textContent: '', attributes: {}, setAttribute(k, v) { this.attributes[k] = v; } },
    'android-download-btn': { href: '', textContent: '', attributes: {}, setAttribute(k, v) { this.attributes[k] = v; } },
    'win-sha256': { textContent: '' },
    'android-sha256': { textContent: '' },
    'win-meta-info': { textContent: '' },
    'android-meta-info': { textContent: '' },
    'win-version-tag': { textContent: '' },
    'android-version-tag': { textContent: '' },
    'hero-win-download-btn': { href: '' },
    'hero-android-download-btn': { href: '' },
  };

  const copyButtons = [
    { attributes: { 'data-hash': '' }, setAttribute(k, v) { this.attributes[k] = v; } },
    { attributes: { 'data-hash': '' }, setAttribute(k, v) { this.attributes[k] = v; } }
  ];

  mockElements['win-sha256'].closest = () => ({
    querySelector: () => copyButtons[0]
  });
  mockElements['android-sha256'].closest = () => ({
    querySelector: () => copyButtons[1]
  });

  const { applyReleaseData } = await import(mainModuleUrl);

  global.document = {
    getElementById(id) {
      return mockElements[id] || null;
    }
  };

  const testData = JSON.parse(fs.readFileSync(releaseJsonPath, 'utf8'));
  applyReleaseData(testData);

  assert.strictEqual(mockElements['hero-badge-version'].textContent, testData.versionShort);
  assert.strictEqual(mockElements['web-player-link'].href, testData.web.url);
  assert.strictEqual(mockElements['win-download-btn'].href, testData.windows.downloadUrl);
  assert(mockElements['win-download-btn'].textContent.includes(testData.windows.size));
  assert.strictEqual(mockElements['android-download-btn'].href, testData.android.downloadUrl);
  assert(mockElements['android-download-btn'].textContent.includes(testData.android.size));
  assert.strictEqual(mockElements['win-sha256'].textContent, testData.windows.sha256);
  assert.strictEqual(mockElements['android-sha256'].textContent, testData.android.sha256);
  assert.strictEqual(copyButtons[0].attributes['data-hash'], testData.windows.sha256);
  assert.strictEqual(copyButtons[1].attributes['data-hash'], testData.android.sha256);
  console.log('✔ applyReleaseData hydrated mock DOM with exact release.json values.');
}

console.log('All Task 4 unit & logic tests passed successfully!');
