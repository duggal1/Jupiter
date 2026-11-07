// Jupiter landing — sans only, dependency-free, lightweight.

(function () {
  var reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  // --- pixel glyphs (4x4 alphabet, crisp) ---
  var GLYPHS = {
    stone: ["0000", "0110", "0110", "0000"],
    sky: ["0010", "0110", "1111", "0010"],
    green: ["0001", "0011", "1010", "0100"],
    violet: ["1100", "1010", "0101", "0011"],
    rose: ["1001", "0110", "0110", "1001"],
    orange: ["0110", "1001", "1001", "0110"]
  };
  var TONES = {
    stone: "#71717A", sky: "#2563EB", green: "#16A34A",
    violet: "#8B5CF6", rose: "#E11D48", orange: "#F97316"
  };
  document.querySelectorAll(".glyph").forEach(function (el) {
    var tone = el.getAttribute("data-tone") || "stone";
    var rows = GLYPHS[tone] || GLYPHS.stone;
    var color = TONES[tone] || TONES.stone;
    var rects = "";
    for (var y = 0; y < 4; y++) {
      for (var x = 0; x < 4; x++) {
        if (rows[y][x] === "1") rects += '<rect x="' + x + '" y="' + y + '" width="1" height="1" />';
      }
    }
    el.innerHTML = '<svg viewBox="0 0 4 4" fill="' + color + '" shape-rendering="crispEdges">' + rects + "</svg>";
    if (tone === "sky") {
      el.style.animation = reduced ? "" : "pulse 1.6s ease-in-out infinite";
      el.insertAdjacentHTML("beforeend", "<style>@keyframes pulse{0%,100%{opacity:.6}50%{opacity:1}}</style>");
    }
  });

  // --- scroll reveal (IntersectionObserver, staggered) ---
  var items = Array.prototype.slice.call(document.querySelectorAll(".reveal"));
  items.forEach(function (el, i) { el.style.setProperty("--d", (Math.min(i, 6) * 40) + "ms"); });
  if ("IntersectionObserver" in window && !reduced) {
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (entry.isIntersecting) {
          entry.target.classList.add("in");
          io.unobserve(entry.target);
        }
      });
    }, { threshold: 0.15 });
    items.forEach(function (el) { io.observe(el); });
  } else {
    items.forEach(function (el) { el.classList.add("in"); });
  }

  // --- pixel sky field (2D canvas, transform-light, no WebGL needed) ---
  var canvas = document.getElementById("sky");
  var ctx = canvas && canvas.getContext("2d", { alpha: false });
  var cols = 0, rows = 0, cell = 16, scale = 1, raf = 0, prev = 0, t = 0;
  var SKY = ["#0A0A0A", "#0C1322", "#0F1D3A", "#14315F", "#1B4B8A", "#2563EB", "#60A5FA"];

  function resize() {
    if (!canvas) return;
    var r = canvas.getBoundingClientRect();
    scale = Math.min(window.devicePixelRatio || 1, 1.5);
    cell = r.width < 640 ? 12 : 16;
    cols = Math.ceil(r.width / cell);
    rows = Math.ceil(r.height / cell);
    canvas.width = Math.max(1, Math.round(r.width * scale));
    canvas.height = Math.max(1, Math.round(r.height * scale));
    ctx.imageSmoothingEnabled = false;
    paint();
  }

  function paint() {
    if (!ctx || !cols || !rows) return;
    var now = reduced ? 0 : t;
    for (var y = 0; y < rows; y++) {
      for (var x = 0; x < cols; x++) {
        var a = Math.sin(x * 0.16 + y * 0.045 - now * 0.4);
        var b = Math.cos(y * 0.14 - x * 0.065 + now * 0.28);
        var c = Math.sin((x + y * 0.7) * 0.075 + now * 0.15);
        var central = Math.max(0, 1 - Math.hypot(x / cols - 0.5, y / rows - 0.5) * 1.4);
        var level = Math.max(0, Math.min(5.99, (a + b + c * 0.7 + 3) * 1.02 - central * 1.6));
        var lo = Math.floor(level);
        var px = Math.round(x * cell * scale);
        var py = Math.round(y * cell * scale);
        var w = Math.max(1, Math.round(cell * scale));
        ctx.fillStyle = SKY[lo];
        ctx.fillRect(px, py, w, w);
        if (level - lo > 0.5 && lo < 6) {
          ctx.fillStyle = SKY[lo + 1];
          ctx.fillRect(px + Math.floor(w / 2), py + Math.floor(w / 2), w - Math.floor(w / 2), w - Math.floor(w / 2));
        }
      }
    }
  }

  function tick(now) {
    raf = 0;
    if (prev) t += Math.min(48, now - prev) / 1000;
    prev = now;
    paint();
    raf = requestAnimationFrame(tick);
  }

  function play(on) {
    if (!canvas) return;
    if (on && !raf && !reduced) { prev = 0; raf = requestAnimationFrame(tick); }
    if (!on && raf) { cancelAnimationFrame(raf); raf = 0; prev = 0; }
  }

  if (canvas && ctx) {
    if ("ResizeObserver" in window) new ResizeObserver(resize).observe(canvas);
    window.addEventListener("resize", resize);
    resize();
    document.addEventListener("visibilitychange", function () {
      play(document.visibilityState === "visible");
    });
    play(true);
  }

  // --- download button: upgrade to latest DMG ---
  var btn = document.getElementById("downloadBtn");
  var api = "https://api.github.com/repos/duggal1/Jupiter/releases/latest";
  if (btn) {
    btn.addEventListener("click", function () {
      fetch(api, { headers: { Accept: "application/vnd.github+json" } })
        .then(function (r) { return r.json(); })
        .then(function (release) {
          var assets = release.assets || [];
          var asset = assets.filter(function (a) { return /\.dmg$/i.test(a.name); })[0];
          if (asset && asset.browser_download_url) btn.href = asset.browser_download_url;
        })
        .catch(function () { /* keep /releases fallback */ });
    });
  }
})();
