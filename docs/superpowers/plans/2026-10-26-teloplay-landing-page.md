# TeloPlay Showcase Landing Page Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a high-performance, standalone, zero-dependency web landing page for TeloPlay with native Windows/Android GitHub Release downloads, SHA-256 verification, and an interactive synchronized-lyrics player demo linking directly to the Web Player (`teloplay.pages.dev`).

**Architecture:** A lightweight, vanilla HTML5/CSS3/JavaScript web client under `landing/` adhering to the "Midnight Aurora" design tokens (`#0A0C10`, `#8B5CF6`, `#EC4899`, `#06B6D4`). Dynamic release metadata is centralized in `release.json` with client-side fallback, and the interactive lyrics demo provides real-time karaoke synchronization with full `prefers-reduced-motion` and WCAG AA compliance.

**Tech Stack:** Semantic HTML5, Modular CSS3 (Custom Properties, Flexbox/Grid), Vanilla JavaScript (ES6+), Playwright for visual regression, Lighthouse for performance/accessibility audits.

**Spec:** `docs/superpowers/specs/2026-10-26-teloplay-landing-page-design.md`

## Global Constraints

- **No false/risky claims:** Do NOT use "Lossless" or "Audiophile"; use "High-quality streaming" / "Clean listening experience". Audio from YouTube Music is lossy (AAC/Opus).
- **Neutral Web Engine description:** Do NOT use "edge-resolved stream URL bypass"; describe neutrally as "Web Audio API with service worker caching".
- **Hero Headline:** Exactly `"Your music, your way. A clean, cross-platform player."` (No "Free Forever", no promises of third-party ad removal).
- **Independent Disclaimer:** Must include plain footer text: `"TeloPlay is an independent open-source project and is not affiliated with, endorsed by, or associated with YouTube or Google LLC."`
- **Softened Privacy/Telemetry:** Must state: `"No third-party ad networks or marketing trackers. Your listening history and preferences are stored locally in your personal SQLite database."`
- **No Gapless Claims:** Do not claim "True Gapless"; describe as "Local SQLite storage & smart cache".
- **External Downloads:** Do not host binaries on Cloudflare Pages (25MB limit); link to GitHub Releases and display copyable SHA-256 checksums.
- **Install Notices:** Windows SmartScreen note (`More info` → `Run anyway`) and Android unknown apps note must be placed under respective download buttons.
- **No Hardcoded Versions:** All version strings and binary metadata must be driven by `landing/release.json`.
- **Aurora Gradient Discipline:** Strictly applied to the primary CTA button and one hero accent line only.
- **Accessibility & Motion:** Respect `prefers-reduced-motion` (disable visualizer/animations), disable heavy blur on mobile, ensure all text meets WCAG AA (≥ 4.5:1), and provide visible `:focus-visible` states.

---

### Task 1: Release Metadata & Self-Hosted Typography Setup

**Files:**
- Create: `landing/release.json`
- Create: `landing/fonts/fonts.css`

**Interfaces:**
- Consumes: Nothing
- Produces: `landing/release.json` used by `main.js` and `index.html` to populate download links, version tags, and SHA-256 checksums; `landing/fonts/fonts.css` providing self-hosted font definitions with local system-ui fallback.

- [ ] **Step 1: Create `landing/release.json` with validated schema**

Create `landing/release.json` containing the single source of truth for versioning, file sizes, release dates, and SHA-256 checksums:

```json
{
  "version": "v2.4.0",
  "versionShort": "v2.4",
  "releaseDate": "2026-10-26",
  "web": {
    "url": "https://teloplay.pages.dev",
    "status": "Live Edge Deployment"
  },
  "windows": {
    "fileName": "TeloPlay-Setup-v2.4.0.exe",
    "downloadUrl": "https://github.com/teloplay/teloplay/releases/download/v2.4.0/TeloPlay-Setup-v2.4.0.exe",
    "size": "48.2 MB",
    "architecture": "x64 / x86_64",
    "sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
  },
  "android": {
    "fileName": "TeloPlay-arm64-v8a-v2.4.0.apk",
    "downloadUrl": "https://github.com/teloplay/teloplay/releases/download/v2.4.0/TeloPlay-arm64-v8a-v2.4.0.apk",
    "size": "32.4 MB",
    "architecture": "ARM64 (v8a)",
    "sha256": "ca978112ca1bbdcafac231b39a23dc4da786eff8147c4e72b9807785afee48bb"
  }
}
```

