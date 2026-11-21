# Spotify Frontend Architecture & Design Blueprint (for TeloPlay)

## 1. System Overview & Core Metaphor
Spotify’s Web and Desktop client (Chromium-based CEF) uses a unified Single Page Application (SPA) architecture built on Spotify’s **Encore Design System**. 

The app uses a strict **Docked 3-Column Grid** where the audio player and sidebars are decoupled from route changes:

```
+---------------------------------------------------------------------------------------+
| Top Bar: Navigation (< >), Global Search Input, Profile Menu                          |
+----------------------+----------------------------------------+-----------------------+
| Left Sidebar:        | Main Content (Router Outlet):          | Right Panel           |
| - Primary Nav        | - Dynamic Dominant Color Gradient      | (Contextual):         |
|   (Home, Search)     | - View Container (Scrollable)          | - Now Playing info    |
| - Your Library       | - Sticky Filter/Action Bars            | - Synchronized Lyrics |
|   (Filter chips,     | - Views: Playlist, Album, Artist,      | - Queue list          |
|    pinning, list/grid)  Search, Collection, Home              | - Friend Activity     |
+----------------------+----------------------------------------+-----------------------+
| Persistent Player Bar: Track Details | Media Controls | Connect Devices & Volume      |
+---------------------------------------------------------------------------------------+
```

---

## 2. Design Tokens (Encore Design System)

### 2.1 Color Tokens
| Token | Hex Value | Purpose |
| :--- | :--- | :--- |
| `background-base` | `#121212` | Main page and panel background |
| `background-highlight` | `#1a1a1a` | Secondary panels / hover on transparent items |
| `background-elevated-base` | `#242424` | Cards, popovers, dropdown menus |
| `background-elevated-highlight` | `#2a2a2a` | Card hover state |
| `text-base` | `#FFFFFF` | Headers, active items, track titles |
| `text-subdued` | `#b3b3b3` | Artist names, album names, durations |
| `essential-positive` | `#1ed760` | Spotify primary green (playback, toggles, success) |
| `essential-positive-active` | `#169c46` | Active/Pressed state of green button |
| `border-subtle` | `rgba(255,255,255,0.1)` | Subtle dividers and outlines |

### 2.2 Typography Scale (Circular Spotify)
- **Hero Title:** `clamp(32px, 6vw, 96px)` | Weight `900` | Line-height `1.05`
- **Section Heading:** `24px` | Weight `700` | Line-height `1.2`
- **Card Title / List Primary:** `16px` | Weight `700` | Line-height `1.3`
- **Subtitles & Body:** `14px` | Weight `400` / `500`
- **Metadata / Timestamps:** `11px - 12px` | Weight `400`

---

## 3. Structural Screens & Layout Code

### 3.1 CSS Grid Shell
```css
.spotify-shell {
  display: grid;
  grid-template-areas:
    "top-nav top-nav top-nav"
    "left-sidebar main-view right-panel"
    "player-bar player-bar player-bar";
  grid-template-rows: auto 1fr 90px;
  grid-template-columns: var(--left-width, 280px) 1fr var(--right-width, 320px);
  gap: 8px;
  height: 100vh;
  padding: 8px;
  background-color: #000000;
  box-sizing: border-box;
  overflow: hidden;
}

.panel-card {
  background-color: #121212;
  border-radius: 8px;
  overflow: hidden;
  display: flex;
  flex-direction: column;
}
```

### 3.2 Dynamic Contextual Header Gradient
Spotify extracts the dominant color of the active album/playlist cover using color quantization:
```css
.dynamic-header {
  position: relative;
  background: linear-gradient(
    180deg,
    var(--extracted-accent-color, #535353) 0%,
    rgba(18, 18, 18, 0.7) 70%,
    #121212 100%
  );
  padding: 24px 32px;
  display: flex;
  align-items: flex-end;
  gap: 24px;
  transition: background-color 0.4s ease-out;
}
```

---

## 4. Routing Architecture

Spotify maps standard URI structures (`spotify:playlist:<id>` -> `/playlist/<id>`):

