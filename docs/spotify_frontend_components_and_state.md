# Spotify Frontend Components, State & Motion Specs (Part 2)

## 1. Global Audio Playback State (Zustand Store Pattern)

Spotify treats audio playback as an immutable global background service completely detached from router view mounts.

```typescript
// types/player.ts
export interface Track {
  id: string;
  title: string;
  artists: { id: string; name: string }[];
  album: { id: string; name: string; coverUrl: string; dominantColor?: string };
  durationMs: number;
  audioUrl: string;
}

export type RepeatMode = 'off' | 'all' | 'one';

export interface PlayerState {
  currentTrack: Track | null;
  isPlaying: boolean;
  progressMs: number;
  volume: number; // 0.0 - 1.0
  isMuted: boolean;
  queue: Track[];
  history: Track[];
  isShuffled: boolean;
  repeatMode: RepeatMode;

  // Actions
  playTrack: (track: Track, contextQueue?: Track[]) => void;
  togglePlay: () => void;
  seekTo: (ms: number) => void;
  nextTrack: () => void;
  prevTrack: () => void;
  setVolume: (val: number) => void;
  toggleShuffle: () => void;
  cycleRepeat: () => void;
}
```

---

## 2. Audio Equalizer Waveform Animation (Tracklist Row)

When a track is actively playing, the track number column (`#`) is replaced by a 4-bar jumping equalizer animation.

```css
/* Animated Equalizer */
.equalizer-indicator {
  display: flex;
  align-items: flex-end;
  gap: 2px;
  width: 14px;
  height: 14px;
}

.equalizer-bar {
  width: 2px;
  background-color: #1ed760;
  border-radius: 1px;
  animation: equalizerBounce 1.2s ease-in-out infinite alternate;
}

.equalizer-bar:nth-child(1) { height: 60%; animation-delay: 0.1s; }
.equalizer-bar:nth-child(2) { height: 100%; animation-delay: 0.3s; }
.equalizer-bar:nth-child(3) { height: 35%; animation-delay: 0.15s; }
.equalizer-bar:nth-child(4) { height: 80%; animation-delay: 0.4s; }

@keyframes equalizerBounce {
  0% { height: 20%; }
  100% { height: 100%; }
}

/* Paused state */
.equalizer-indicator.is-paused .equalizer-bar {
  animation-play-state: paused;
  height: 25% !important;
}
```

---

## 3. Synchronized Lyrics View & Scroll Snapping

Spotify’s lyrics screen features dynamic auto-scroll snapping, text sizing transitions, and opacity highlighting for the active lyric line.

### 3.1 CSS Styling & Animations
```css
.lyrics-container {
  display: flex;
  flex-direction: column;
  padding: 80px 40px;
  gap: 28px;
  background-color: var(--extracted-dominant-color, #242424);
  overflow-y: auto;
  scroll-behavior: smooth;
  scroll-snap-type: y mandatory;
}

.lyric-line {
  font-size: 28px;
  font-weight: 700;
  color: rgba(0, 0, 0, 0.45);
  cursor: pointer;
  scroll-snap-align: center;
  transition: color 0.25s cubic-bezier(0.3, 0, 0, 1),
              transform 0.25s cubic-bezier(0.3, 0, 0, 1),
              filter 0.25s ease;
  user-select: none;
}

/* Active current lyric */
.lyric-line.is-active {
  color: #ffffff;
  transform: scale(1.04);
  filter: drop-shadow(0 2px 8px rgba(0,0,0,0.3));
}

/* Passed lines */
.lyric-line.is-past {
  color: rgba(255, 255, 255, 0.65);
}

.lyric-line:hover {
  color: rgba(255, 255, 255, 0.9);
}
```

### 3.2 Auto-Scroll Sync Logic
```typescript
// Hook or effect: trigger auto-scroll whenever active line index changes
function useLyricsAutoScroll(activeLineIndex: number, lineRefs: React.RefObject<HTMLDivElement>[]) {
  React.useEffect(() => {
    const activeEl = lineRefs[activeLineIndex]?.current;
    if (activeEl) {
      activeEl.scrollIntoView({
        behavior: 'smooth',
        block: 'center',
      });
    }
  }, [activeLineIndex]);
}
```

