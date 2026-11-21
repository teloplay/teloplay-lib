# TeloPlay Showcase Landing Page — Design Specification

**Date:** 2026-10-26  
**Status:** Approved (Revised)  
**Author:** Antigravity / Claude Code (Pair Programming with User)  
**Project:** TeloPlay (`H:\TeloPlay\teloplay`)

---

## 1. Executive Summary

TeloPlay is an independent, cross-platform music streaming client (Flutter/Dart) designed for a clean listening experience backed by InnerTube / YouTube Music with synchronized lyrics (LRCLIB), local offline storage (Drift SQLite), and dynamic "Midnight Aurora" theming.

This specification defines the architectural and visual design for the official **TeloPlay Web Landing Page**. The page serves as the public gateway for users to:
1. Stream music immediately via the Web Player (`https://teloplay.pages.dev`).
2. Download the native Windows Desktop edition (`.exe`) via GitHub Releases with verified SHA-256 checksums.
3. Download the native Android mobile edition (`.apk`) via GitHub Releases with verified SHA-256 checksums.
4. Discover key architecture highlights, high-quality audio capabilities, and platform-specific native engines.

---

## 2. Brand & Visual Design Tokens

The landing page directly implements the design tokens from TeloPlay's Flutter core design system ([app_colors.dart](lib/core/theme/app_colors.dart) & [app_theme_extension.dart](lib/core/theme/app_theme_extension.dart)):

### 2.1 Color Palette
- **Background (Obsidian Pitch):** `#0A0C10`
- **Surface Elevation 1 (Cards):** `#11141B`
- **Surface Elevation 2 (Raised Panels):** `#181C25`
- **Surface Elevation 3 (Elevated / Modals):** `#212633`
- **Primary Accent (Electric Violet):** `#8B5CF6`
- **Secondary Accent (Vibrant Magenta):** `#EC4899`
- **Tertiary Accent (Neon Cyan):** `#06B6D4`
- **Signature Aurora Gradient:** `linear-gradient(135deg, #8B5CF6 0%, #D946EF 50%, #EC4899 100%)` (Reserved strictly for the primary CTA button and one hero accent line — NOT applied repeatedly across generic cards).
- **Glass Borders:** `rgba(255, 255, 255, 0.08)`
- **Glass Fill:** `rgba(17, 20, 27, 0.65)` with `backdrop-filter: blur(16px)` on desktop; falls back gracefully to solid `#11141B` on mobile/low-power devices.

### 2.2 Typography Scale & Self-Hosting
- **Display Font:** Plus Jakarta Sans & Inter, self-hosted locally in `landing/fonts/` as `.woff2` files for zero external network dependency, with native system sans-serif fallback (`system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif`).
- **Headings:** Tight tracking (`-0.03em`), deliberate weights (700/800).
- **Body Text:** `#94A3B8` (4.9:1 contrast ratio against `#0A0C10`, exceeding WCAG AA 4.5:1 requirement).
- **Primary Text:** `#F2F1F7` (soft white, anti-glare).
- **Tabular Figures:** Used on duration, timestamps, and release statistics for optical stability.

---

## 3. Page Architecture & Component Layout

The landing page is engineered as an ultra-fast, zero-dependency standalone modern web application located at `landing/index.html` (with accompanying `styles.css`, `main.js`, and `release.json`), ready for instant deployment to Cloudflare Pages, GitHub Pages, or static web servers.

### 3.1 Metadata & Head Standards
- **Title:** `TeloPlay — Clean, Cross-Platform Music Streaming`
- **Meta Description:** `An independent cross-platform music streaming client with synchronized lyrics, local cache, and clean playback on Android, Windows, and Web.`
- **Open Graph & Twitter Cards:** Complete `og:title`, `og:description`, `og:image`, `twitter:card`.
- **Theme Color:** `#0A0C10`
- **Favicon:** Embedded high-res SVG / icon link to `../assets/icon.png`.

### 3.2 Dynamic Release Data (`release.json`)
No hardcoded version numbers or file sizes in HTML. All release metrics and download artifacts are driven by `landing/release.json` (with client-side fallback and optional GitHub Releases API enrichment):
- `version`: (e.g. `v2.4.0`)
- `releaseDate`: ISO date string
- `windows`: `{ fileName: "TeloPlay-Setup.exe", downloadUrl: "https://github.com/teloplay/teloplay/releases/download/v2.4.0/TeloPlay-Setup.exe", size: "48.2 MB", sha256: "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" }`
- `android`: `{ fileName: "TeloPlay-arm64-v8a.apk", downloadUrl: "https://github.com/teloplay/teloplay/releases/download/v2.4.0/TeloPlay-arm64-v8a.apk", size: "32.4 MB", sha256: "ca978112ca1bbdcafac231b39a23dc4da786eff8147c4e72b9807785afee48bb" }`
- `web`: `{ url: "https://teloplay.pages.dev" }`

### 3.3 Components Breakdown