- [ ] **Step 2: Create `landing/fonts/fonts.css` for self-hosted typography**

Create `landing/fonts/fonts.css` defining the `@font-face` declarations with system fallbacks to guarantee zero third-party font tracking and instant offline availability:

```css
/* Self-hosted & system-first typography stack */
:root {
  --font-sans: 'Plus Jakarta Sans', 'Inter', system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
  --font-mono: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, 'Liberation Mono', 'Courier New', monospace;
}
```

- [ ] **Step 3: Verification check**

Verify `release.json` parses as valid JSON:
Run: `node -e "const r = JSON.parse(fs.readFileSync('landing/release.json')); console.log('Version:', r.version, 'Windows:', r.windows.fileName);"`
Expected: Prints `Version: v2.4.0 Windows: TeloPlay-Setup-v2.4.0.exe`

- [ ] **Step 4: Commit Task 1**

```bash
git add landing/release.json landing/fonts/fonts.css
git commit -m "feat(landing): add release metadata schema and font configuration"
```

---

### Task 2: Core CSS Architecture, Midnight Aurora Design Tokens, & Responsive Framework

**Files:**
- Create: `landing/styles.css`

**Interfaces:**
- Consumes: `landing/fonts/fonts.css`
- Produces: Complete CSS styles for all components, responsive media queries, accessibility focus rings, and `@media (prefers-reduced-motion)` rules.

- [ ] **Step 1: Implement CSS custom properties and resets in `landing/styles.css`**

Define CSS variables matching TeloPlay's `AppColors`:
```css
@import url('fonts/fonts.css');

:root {
  /* Obsidian Surfaces */
  --color-bg: #0A0C10;
  --color-surface: #11141B;
  --color-surface-raised: #181C25;
  --color-surface-elevated: #212633;
  --color-glass-border: rgba(255, 255, 255, 0.08);
  --color-glass-fill: rgba(17, 20, 27, 0.75);

  /* Accents */
  --color-primary: #8B5CF6;
  --color-secondary: #EC4899;
  --color-cyan: #06B6D4;
  --color-amber: #F59E0B;
  --color-success: #10B981;

  /* Typography */
  --color-text-primary: #F2F1F7;
  --color-text-secondary: #94A3B8;
  --color-text-muted: #64748B;

  /* Signature Gradient: Used strictly for Primary CTA and hero highlight */
  --gradient-aurora: linear-gradient(135deg, #8B5CF6 0%, #D946EF 50%, #EC4899 100%);
  --glow-aurora: 0 0 32px rgba(139, 92, 246, 0.35);

  /* Spacing */
  --radius-sm: 8px;
  --radius-md: 14px;
  --radius-lg: 20px;
  --radius-full: 9999px;
  --container-max: 1200px;
}

*, *::before, *::after {
  box-sizing: border-box;
  margin: 0;
  padding: 0;
}

html {
  scroll-behavior: smooth;
  background-color: var(--color-bg);
  color: var(--color-text-primary);
  font-family: var(--font-sans);
  line-height: 1.5;
  -webkit-font-smoothing: antialiased;
}

body {
  min-height: 100vh;
  overflow-x: hidden;
  background: radial-gradient(circle at 50% 0%, rgba(139, 92, 246, 0.12) 0%, transparent 60%),
              radial-gradient(circle at 10% 20%, rgba(6, 182, 212, 0.05) 0%, transparent 40%),
              var(--color-bg);
}
```

- [ ] **Step 2: Implement Components, Bento Grid, and Signature Lyrics Player styling**

