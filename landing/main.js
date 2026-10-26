/**
 * TeloPlay Landing Page Script
 * - Dynamic release metadata hydration with safe fallback
 * - Interactive synchronized lyrics demo player engine
 * - Micro-interactions (copy-to-clipboard SHA-256 toast feedback)
 */

(function () {
  'use strict';

  // --- Configuration & Constants ---
  const DEFAULT_RELEASE = {
    version: 'v2.4.0',
    versionShort: 'v2.4',
    releaseDate: '2026-10-26',
    web: {
      url: 'https://teloplay.pages.dev',
      status: 'Live Edge Deployment'
    },
    windows: {
      fileName: 'TeloPlay-Setup-v2.4.0.exe',
      downloadUrl: 'https://github.com/teloplay/teloplay/releases/download/v2.4.0/TeloPlay-Setup-v2.4.0.exe',
      size: '48.2 MB',
      architecture: 'x64 / x86_64',
      sha256: 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
    },
    android: {
      fileName: 'TeloPlay-arm64-v8a-v2.4.0.apk',
      downloadUrl: 'https://github.com/teloplay/teloplay/releases/download/v2.4.0/TeloPlay-arm64-v8a-v2.4.0.apk',
      size: '32.4 MB',
      architecture: 'ARM64 (v8a)',
      sha256: 'ca978112ca1bbdcafac231b39a23dc4da786eff8147c4e72b9807785afee48bb'
    }
  };

  const LYRICS = [
    { time: 0, text: "I'm tryna put you in the worst mood, ah" },
    { time: 4, text: "P1 cleaner than your church shoes, ah" },
    { time: 8, text: "Milli point two just to hurt you, ah" },
    { time: 12, text: "All red Lamb' just to tease you, ah" },
    { time: 16, text: "None of these toys on lease too, ah" },
    { time: 20, text: "Made your whole year in a week too, yah" }
  ];

  const DURATION = 24; // demo loop duration in seconds

  // --- Helper: format seconds as mm:ss ---
  function formatTime(seconds) {
    const s = Math.max(0, Math.floor(seconds));
    const mins = Math.floor(s / 60);
    const secs = s % 60;
    return (mins < 10 ? '0' : '') + mins + ':' + (secs < 10 ? '0' : '') + secs;
  }

  // --- Step 1: Dynamic Release Data Hydration ---
  async function loadReleaseData() {
    let data = DEFAULT_RELEASE;
    try {
      const response = await fetch('./release.json');
      if (response.ok) {
        const json = await response.json();
        if (json && typeof json === 'object') {
          data = json;
        }
      }
    } catch (_) {
      // Fallback cleanly on network failure, file:// protocol, or parsing error
      data = DEFAULT_RELEASE;
    }

    applyReleaseData(data);
    return data;
  }

  function applyReleaseData(data) {
    if (!data) return;

    // Hero badge
    const heroBadgeVersion = document.getElementById('hero-badge-version');
    if (heroBadgeVersion && data.versionShort) {
      heroBadgeVersion.textContent = data.versionShort;
    }

    // Web player link
    if (data.web && data.web.url) {
      const webPlayerLink = document.getElementById('web-player-link');
      if (webPlayerLink) {
        webPlayerLink.href = data.web.url;
      }
    }

    // Windows release hydration
    if (data.windows) {
      const winDownloadBtn = document.getElementById('win-download-btn');
      if (winDownloadBtn) {
        if (data.windows.downloadUrl) winDownloadBtn.href = data.windows.downloadUrl;
        if (data.windows.size) {
          winDownloadBtn.textContent = 'Download .exe (' + data.windows.size + ')';
          if (typeof winDownloadBtn.setAttribute === 'function') {
            winDownloadBtn.setAttribute('aria-label', 'Download .exe (' + data.windows.size + ')');
          }
        }
      }

      const heroWinBtn = document.getElementById('hero-win-download-btn');
      if (heroWinBtn && data.windows.downloadUrl) {
        heroWinBtn.href = data.windows.downloadUrl;
      }

      const winVersionTag = document.getElementById('win-version-tag');
      if (winVersionTag && data.version) {
        winVersionTag.textContent = data.version;
      }

      const winMetaInfo = document.getElementById('win-meta-info');
      if (winMetaInfo && data.windows.architecture && data.windows.size) {
        winMetaInfo.textContent = data.windows.architecture + ' • ' + data.windows.size;
      }

      const winSha256 = document.getElementById('win-sha256');
      if (winSha256 && data.windows.sha256) {
        winSha256.textContent = data.windows.sha256;
      }

      const winCard = winSha256 ? winSha256.closest('.download-card') : null;
      if (winCard) {
        const copyBtn = winCard.querySelector('.copy-hash-btn');
        if (copyBtn && data.windows.sha256) {
          copyBtn.setAttribute('data-hash', data.windows.sha256);
        }
      }
    }

    // Android release hydration
    if (data.android) {
      const androidDownloadBtn = document.getElementById('android-download-btn');
      if (androidDownloadBtn) {
        if (data.android.downloadUrl) androidDownloadBtn.href = data.android.downloadUrl;
        if (data.android.size) {
          androidDownloadBtn.textContent = 'Download .apk (' + data.android.size + ')';
          if (typeof androidDownloadBtn.setAttribute === 'function') {
            androidDownloadBtn.setAttribute('aria-label', 'Download .apk (' + data.android.size + ')');
          }
        }
      }

      const heroAndroidBtn = document.getElementById('hero-android-download-btn');
      if (heroAndroidBtn && data.android.downloadUrl) {
        heroAndroidBtn.href = data.android.downloadUrl;
      }

      const androidVersionTag = document.getElementById('android-version-tag');
      if (androidVersionTag && data.version) {
        androidVersionTag.textContent = data.version;
      }

      const androidMetaInfo = document.getElementById('android-meta-info');
      if (androidMetaInfo && data.android.architecture && data.android.size) {
        androidMetaInfo.textContent = data.android.architecture + ' • ' + data.android.size;
      }

      const androidSha256 = document.getElementById('android-sha256');
      if (androidSha256 && data.android.sha256) {
        androidSha256.textContent = data.android.sha256;
      }

      const androidCard = androidSha256 ? androidSha256.closest('.download-card') : null;
      if (androidCard) {
        const copyBtn = androidCard.querySelector('.copy-hash-btn');
        if (copyBtn && data.android.sha256) {
          copyBtn.setAttribute('data-hash', data.android.sha256);
        }
      }
    }
  }

  // --- Step 2: Interactive Karaoke Synchronized-Lyrics Engine ---
  function initLyricsDemo() {
    const container = document.getElementById('lyrics-container');
    const timeCurrent = document.getElementById('demo-time-current');
    const timeTotal = document.getElementById('demo-time-total');
    const scrubberBar = document.getElementById('demo-scrubber');
    const progressFill = document.getElementById('demo-progress-fill');
    const playPauseBtn = document.getElementById('demo-btn-play');
    const iconPlay = document.getElementById('demo-icon-play');
    const iconPause = document.getElementById('demo-icon-pause');
    const visualizer = document.getElementById('visualizer');
    const visualizerBars = visualizer ? Array.from(visualizer.querySelectorAll('.visualizer-bar')) : [];

    if (!container || !scrubberBar) return;

    // Safely clear container and render lyric lines
    if (typeof container.replaceChildren === 'function') {
      container.replaceChildren();
    } else {
      while (container.firstChild) {
        container.removeChild(container.firstChild);
      }
    }

    LYRICS.forEach((item, idx) => {
      const lineEl = document.createElement('div');
      lineEl.className = 'lyric-line';
      lineEl.setAttribute('data-index', String(idx));
      lineEl.textContent = item.text;
      lineEl.addEventListener('click', () => {
        seekTo(item.time);
      });
      container.appendChild(lineEl);
    });

    const lyricElements = Array.from(container.querySelectorAll('.lyric-line'));

    // State
    let isPlaying = true;
    let currentTime = 0;
    const duration = DURATION;
    let lastTimestamp = performance.now();
    let activeIndex = -1;
    let animFrameId = null;

    if (timeTotal) {
      timeTotal.textContent = formatTime(duration);
    }

    function prefersReducedMotion() {
      return typeof window !== 'undefined' &&
        typeof window.matchMedia === 'function' &&
        window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    }

    function updateVisualizer(playing) {
      if (!visualizerBars.length) return;
      if (prefersReducedMotion()) {
        // Flatten bars and do not animate when reduced motion is preferred
        visualizerBars.forEach(bar => {
          bar.style.height = '8px';
        });
        return;
      }

      if (!playing) {
        visualizerBars.forEach(bar => {
          bar.style.height = '6px';
        });
        return;
      }

      // Modulated heights when playing
      visualizerBars.forEach((bar, i) => {
        const wave = Math.sin((currentTime * 3) + (i * 0.7)) * 0.5 + 0.5;
        const jitter = Math.random() * 8;
        const height = Math.floor(6 + wave * 20 + jitter);
        bar.style.height = Math.min(32, Math.max(4, height)) + 'px';
      });
    }

    let cachedViewportCenter = 0;
    let cachedActiveCenter = 0;

    function updateLyricsScroll(currIdx) {
      if (currIdx === activeIndex) return;
      activeIndex = currIdx;

      lyricElements.forEach((el, idx) => {
        if (idx === currIdx) {
          el.classList.add('active');
        } else {
          el.classList.remove('active');
        }
      });

      const activeEl = lyricElements[currIdx];
      if (activeEl) {
        const viewport = container.parentElement;
        if (viewport) {
          if (!cachedViewportCenter) {
            cachedViewportCenter = (viewport.clientHeight || 180) / 2;
          }
          const targetY = cachedViewportCenter - (activeEl.offsetTop + (activeEl.clientHeight || 24) / 2);
          container.style.transform = `translateY(${targetY}px)`;
        }
      }
    }

    function render() {
      if (timeCurrent) {
        timeCurrent.textContent = formatTime(currentTime);
      }

      const percent = Math.min(100, Math.max(0, (currentTime / duration) * 100));
      if (progressFill) {
        progressFill.style.width = percent.toFixed(2) + '%';
      }
      if (scrubberBar) {
        scrubberBar.setAttribute('aria-valuenow', Math.round(percent).toString());
      }

      // Determine active lyric line
      let currIdx = 0;
      for (let i = 0; i < LYRICS.length; i++) {
        if (currentTime >= LYRICS[i].time) {
          currIdx = i;
        } else {
          break;
        }
      }
      updateLyricsScroll(currIdx);
    }

    function tick(now) {
      if (!isPlaying) return;

      const delta = (now - lastTimestamp) / 1000;
      currentTime += delta;
      if (currentTime >= duration) {
        currentTime = 0;
      }
      render();
      updateVisualizer(true);

      lastTimestamp = now;
      animFrameId = requestAnimationFrame(tick);
    }

    function setPlayState(play) {
      isPlaying = play;
      if (iconPlay && iconPause) {
        if (isPlaying) {
          iconPlay.style.display = 'none';
          iconPause.style.display = 'block';
          if (playPauseBtn) playPauseBtn.setAttribute('aria-label', 'Pause');
          lastTimestamp = performance.now();
          if (animFrameId) cancelAnimationFrame(animFrameId);
          animFrameId = requestAnimationFrame(tick);
        } else {
          iconPlay.style.display = 'block';
          iconPause.style.display = 'none';
          if (playPauseBtn) playPauseBtn.setAttribute('aria-label', 'Play');
          if (animFrameId) {
            cancelAnimationFrame(animFrameId);
            animFrameId = null;
          }
          updateVisualizer(false);
        }
      }
    }

    function togglePlay() {
      setPlayState(!isPlaying);
    }

    function seekTo(targetSeconds) {
      currentTime = Math.max(0, Math.min(duration, targetSeconds));
      render();
      updateVisualizer(isPlaying);
    }

    function seekFromEvent(e) {
      const rect = scrubberBar.getBoundingClientRect();
      if (rect.width <= 0) return;
      const clientX = e.clientX !== undefined ? e.clientX : (e.touches && e.touches[0] ? e.touches[0].clientX : 0);
      const relativeX = clientX - rect.left;
      const ratio = Math.max(0, Math.min(1, relativeX / rect.width));
      seekTo(ratio * duration);
    }

    // Play / Pause event
    if (playPauseBtn) {
      playPauseBtn.addEventListener('click', togglePlay);
    }

    // Scrubber click & drag events
    let isDragging = false;
    scrubberBar.addEventListener('mousedown', (e) => {
      isDragging = true;
      seekFromEvent(e);
    });

    window.addEventListener('mousemove', (e) => {
      if (isDragging) {
        seekFromEvent(e);
      }
    });

    window.addEventListener('mouseup', () => {
      if (isDragging) {
        isDragging = false;
      }
    });

    // Touch scrubber events
    scrubberBar.addEventListener('touchstart', (e) => {
      if (e.touches && e.touches[0]) {
        isDragging = true;
        seekFromEvent(e.touches[0]);
      }
    }, { passive: true });

    window.addEventListener('touchmove', (e) => {
      if (isDragging && e.touches && e.touches[0]) {
        seekFromEvent(e.touches[0]);
      }
    }, { passive: true });

    window.addEventListener('touchend', () => {
      if (isDragging) {
        isDragging = false;
      }
    });

    // Prev / Next button interactions
    const prevBtn = document.getElementById('demo-btn-prev');
    const nextBtn = document.getElementById('demo-btn-next');

    if (prevBtn) {
      prevBtn.addEventListener('click', () => {
        const prevIdx = Math.max(0, activeIndex - 1);
        seekTo(LYRICS[prevIdx].time);
      });
    }

    if (nextBtn) {
      nextBtn.addEventListener('click', () => {
        const nextIdx = (activeIndex + 1) % LYRICS.length;
        seekTo(LYRICS[nextIdx].time);
      });
    }

    // Initial render and loop kick-off
    render();
    updateVisualizer(isPlaying);
    animFrameId = requestAnimationFrame(tick);
  }

  // --- Step 3: SHA-256 Checksum 1-Click Copy with Toast ---
  function initHashCopy() {
    const copyButtons = document.querySelectorAll('.copy-hash-btn');
    const toast = document.getElementById('copy-toast');
    let toastTimeout = null;

    copyButtons.forEach(btn => {
      btn.addEventListener('click', async () => {
        const hash = btn.getAttribute('data-hash') || '';
        if (!hash) return;

        let copied = false;
        if (typeof navigator !== 'undefined' && navigator.clipboard && navigator.clipboard.writeText) {
          try {
            await navigator.clipboard.writeText(hash);
            copied = true;
          } catch (_) {
            copied = false;
          }
        }

        // Fallback for non-secure / file:// context
        if (!copied && typeof document !== 'undefined') {
          try {
            const textarea = document.createElement('textarea');
            textarea.value = hash;
            textarea.style.position = 'fixed';
            textarea.style.opacity = '0';
            document.body.appendChild(textarea);
            textarea.select();
            document.execCommand('copy');
            document.body.removeChild(textarea);
            copied = true;
          } catch (_) {
            copied = false;
          }
        }

        if (copied) {
          if (btn.classList.contains('copied')) return;
          const originalText = btn.textContent;
          btn.textContent = '✓ Copied';
          btn.classList.add('copied');

          if (toast) {
            toast.textContent = 'Copied to clipboard!';
            toast.classList.add('show');
            if (toastTimeout) clearTimeout(toastTimeout);
            toastTimeout = setTimeout(() => {
              toast.classList.remove('show');
            }, 2000);
          }

          setTimeout(() => {
            btn.textContent = originalText;
            btn.classList.remove('copied');
          }, 2000);
        }
      });
    });
  }

  // --- Bootstrap on DOMContentLoaded ---
  function init() {
    loadReleaseData();
    initLyricsDemo();
    initHashCopy();
  }

  if (typeof document !== 'undefined') {
    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', init);
    } else {
      init();
    }
  }

  // Export internal functions for unit test verification if running in Node test harness
  if (typeof module !== 'undefined' && module.exports) {
    module.exports = {
      DEFAULT_RELEASE,
      LYRICS,
      DURATION,
      formatTime,
      loadReleaseData,
      applyReleaseData,
      initLyricsDemo,
      initHashCopy
    };
  }
})();