---

## 4. Responsive Breakpoints & Adaptive Layout

Spotify adapts dynamically from multi-panel Desktop to compact Mobile:

```
[ Desktop: > 1024px ]
Grid: Left Sidebar (resizable) | Main View (fluid) | Right Panel (collapsible) | Bottom Player

[ Tablet: 768px - 1024px ]
Grid: Left Sidebar (collapsed icons only: 72px) | Main View (fluid) | Bottom Player
Right Panel is toggled via floating drawer or modal.

[ Mobile: < 768px ]
Flex: Top Nav Bar | Main View (100% width) | Floating Mini-Player (64px) | Bottom Tab Bar (56px)
Sidebars convert to Fullscreen Overlay Navigation sheets.
```

### Mobile Layout Media Query
```css
@media (max-width: 768px) {
  .spotify-shell {
    display: flex;
    flex-direction: column;
    padding: 0;
    gap: 0;
  }

  .left-sidebar, .right-panel {
    display: none; /* Replaced by bottom nav drawer */
  }

  .main-view {
    flex: 1;
    border-radius: 0;
    padding-bottom: 120px; /* Room for Mini-Player + Bottom Nav */
  }

  .mobile-bottom-nav {
    display: flex;
    position: fixed;
    bottom: 0;
    left: 0;
    right: 0;
    height: 56px;
    background: rgba(18, 18, 18, 0.95);
    backdrop-filter: blur(12px);
    justify-content: space-around;
    align-items: center;
    z-index: 100;
  }

  .mobile-mini-player {
    position: fixed;
    bottom: 60px;
    left: 8px;
    right: 8px;
    height: 56px;
    background-color: #282828;
    border-radius: 8px;
    display: flex;
    align-items: center;
    padding: 8px 12px;
    z-index: 99;
    box-shadow: 0 4px 16px rgba(0, 0, 0, 0.6);
  }
}
```

---

## 5. Context Menus, Popovers & Backdrop Blur

When right-clicking an album, song, or artist:
- **Positioning:** Calculated dynamic coordinate offsets (`clientX`, `clientY`) clamped within the viewport bounding client rect.
- **Glassmorphism / Elevation:**
```css
.context-menu-popover {
  position: fixed;
  z-index: 9999;
  min-width: 200px;
  max-width: 320px;
  background: rgba(40, 40, 40, 0.94);
  backdrop-filter: blur(16px);
  -webkit-backdrop-filter: blur(16px);
  border: 1px solid rgba(255, 255, 255, 0.08);
  border-radius: 6px;
  padding: 4px;
  box-shadow: 0 16px 24px rgba(0, 0, 0, 0.5), 0 6px 12px rgba(0, 0, 0, 0.3);
  animation: contextMenuPop 0.12s cubic-bezier(0, 0, 0.2, 1);
}

@keyframes contextMenuPop {
  from {
    opacity: 0;
    transform: scale(0.96);
  }
  to {
    opacity: 1;
    transform: scale(1);
  }
}

.context-menu-item {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 10px 12px;
  font-size: 13px;
  color: #e5e5e5;
  border-radius: 4px;
  cursor: pointer;
}

.context-menu-item:hover {
  background-color: rgba(255, 255, 255, 0.1);
  color: #ffffff;
}
```

---

## 6. Summary Checklist for TeloPlay Implementation

| Module | Core Logic | Ready Specs |
| :--- | :--- | :--- |
| **Audio Core** | Audio Element/WebAudio API + Zustand store | `types/player.ts` |
| **Row Feedback** | Equalizer bounce animation on playing row | `.equalizer-bar` keyframes |
| **Lyrics Sync** | Timestamp sync + auto scroll-snap to center | `.lyrics-container` CSS & hooks |
| **Adaptive Shell** | Desktop Grid -> Mobile Mini-Player + Bottom Nav | `@media (max-width: 768px)` |
| **Action Overlays** | Clamped Context Menus with blur backdrop | `.context-menu-popover` |