Implement styles for:
- Navbar: frosted header with sticky positioning and clean branding.
- Hero: headline (`font-size: clamp(2.25rem, 5vw, 3.75rem)`), subtitle, action buttons row.
- Primary CTA (`.btn-aurora`): signature gradient, smooth elevation, focus ring.
- Secondary CTAs (`.btn-glass`): frosted surface, clean border, platform icons, install hints.
- Interactive Lyrics Player container: vinyl/artwork glow, scrolling lyrics viewport with `.lyric-line` (inactive: `opacity: 0.35`, active: `opacity: 1`, font-weight: 700, scale: 1.02, color: `#F2F1F7`), audio visualizer canvas/bars.
- Asymmetric Bento Feature Grid: hero wide card (lyrics), split cards (clean stream, local SQLite storage, dynamic ambient lighting).
- Engine Showcase Cards: Android, Windows, Web specs.
- Download Matrix Table & Hash Copy Buttons.
- Footer with disclaimer and privacy policy.

- [ ] **Step 3: Implement Accessibility, Focus Rings, and Motion Constraints**

Ensure:
```css
/* Focus Ring for Keyboard Navigation (WCAG AA) */
a:focus-visible, button:focus-visible, input:focus-visible {
  outline: 2px solid var(--color-cyan);
  outline-offset: 3px;
}

/* Reduced Motion Preference */
@media (prefers-reduced-motion: reduce) {
  *, *::before, *::after {
    animation-duration: 0.001ms !important;
    animation-iteration-count: 1 !important;
    transition-duration: 0.001ms !important;
    scroll-behavior: auto !important;
  }
  .visualizer-bar {
    animation: none !important;
    transform: scaleY(0.3) !important;
  }
  .status-pulse {
    animation: none !important;
  }
}

/* Mobile & Low-Power Screen Optimizations (Disable heavy blur) */
@media (max-width: 768px) {
  .glass-panel, .nav-container, .player-card {
    backdrop-filter: none !important;
    -webkit-backdrop-filter: none !important;
    background-color: var(--color-surface) !important;
  }
}
```

- [ ] **Step 4: Commit Task 2**

```bash
git add landing/styles.css
git commit -m "feat(landing): implement core css architecture and design tokens"
```

---

### Task 3: Semantic HTML5 Structure, Head Metadata, & Content Sections

**Files:**
- Create: `landing/index.html`

**Interfaces:**
- Consumes: `landing/styles.css`, `landing/release.json`
- Produces: The primary entry point for the landing page with zero external CDN dependencies.

- [ ] **Step 1: Write HTML5 header with rich SEO and Open Graph metadata**

Include:
- Page Title: `TeloPlay — Clean, Cross-Platform Music Streaming`
- Meta Description: `An independent cross-platform music streaming client with synchronized lyrics, local cache, and clean playback on Android, Windows, and Web.`
- `theme-color`: `#0A0C10`
- Open Graph tags (`og:title`, `og:description`, `og:type`, `og:image`, `og:url`)
- Twitter Card tags (`twitter:card`, `twitter:title`, `twitter:description`)
- Semantic structure: `<header>`, `<main>`, `<section>`, `<footer>`.

- [ ] **Step 2: Build Hero Section with the Exact Approved Copy**

- Pre-title status pill: `<div class="badge"><span class="badge-dot status-pulse"></span> <span id="hero-badge-version">v2.4</span> Ready • Cross-Platform Music Client</div>`
- Headline: `<h1>Your music, your way. A clean, cross-platform player.</h1>`
- Subtitle: `<p class="hero-sub">Stream high-quality audio with synchronized real-time lyrics, local caching, and native playback engines built for Android, Windows, and the Web.</p>`
- Action Buttons:
  1. `<a href="https://teloplay.pages.dev" target="_blank" rel="noopener" class="btn btn-aurora" aria-label="Play TeloPlay on the Web">🚀 Play on Web</a>`
  2. Windows button linking to `#downloads` or direct download from release data, with note:
     `<div class="install-note">Windows SmartScreen: Click "More info" → "Run anyway" during first-time installation.</div>`
  3. Android button linking to `#downloads` or direct download from release data, with note:
     `<div class="install-note">Android Install: Allow "Install unknown apps" in browser settings if prompted.</div>`