| Route Path | View Component | Behavior |
| :--- | :--- | :--- |
| `/` | `HomeFeed` | Recommended horizontal scrolling trays (Recently Played, Made For You) |
| `/search` | `SearchExplore` | Browse-all genre grid with colorful diagonal cards |
| `/search/:query` | `SearchResults` | Filter pill buttons: All, Songs, Playlists, Artists, Albums |
| `/playlist/:id` | `PlaylistDetail` | Hero header, action bar (Play, Like, More), Virtualized track table |
| `/album/:id` | `AlbumDetail` | Track table with sequential track numbers (#, Title, Duration) |
| `/artist/:id` | `ArtistDetail` | Verified badge, listener count, top 5 songs, releases, about bio |
| `/collection/tracks` | `LikedSongs` | Custom purple gradient hero, in-list search filter |

**Navigation Principles:**
- The persistent Player Bar and Left Navigation Sidebar **never unmount**.
- Views use virtual scrolling for long lists (1,000+ songs) to keep DOM nodes minimal.

---

## 5. Micro-Animations & Motion Design

### 5.1 Card Play Button Elevation (Hover State)
When hovering over an album card, the green play button slides up and fades in:
```css
.card {
  position: relative;
  background: #181818;
  border-radius: 8px;
  padding: 16px;
  transition: background-color 0.3s ease;
}

.card:hover {
  background-color: #282828;
}

.card .play-button {
  position: absolute;
  right: 24px;
  bottom: 24px;
  width: 48px;
  height: 48px;
  border-radius: 50%;
  background: #1ed760;
  display: flex;
  align-items: center;
  justify-content: center;
  box-shadow: 0 8px 16px rgba(0, 0, 0, 0.4);
  
  /* Initial state: Hidden & pushed down */
  opacity: 0;
  transform: translateY(8px);
  transition: transform 0.25s cubic-bezier(0.3, 0, 0, 1), 
              opacity 0.25s cubic-bezier(0.3, 0, 0, 1),
              background-color 0.15s ease;
}

.card:hover .play-button {
  opacity: 1;
  transform: translateY(0);
}

.card .play-button:hover {
  transform: scale(1.06);
  background: #1fdf64;
}

.card .play-button:active {
  transform: scale(0.96);
  background: #169c46;
}
```

### 5.2 Playback Scrubber & Volume Rail
A dual-color track that thickens and turns green on hover:
```css
.scrubber-rail {
  width: 100%;
  height: 4px;
  background: rgba(255, 255, 255, 0.3);
  border-radius: 2px;
  cursor: pointer;
  position: relative;
  transition: height 0.1s ease;
}

.scrubber-rail:hover {
  height: 6px;
}

.scrubber-fill {
  height: 100%;
  background: #ffffff;
  border-radius: 2px;
}

.scrubber-rail:hover .scrubber-fill {
  background: #1ed760;
}

.scrubber-thumb {
  position: absolute;
  top: 50%;
  transform: translate(-50%, -50%);
  width: 12px;
  height: 12px;
  background: #ffffff;
  border-radius: 50%;
  box-shadow: 0 2px 4px rgba(0,0,0,0.5);
  display: none;
}

.scrubber-rail:hover .scrubber-thumb {
  display: block;
}
```

### 5.3 Sticky Sub-header on Scroll
```css
.sticky-table-header {
  position: sticky;
  top: 64px;
  z-index: 20;
  background-color: transparent;
  transition: background-color 0.2s ease, border-bottom 0.2s ease;
}

.sticky-table-header.is-stuck {
  background-color: #181818;
  border-bottom: 1px solid rgba(255, 255, 255, 0.1);
  box-shadow: 0 4px 12px rgba(0, 0, 0, 0.6);
}
```

---

## 6. Recommended TeloPlay Frontend Stack
1. **Layout & Styles:** Tailwind CSS / CSS Modules with standard CSS variables for `--extracted-accent-color`.
2. **Icons:** Lucide-react or SVG equivalents (matches Spotify's rounded geometry).
3. **State Management:** Zustand (store audio controls, current tracks, and queue separate from routing context).
4. **Dominant Color Extraction:** `fast-average-color` or canvas pixel sampling.