1. **Fixed Glass Navigation Bar:**
   - Brand logo and title with subtle hover glow.
   - Quick navigation links: *Features*, *Engines*, *Platforms*, *Downloads*.
   - Primary Header CTA: **"Launch Web Player"** (opens `teloplay.pages.dev`).

2. **Hero Section (The Showcase):**
   - **Pre-title Badge:** Status pill populated dynamically from `release.json`: `"<span id='badge-version'>v2.4</span> Ready • Cross-Platform Music Client"`.
   - **Headline:** *"Your music, your way. A clean, cross-platform player."*
   - **Subtitle:** *"Stream high-quality audio with synchronized real-time lyrics, local caching, and native playback engines built for Android, Windows, and the Web."*
   - **Triple Action CTAs:**
     - 🚀 **Play on Web** (`https://teloplay.pages.dev`) — Primary glowing Aurora gradient button.
     - 🪟 **Download for Windows** — Frosted card button linking to GitHub Releases `.exe`, displaying dynamic size and SHA-256.
     - 🤖 **Download for Android** — Frosted card button linking to GitHub Releases `.apk`, displaying dynamic size and SHA-256.
   - **Platform Install Notes (Below Download Buttons):**
     - Windows Note: *"Windows SmartScreen: Click 'More info' → 'Run anyway' during first-time installation."*
     - Android Note: *"Android Install: Allow 'Install unknown apps' in browser settings if prompted."*
   - **Hero Signature Showcase: Interactive Synchronized-Lyrics Player Demo:**
     - The visual centerpiece of the page—an authentic player frame showing real-time karaoke-style scrolling lyrics synchronized to an audio playback progress simulation.
     - Dynamic album artwork with localized ambient back-glow.
     - Toggleable play/pause, scrubbable progress bar, and active lyric highlighting with smooth line transitions.
     - Audio visualizer with bars animating smoothly, automatically disabled when `prefers-reduced-motion` is active.

3. **Feature Section (Asymmetric Differentiated Grid):**
   - Diverse layout avoiding monotonous identical cards:
   - **Feature Hero Block (Wide): Synchronized Dynamic Lyrics** — Real-time LRC synchronization, karaoke auto-scroll, translation support, sub-second accuracy.
   - **Feature Split Block A: Clean Listening Experience** — Direct playback without third-party ad insertion or commercial interruptions.
   - **Feature Split Block B: Local SQLite Storage & Cache** — Drift SQLite database managing local metadata, offline track caching, and fast queue recovery.
   - **Feature Split Block C: Adaptive Ambient Lighting** — Real-time color extraction from album artwork illuminating the player chrome.

4. **Multi-Platform Native Playback Engines:**
   - **Android Engine:** ExoPlayer via `just_audio`, native foreground playback service, lockscreen art, and notification media controls.
   - **Windows Engine:** LibVLC / MediaKit native C++ decoding, Windows SMTC (System Media Transport Controls) taskbar thumbnail controls, and hardware media keys.
   - **Web Engine:** Web Audio API with service worker caching, streaming directly through Cloudflare Pages edge.

5. **Direct Download Matrix & Security Verification:**
   - Table / cards showing platform, binary format, GitHub Release download button, and copyable SHA-256 checksum strings with a 1-click "Copy Hash" button.

6. **Footer & Plain Disclaimer:**
   - **Independent Client Disclaimer:** *"TeloPlay is an independent open-source project and is not affiliated with, endorsed by, or associated with YouTube or Google LLC."*
   - **Privacy Notice:** *"No third-party ad networks or marketing trackers. Your listening history and preferences are stored locally in your personal SQLite database."*
   - Architecture links, GitHub repository, and license info.

---

## 4. Implementation & Quality Verification Plan

1. **Scaffold Structure:** Place in `landing/` directory:
   - `landing/index.html` (Semantic, accessible HTML5, meta tags, aria-labels, WCAG AA)
   - `landing/styles.css` (Modular CSS, CSS variables, `@media (prefers-reduced-motion)`, mobile blur fallback)
   - `landing/main.js` (Dynamic `release.json` loader, lyrics sync demo engine, SHA-256 copy helpers)
   - `landing/release.json` (Single source of truth for version and download binaries)
   - `landing/fonts/` (Self-hosted woff2 fonts)
2. **Responsive Visual Testing via Playwright MCP:**
   - Desktop Wide: `1440x900`
   - Tablet / Laptop: `1024x768`
   - Mobile Portrait: `375x812` (iPhone/Android standard)
3. **Accessibility & Contrast Verification:**
   - Verify all interactive elements have visible keyboard focus rings (`:focus-visible`).
   - All buttons and links have explicit `aria-label` where icons are used.
   - Text contrast meets or exceeds WCAG AA (minimum 4.5:1).
4. **Lighthouse Audit Target:**
   - Performance: 90+
   - Accessibility: 90+
   - Best Practices: 90+
   - SEO: 90+
5. **Link & Release Verification:**
   - Verify `teloplay.pages.dev` target link.
   - Verify GitHub Releases download paths and fallback functionality.