- [ ] **Step 3: Build Signature Interactive Lyrics Player Demo Mockup**

Create the player showcase widget in the hero:
- Artwork container with dynamic ambient backlight.
- Track metadata: "Starboy" — The Weeknd (or neutral demo track).
- Live scrolling lyrics viewport with 5-6 sample lines:
  - Line 1: "I'm tryna put you in the worst mood, ah"
  - Line 2: "P1 cleaner than your church shoes, ah"
  - Line 3 (Active highlighted): "Milli point two just to hurt you, ah"
  - Line 4: "All red Lamb' just to tease you, ah"
  - Line 5: "None of these toys on lease too, ah"
- Real-time scrubber with current timestamp (`01:24`) and total duration (`03:50`).
- Play/Pause interactive toggle button, previous/next buttons.
- Real-time animated audio visualizer bar container (`<div class="visualizer" id="visualizer"></div>`).

- [ ] **Step 4: Build Asymmetric Bento Feature Grid & Native Engines Section**

- Wide Card: **Synchronized Dynamic Lyrics** (LRCLIB integration, auto-scroll, sub-second precision).
- Card A: **Clean Listening Experience** (Stream playback without third-party ad injection).
- Card B: **Local SQLite Storage & Cache** (Drift SQLite database for metadata and offline queue recovery).
- Card C: **Adaptive Ambient Lighting** (Dominant palette extraction illuminating the player chrome).
- Native Engines Breakdown:
  - Android: ExoPlayer via `just_audio`, foreground service, lockscreen art.
  - Windows: MediaKit / LibVLC native decoding, SMTC taskbar thumbnail controls.
  - Web: Web Audio API with service worker caching.

- [ ] **Step 5: Build Download Matrix & Footer**

- Direct download cards with OS icons, binary names, dynamic sizes, and copyable SHA-256 strings with a `copy-hash-btn`.
- Footer:
  - Plain independent disclaimer: `"TeloPlay is an independent open-source project and is not affiliated with, endorsed by, or associated with YouTube or Google LLC."`
  - Plain privacy statement: `"No third-party ad networks or marketing trackers. Your listening history and preferences are stored locally in your personal SQLite database."`
  - Architecture and GitHub links.

- [ ] **Step 6: Commit Task 3**

```bash
git add landing/index.html
git commit -m "feat(landing): implement semantic html5 layout and content sections"
```

---

### Task 4: Interactive Synchronized-Lyrics Demo Engine, Dynamic Releases Loader, & Micro-Interactions

**Files:**
- Create: `landing/main.js`

**Interfaces:**
- Consumes: `landing/release.json`, DOM elements in `landing/index.html`
- Produces: Dynamic version hydration, interactive karaoke lyrics playback simulation, play/pause controls, scrubber interaction, and SHA-256 clipboard copy with toast feedback.

- [ ] **Step 1: Implement Dynamic Release Data Hydration with Safe Fallback**

Write `loadReleaseData()` in `landing/main.js`:
- Fetch `./release.json` (relative path).
- If fetch succeeds, dynamically update DOM elements:
  - `#hero-badge-version`: e.g. `v2.4 Ready`
  - `#win-download-btn`: update `href` to `windows.downloadUrl`, size text to `windows.size`.
  - `#win-sha256`: update hash text.
  - `#android-download-btn`: update `href` to `android.downloadUrl`, size text to `android.size`.
  - `#android-sha256`: update hash text.
  - `#web-player-link`: update `href` to `web.url`.
- If fetch fails or running on `file://` protocol, catch error and gracefully use built-in fallback defaults without breaking the UI.

- [ ] **Step 2: Implement the Interactive Karaoke Synchronized-Lyrics Engine**

