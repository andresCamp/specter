/* Fingerprint mosaic — direct port of the app's implementation
   (tools/editor/src/editor.ts): FNV-1a hash seeds a Mulberry32 PRNG,
   which lays out trim-colored tiles; an idle twinkle shimmers at 24fps
   and pointer movement disturbs nearby tiles with a decaying random fill. */

function fnv1aHash(str) {
  let h = 0x811c9dc5;
  for (let i = 0; i < str.length; i++) {
    h ^= str.charCodeAt(i);
    h = Math.imul(h, 0x01000193);
  }
  return h >>> 0;
}

function mulberry32(seed) {
  return function () {
    seed |= 0;
    seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function parseHexColor(hex) {
  hex = hex.trim().replace("#", "");
  return {
    r: parseInt(hex.substring(0, 2), 16),
    g: parseInt(hex.substring(2, 4), 16),
    b: parseInt(hex.substring(4, 6), 16),
  };
}

const DISTURB_RADIUS_MIN = 30;
const DISTURB_RADIUS_MAX = 72;
const DISTURB_DURATION = 1500;
const TWINKLE_FRAME_INTERVAL = 1000 / 24;

const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");

function isDarkTheme() {
  return document.documentElement.dataset.theme === "dark";
}

function trimColor() {
  const hex = getComputedStyle(document.documentElement)
    .getPropertyValue("--trim-color")
    .trim();
  return parseHexColor(hex || "#e3bd96");
}

export function mountMosaic(canvas, options = {}) {
  let {
    seed = "spectr",
    interactive = false,
    fadeBottom = 24,
    pointerTarget = canvas,
    animateIn = true,
  } = options;

  const ctx = canvas.getContext("2d");
  let tiles = [];
  let params = null;
  let twinkleRunning = false;
  let lastTwinkleFrame = 0;
  let entranceFrame = null;
  const disturbances = new Map();
  let entropyRunning = false;
  let visible = true;

  function buildTiles() {
    const rng = mulberry32(fnv1aHash(seed));
    const dpr = window.devicePixelRatio || 1;
    const w = canvas.clientWidth;
    const h = canvas.clientHeight;
    if (w === 0 || h === 0) return false;

    canvas.width = w * dpr;
    canvas.height = h * dpr;

    const { r, g, b } = trimColor();
    const isDark = isDarkTheme();
    const tileSize = 10;
    const gap = 2;
    const step = tileSize + gap;
    const cols = Math.ceil(w / step);
    const rows = Math.ceil(h / step);
    tiles = [];

    for (let row = 0; row < rows; row++) {
      for (let col = 0; col < cols; col++) {
        const v = rng();
        if (v < 0.35) {
          rng();
          continue;
        }
        let fillStyle;
        if (v < 0.65) {
          const opacity = 0.15 + rng() * 0.35;
          fillStyle = `rgba(${r}, ${g}, ${b}, ${opacity})`;
        } else {
          const opacity = 0.06 + rng() * 0.12;
          fillStyle = isDark
            ? `rgba(255, 255, 255, ${opacity})`
            : `rgba(0, 0, 0, ${opacity})`;
        }
        tiles.push({
          x: col * step,
          y: row * step,
          diag: col + row,
          fillStyle,
          reach: rng(),
        });
      }
    }

    params = { w, h, tileSize, maxDiag: cols + rows - 2 };
    return true;
  }

  function applyBottomFade() {
    if (!fadeBottom) return;
    const { w, h } = params;
    ctx.globalAlpha = 1;
    const grad = ctx.createLinearGradient(0, h - fadeBottom, 0, h);
    grad.addColorStop(0, "rgba(0,0,0,0)");
    grad.addColorStop(1, "rgba(0,0,0,1)");
    ctx.globalCompositeOperation = "destination-out";
    ctx.fillStyle = grad;
    ctx.fillRect(0, h - fadeBottom, w, fadeBottom);
    ctx.globalCompositeOperation = "source-over";
  }

  function renderStatic(progress = 1) {
    const dpr = window.devicePixelRatio || 1;
    const { w, h, tileSize, maxDiag } = params;
    ctx.save();
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, w, h);
    for (const tile of tiles) {
      const tileDelay = tile.diag / maxDiag;
      const tileProgress = Math.max(0, Math.min(1, (progress - tileDelay * 0.6) / 0.4));
      if (tileProgress <= 0) continue;
      ctx.globalAlpha = tileProgress;
      ctx.fillStyle = tile.fillStyle;
      ctx.fillRect(tile.x, tile.y, tileSize, tileSize);
    }
    applyBottomFade();
    ctx.restore();
  }

  function startTwinkle() {
    if (twinkleRunning || reducedMotion.matches) return;
    twinkleRunning = true;
    requestAnimationFrame(twinkleTick);
  }

  function twinkleTick(now) {
    if (!twinkleRunning || !params) {
      twinkleRunning = false;
      return;
    }
    if (!visible) {
      twinkleRunning = false;
      return;
    }
    if (entropyRunning) {
      requestAnimationFrame(twinkleTick);
      return;
    }
    if (now - lastTwinkleFrame < TWINKLE_FRAME_INTERVAL) {
      requestAnimationFrame(twinkleTick);
      return;
    }
    lastTwinkleFrame = now;

    const dpr = window.devicePixelRatio || 1;
    const { w, h, tileSize } = params;
    ctx.save();
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, w, h);
    const t = now * 0.001;
    for (let i = 0; i < tiles.length; i++) {
      const tile = tiles[i];
      const phase = tile.reach * Math.PI * 2 + tile.diag * 0.7;
      const shimmer = Math.sin(t * 0.8 + phase) * 0.03
                    + Math.sin(t * 1.3 + phase * 1.7) * 0.03;
      ctx.globalAlpha = Math.max(0, Math.min(1, 1 + shimmer));
      ctx.fillStyle = tile.fillStyle;
      ctx.fillRect(tile.x, tile.y, tileSize, tileSize);
    }
    applyBottomFade();
    ctx.restore();
    requestAnimationFrame(twinkleTick);
  }

  function randomTileFill() {
    const { r, g, b } = trimColor();
    const isDark = isDarkTheme();
    const v = Math.random();
    if (v < 0.4) {
      const opacity = isDark ? 0.2 + Math.random() * 0.45 : 0.15 + Math.random() * 0.35;
      return `rgba(${r}, ${g}, ${b}, ${opacity})`;
    } else if (v < 0.7) {
      const opacity = isDark ? 0.08 + Math.random() * 0.18 : 0.06 + Math.random() * 0.14;
      return isDark
        ? `rgba(255, 255, 255, ${opacity})`
        : `rgba(0, 0, 0, ${opacity})`;
    }
    return "rgba(0,0,0,0)";
  }

  function disturbNear(x, y) {
    if (!params || reducedMotion.matches) return;
    const now = performance.now();
    const half = params.tileSize / 2;
    for (let i = 0; i < tiles.length; i++) {
      const tile = tiles[i];
      const dx = (tile.x + half) - x;
      const dy = (tile.y + half) - y;
      const threshold = DISTURB_RADIUS_MIN + tile.reach * (DISTURB_RADIUS_MAX - DISTURB_RADIUS_MIN);
      if (dx * dx + dy * dy < threshold * threshold && !disturbances.has(i)) {
        disturbances.set(i, { randomFill: randomTileFill(), startTime: now });
      }
    }
    if (!entropyRunning && disturbances.size > 0) {
      entropyRunning = true;
      requestAnimationFrame(entropyTick);
    }
  }

  function entropyTick(now) {
    if (!params) {
      entropyRunning = false;
      return;
    }
    const dpr = window.devicePixelRatio || 1;
    const { w, h, tileSize } = params;
    ctx.save();
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, w, h);
    for (let i = 0; i < tiles.length; i++) {
      const tile = tiles[i];
      const d = disturbances.get(i);
      ctx.globalAlpha = 1;
      ctx.fillStyle = tile.fillStyle;
      ctx.fillRect(tile.x, tile.y, tileSize, tileSize);
      if (d) {
        const t = Math.min(1, (now - d.startTime) / DISTURB_DURATION);
        if (t >= 1) {
          disturbances.delete(i);
        } else {
          ctx.globalAlpha = 1 - t * t;
          ctx.fillStyle = d.randomFill;
          ctx.fillRect(tile.x, tile.y, tileSize, tileSize);
        }
      }
    }
    applyBottomFade();
    ctx.restore();
    if (disturbances.size > 0) {
      requestAnimationFrame(entropyTick);
    } else {
      entropyRunning = false;
      startTwinkle();
    }
  }

  function draw(animate) {
    if (entranceFrame) {
      cancelAnimationFrame(entranceFrame);
      entranceFrame = null;
    }
    if (!buildTiles()) return;
    if (!animate || reducedMotion.matches) {
      renderStatic(1);
      startTwinkle();
      return;
    }
    const duration = 600;
    const start = performance.now();
    function tick(now) {
      const t = Math.min(1, (now - start) / duration);
      renderStatic(1 - Math.pow(1 - t, 3));
      if (t < 1) {
        entranceFrame = requestAnimationFrame(tick);
      } else {
        entranceFrame = null;
        startTwinkle();
      }
    }
    entranceFrame = requestAnimationFrame(tick);
  }

  if (interactive) {
    pointerTarget.addEventListener("pointermove", (e) => {
      const rect = canvas.getBoundingClientRect();
      disturbNear(e.clientX - rect.left, e.clientY - rect.top);
    }, { passive: true });
  }

  const io = new IntersectionObserver((entries) => {
    for (const entry of entries) {
      visible = entry.isIntersecting;
      if (visible) startTwinkle();
    }
  });
  io.observe(canvas);

  let resizeTimer = null;
  const ro = new ResizeObserver(() => {
    if (resizeTimer) clearTimeout(resizeTimer);
    resizeTimer = setTimeout(() => draw(false), 120);
  });
  ro.observe(canvas);

  const observer = new MutationObserver(() => draw(false));
  observer.observe(document.documentElement, { attributes: true, attributeFilter: ["data-theme"] });

  draw(animateIn);

  return {
    redraw: () => draw(false),
    setSeed: (newSeed) => {
      seed = newSeed;
      disturbances.clear();
      draw(true);
    },
  };
}