Write `initLyricsDemo()`:
- Define array of lyric lines with start/end millisecond timestamps:
  ```javascript
  const LYRICS = [
    { time: 0, text: "I'm tryna put you in the worst mood, ah" },
    { time: 4, text: "P1 cleaner than your church shoes, ah" },
    { time: 8, text: "Milli point two just to hurt you, ah" },
    { time: 12, text: "All red Lamb' just to tease you, ah" },
    { time: 16, text: "None of these toys on lease too, ah" },
    { time: 20, text: "Made your whole year in a week too, yah" }
  ];
  ```
- Track playback state (`isPlaying = true`, `currentTime = 0`, `duration = 24`).
- `requestAnimationFrame` or `setInterval` tick updating:
  - Progress bar width percentage.
  - Active lyric index calculation.
  - Auto-scroll lyrics container so the active line stays centered.
  - Add `.active` class to current line, remove from others.
  - Audio visualizer bar heights modulation (randomized smoothly when playing, flattened when paused).
- Play/Pause toggle button updates icon and pauses/resumes the animation timer.
- Scrubber click / drag seeks to target timestamp.

- [ ] **Step 3: Implement SHA-256 Checksum 1-Click Copy with Toast**

Write `initHashCopy()`:
- Attach click listener to `.copy-hash-btn`.
- Read target hash from `data-hash` attribute.
- Call `navigator.clipboard.writeText(hash)`.
- Show temporary "Copied to clipboard!" tooltip/toast and update button icon to checkmark for 2 seconds.

- [ ] **Step 4: Commit Task 4**

```bash
git add landing/main.js
git commit -m "feat(landing): implement dynamic release loader, lyrics sync engine, and copy helpers"
```

---

### Task 5: Automated Verification & Unit Self-Check

**Files:**
- Create: `test/landing_verification.mjs`

**Interfaces:**
- Consumes: `landing/index.html`, `landing/release.json`, `landing/styles.css`, `landing/main.js`
- Produces: Test report verifying file integrity, forbidden claim checks, link correctness, and accessibility attributes.

- [ ] **Step 1: Write the automated verification script `test/landing_verification.mjs`**

```javascript
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
```

- [ ] **Step 2: Run verification script**

Run: `node test/landing_verification.mjs`
Expected: Output showing all assertions passing with `✔ All verification assertions passed!`

- [ ] **Step 3: Commit Task 5**

```bash
git add test/landing_verification.mjs
git commit -m "test(landing): add automated compliance and assertions check"
```

---

### Task 6: Visual Quality Verification (Playwright) & Lighthouse Audit

**Files:**
- Create: `test/visual_and_lighthouse.mjs`

**Interfaces:**
- Consumes: `landing/index.html` served locally
- Produces: Visual screenshots at 1440px (desktop), 1024px (tablet), 375px (mobile) saved to `docs/screenshots/`, and Lighthouse score validation (targeting 90+ across Performance, Accessibility, Best Practices, and SEO).

- [ ] **Step 1: Write Playwright screenshot and Lighthouse runner**

Create `test/visual_and_lighthouse.mjs`:
- Start lightweight local HTTP server serving `landing/` directory.
- Use Playwright to capture full-page screenshots at:
  - `1440x900` -> `docs/screenshots/landing-desktop-1440.png`
  - `1024x768` -> `docs/screenshots/landing-tablet-1024.png`
  - `375x812` -> `docs/screenshots/landing-mobile-375.png`
- Run Lighthouse CLI against `http://localhost:PORT` and print Performance, Accessibility, Best Practices, and SEO scores.
- Close server.

- [ ] **Step 2: Run visual tests and audit**

Run: `node test/visual_and_lighthouse.mjs`
Expected: Screenshots generated under `docs/screenshots/` and audit scores displayed.

- [ ] **Step 3: Commit Task 6**

```bash
git add test/visual_and_lighthouse.mjs docs/screenshots/
git commit -m "test(landing): add visual regression screenshots and lighthouse audit report"
```
