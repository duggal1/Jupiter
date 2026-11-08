Rebuilt from scratch. I didn't run any of it, as you asked, so treat it as unverified until you open it.

**The idea:** the grid is your disk. 644 cells at 12.5 MB each is exactly 8.05 GB. Hover a cell to see its category and size. Click a row to select or deselect a category, and the cells fill or drain with the number rolling alongside. The Safe/Okay/Risky section is merged into the legend rows under the grid, since they described the same thing.

**Removed:** the sky canvas, the blur and drop-shadow, the big logo, the feature cards, scroll-reveal, all rounded corners. The background is pure black.

**`index.html`**
```html
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<title>Jupiter — Mac Storage Cleaner</title>
<meta name="description" content="Jupiter finds the junk macOS hides and removes it. Native, 1.3 MB, free forever." />
<link rel="icon" href="favicon.svg" />
<link rel="stylesheet" href="style.css" />
</head>
<body>
  <nav>
    <a class="brand" href="#"><img src="favicon.svg" alt="" /><span>Jupiter</span></a>
    <a href="https://github.com/duggal1/Jupiter">GitHub</a>
  </nav>

  <main>
    <header class="hero">
      <h1>Mac Storage is lying to you.<span>Jupiter shows the truth.</span></h1>
      <p class="lede">Caches, Xcode, node_modules, .build, target, dist. Measured in real allocated bytes. Gone in one clean.</p>
      <div class="cta">
        <a class="download" id="downloadBtn" href="https://github.com/duggal1/Jupiter/releases">
          <img src="assets/apple-white.svg" alt="" />Download for macOS
        </a>
        <p class="meta">Apple Silicon · 1.3 MB · Ad-hoc signed · Free forever<br />First open: Right-click → Open</p>
      </div>
    </header>

    <div class="mapwrap" id="mapwrap">
      <section class="map" id="map" aria-label="Junk on a Mac, by category">
        <div class="readout">
          <div class="total">
            <div class="line"><output class="num" id="num">0.00</output><span class="unit">GB</span></div>
            <p class="of">selected of <b>8.05 GB</b> junk</p>
          </div>
          <div class="hover">
            <div class="hl"><span class="sw" id="sw"></span><span id="hn">Hover the grid</span></div>
            <p id="hs">1 cell = 12.5 MB</p>
          </div>
        </div>
        <div class="grid" id="grid" role="img"></div>
        <div class="rows" id="rows"></div>
      </section>
    </div>

    <section class="features" aria-label="Features">
      <article>
        <span class="px" data-icon="chip"></span>
        <h2>Tiny</h2>
        <p>Native SwiftUI. No Electron. Almost no RAM.</p>
      </article>
      <article>
        <span class="px" data-icon="bolt"></span>
        <h2>Fast</h2>
        <p>Concurrent scan. Cleaning streams live, MB by MB.</p>
      </article>
      <article>
        <span class="px" data-icon="eye"></span>
        <h2>Beautiful</h2>
        <p>Dark, pixel-sharp, 60fps. Reduced motion respected.</p>
      </article>
    </section>
  </main>

  <footer>
    <span>Jupiter · Open source</span>
    <a href="https://github.com/duggal1/Jupiter">github.com/duggal1/Jupiter</a>
  </footer>

  <script src="app.js"></script>
</body>
</html>
```

**`style.css`**
```css
:root {
  --bg: #000;
  --text: #FAFAFA;
  --text2: #A3A3A3;
  --control: #1A1A1A;
  --line: #1F1F1F;
  --accent: #2563EB;
  --accent-hover: #3B82F6;
  --safe: #4ADE80;
  --okay: #60A5FA;
  --risky: #F87171;
  --ease: cubic-bezier(0.23, 1, 0.32, 1);
  --font: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", Arial, sans-serif;
  --mono: ui-monospace, "SF Mono", Menlo, Consolas, monospace;
}

* { box-sizing: border-box; margin: 0; padding: 0; }
html { scroll-behavior: smooth; }
body {
  background: var(--bg);
  color: var(--text);
  font: 14px/1.5 var(--font);
  -webkit-font-smoothing: antialiased;
  overflow-x: hidden;
}
a { color: inherit; }
:focus-visible { outline: 2px solid var(--text); outline-offset: 2px; }

nav, main, footer { max-width: 880px; margin: 0 auto; padding-left: 32px; padding-right: 32px; }

nav { display: flex; justify-content: space-between; align-items: center; height: 64px; }
nav a { color: var(--text2); text-decoration: none; transition: color 0.1s ease-out; }
nav a:hover { color: var(--text); }
.brand { display: inline-flex; align-items: center; gap: 8px; color: var(--text); font-weight: 600; font-size: 16px; }
.brand img { width: 24px; height: 24px; }

main { padding-top: 48px; padding-bottom: 64px; }

/* hero */
h1 {
  font-size: 56px;
  font-style: italic;
  font-weight: 600;
  letter-spacing: -2px;
  line-height: 1;
  text-wrap: balance;
}
h1 span { display: block; color: var(--text2); }
.lede { margin-top: 24px; max-width: 480px; color: var(--text2); font-size: 16px; }

.cta { display: flex; align-items: center; gap: 16px; margin-top: 32px; flex-wrap: wrap; }
.download {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  height: 44px;
  padding: 0 20px;
  background: var(--accent);
  color: #fff;
  font-size: 14px;
  font-weight: 600;
  text-decoration: none;
  transition: background 0.1s ease-out, transform 0.1s ease-out;
}
.download img { width: 16px; height: 16px; }
.download:hover { background: var(--accent-hover); }
.download:active { transform: translateY(2px); }
.meta { font-size: 12px; color: var(--text2); }

/* disk map */
.mapwrap { margin-top: 64px; }
.readout { display: grid; grid-template-columns: 1fr auto; align-items: end; gap: 24px; margin-bottom: 16px; }
.line { display: flex; align-items: baseline; gap: 8px; }
.num {
  font: 500 40px/1 var(--mono);
  letter-spacing: -0.04em;
  font-variant-numeric: tabular-nums;
  min-width: 4ch;
}
.unit { font-size: 16px; font-weight: 500; color: var(--text2); }
.of { margin-top: 8px; font-size: 12px; color: var(--text2); }
.of b { color: var(--text); font-family: var(--mono); font-weight: 500; }

.hover { min-width: 220px; text-align: right; }
.hl { display: flex; align-items: center; justify-content: flex-end; gap: 8px; font-weight: 600; min-height: 21px; }
.hover p { font: 12px/1.5 var(--mono); color: var(--text2); }
.sw { width: 8px; height: 8px; background: var(--control); }

.grid {
  --cell: 12px;
  --gap: 2px;
  display: grid;
  grid-auto-flow: column;
  grid-template-rows: repeat(14, var(--cell));
  grid-template-columns: repeat(46, var(--cell));
  gap: var(--gap);
  width: max-content;
}
.cat { display: contents; }
.grid i {
  display: block;
  background: var(--control);
  transition: background-color 0.16s var(--ease) calc(var(--k) * 1ms), opacity 0.1s ease-out;
}
.cat.on i { background: var(--c); }
.map[data-hot] .cat:not(.hot) i { opacity: 0.25; }
.grid i:hover { position: relative; z-index: 1; box-shadow: 0 0 0 1px var(--text); }

.rows { margin-top: 24px; border-top: 1px solid var(--line); }
.row {
  display: grid;
  grid-template-columns: 16px 168px 1fr auto;
  align-items: center;
  gap: 16px;
  width: 100%;
  padding: 16px 0;
  background: none;
  border: 0;
  border-bottom: 1px solid var(--line);
  color: inherit;
  font: inherit;
  text-align: left;
  cursor: pointer;
}
.row:focus-visible { outline-offset: -2px; }
.chk { width: 16px; height: 16px; background: var(--control); transition: background-color 0.14s var(--ease), transform 0.1s ease-out; }
.row[aria-pressed="true"] .chk { background: var(--c); }
.row:active .chk { transform: scale(0.75); }
.who { display: grid; gap: 2px; }
.who b { font-weight: 600; }
.tag { display: inline-flex; align-items: center; gap: 6px; font-size: 12px; font-weight: 500; }
.tag.safe { color: var(--safe); }
.tag.okay { color: var(--okay); }
.tag.risky { color: var(--risky); }
.why { color: var(--text2); transition: color 0.1s ease-out; }
.row.hot .why { color: var(--text); }
.size { font: 14px var(--mono); font-variant-numeric: tabular-nums; min-width: 8ch; text-align: right; }

/* pixel icons */
.px svg { display: block; }

/* features */
.features { display: grid; grid-template-columns: repeat(3, 1fr); gap: 32px; margin-top: 64px; }
.features h2 { margin: 16px 0 4px; font-size: 16px; font-weight: 600; }
.features p { color: var(--text2); }

footer {
  display: flex;
  justify-content: space-between;
  padding-top: 32px;
  padding-bottom: 48px;
  color: var(--text2);
  font-size: 12px;
}
footer a { text-decoration: none; transition: color 0.1s ease-out; }
footer a:hover { color: var(--text); }

@media (prefers-reduced-motion: reduce) {
  html { scroll-behavior: auto; }
  * { transition: none !important; animation: none !important; }
}

@media (max-width: 640px) {
  nav, main, footer { padding-left: 16px; padding-right: 16px; }
  h1 { font-size: 36px; letter-spacing: -1.2px; }
  .readout { grid-template-columns: 1fr; }
  .hover { text-align: left; }
  .hl { justify-content: flex-start; }
  .row { grid-template-columns: 16px 1fr auto; row-gap: 4px; }
  .why { grid-column: 2 / 4; grid-row: 2; }
  .features { grid-template-columns: 1fr; gap: 24px; }
}
```

**`app.js`** (replaces the old one entirely)
```js
(() => {
  const COLS = 46, ROWS = 14, TOTAL = COLS * ROWS; // 644 cells x 12.5 MB = 8.05 GB
  const CELL_MB = 12.5;
  const reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;

  // Pixel icons: each char is a palette key, '.' is empty
  const ICONS = {
    chip: { c: { 1: '#A3A3A3', 2: '#22D3EE', 3: '#0E7490' }, g: [
      '..1.1.1..',
      '.2222222.',
      '122222221',
      '.2233322.',
      '122333221',
      '.2233322.',
      '122222221',
      '.2222222.',
      '..1.1.1..'] },
    bolt: { c: { 1: '#FEF08A', 2: '#FACC15' }, g: [
      '......12.',
      '.....122.',
      '....122..',
      '...1222..',
      '..122222.',
      '....122..',
      '...122...',
      '..122....',
      '..12.....'] },
    eye: { c: { 1: '#F472B6', 2: '#FAFAFA', 3: '#8B5CF6', 4: '#000000' }, g: [
      '.........',
      '..11111..',
      '.1222221.',
      '122333221',
      '122343221',
      '122333221',
      '.1222221.',
      '..11111..',
      '.........'] },
    shield: { c: { 1: '#4ADE80', 2: '#14532D' }, g: [
      '1111111',
      '1222221',
      '1222221',
      '1222221',
      '.12221.',
      '..121..',
      '...1...'] },
    ring: { c: { 1: '#60A5FA', 2: '#BFDBFE' }, g: [
      '..111..',
      '.1...1.',
      '1.....1',
      '1..2..1',
      '1.....1',
      '.1...1.',
      '..111..'] },
    warn: { c: { 1: '#F87171', 2: '#450A0A' }, g: [
      '...1...',
      '..111..',
      '.11211.',
      '.11211.',
      '1111111',
      '1112111',
      '1111111'] },
  };

  // Demo split: sums to 8.05 GB. Replace with real scan results.
  const CATS = [
    { id: 'caches',  name: 'Caches',      tone: 'safe',  gb: 2.65, color: '#4ADE80', why: 'Regenerates automatically. Loses nothing.' },
    { id: 'xcode',   name: 'Xcode',       tone: 'okay',  gb: 1.74, color: '#60A5FA', why: 'DerivedData. Rebuilds on next build.' },
    { id: 'dev',     name: 'Dev folders', tone: 'okay',  gb: 2.62, color: '#A78BFA', why: 'node_modules, .build, target, dist. Rebuild with npm install / swift build.' },
    { id: 'browser', name: 'Browsers',    tone: 'risky', gb: 1.04, color: '#F87171', why: 'Wipes your whole Chrome profile: history, logins, session. Never auto-selected.' },
  ];
  const LABEL = { safe: 'Safe', okay: 'Okay', risky: 'Risky' };
  const BADGE = { safe: 'shield', okay: 'ring', risky: 'warn' };

  const px = (name, u) => {
    const { g, c } = ICONS[name];
    let r = '';
    g.forEach((row, y) => [...row].forEach((ch, x) => {
      if (ch !== '.') r += `<rect x="${x}" y="${y}" width="1" height="1" fill="${c[ch]}"/>`;
    }));
    return `<svg width="${g[0].length * u}" height="${g.length * u}" viewBox="0 0 ${g[0].length} ${g.length}" shape-rendering="crispEdges" aria-hidden="true">${r}</svg>`;
  };

  const $ = s => document.querySelector(s);
  const wrap = $('#mapwrap'), map = $('#map'), grid = $('#grid'), rowsEl = $('#rows');
  const num = $('#num'), hn = $('#hn'), hs = $('#hs'), sw = $('#sw');

  document.querySelectorAll('.px').forEach(el => { el.innerHTML = px(el.dataset.icon, 4); });

  // cells per category (80 cells per GB)
  let used = 0;
  CATS.forEach((c, i) => {
    c.n = i < CATS.length - 1 ? Math.round(c.gb * 1000 / CELL_MB) : TOTAL - used;
    used += c.n;
  });

  // grid: filled column-major, so categories read as pixel-stepped bands
  grid.innerHTML = CATS.map(c =>
    `<div class="cat" data-id="${c.id}" style="--c:${c.color}">` +
    Array.from({ length: c.n }, (_, j) => `<i style="--k:${j}"></i>`).join('') +
    `</div>`
  ).join('');
  grid.setAttribute('aria-label',
    `Pixel map of 8.05 GB of junk. ${CATS.map(c => `${c.gb.toFixed(2)} GB ${c.name}`).join(', ')}. Each cell is 12.5 MB.`);

  rowsEl.innerHTML = CATS.map(c => `
    <button class="row" type="button" data-id="${c.id}" aria-pressed="false" style="--c:${c.color}">
      <span class="chk"></span>
      <span class="who"><b>${c.name}</b><span class="tag ${c.tone}">${px(BADGE[c.tone], 2)}${LABEL[c.tone]}</span></span>
      <span class="why">${c.why}</span>
      <span class="size">${c.gb.toFixed(2)} GB</span>
    </button>`).join('');

  const catEl = {}, rowEl = {};
  CATS.forEach(c => {
    catEl[c.id] = grid.querySelector(`.cat[data-id="${c.id}"]`);
    rowEl[c.id] = rowsEl.querySelector(`.row[data-id="${c.id}"]`);
  });

  // state: everything except Risky is selected
  const on = new Set(CATS.filter(c => c.tone !== 'risky').map(c => c.id));
  let hot = null;

  // rolling number
  let shown = 0, raf = 0;
  const draw = () => { num.textContent = shown.toFixed(2); };
  function roll(to) {
    cancelAnimationFrame(raf);
    if (reduce) { shown = to; draw(); return; }
    const from = shown, t0 = performance.now(), dur = 320;
    const step = t => {
      const k = Math.min(1, (t - t0) / dur);
      shown = from + (to - from) * (1 - Math.pow(1 - k, 3));
      draw();
      if (k < 1) raf = requestAnimationFrame(step);
    };
    raf = requestAnimationFrame(step);
  }

  function showHover() {
    const c = CATS.find(x => x.id === hot);
    if (!c) {
      hn.textContent = 'Hover the grid';
      hs.textContent = '1 cell = 12.5 MB';
      sw.style.visibility = 'hidden';
      return;
    }
    sw.style.visibility = 'visible';
    sw.style.background = c.color;
    hn.textContent = c.name;
    hs.textContent = `${c.gb.toFixed(2)} GB · ${LABEL[c.tone]} · ${on.has(c.id) ? 'Selected' : 'Not selected'}`;
  }

  function setHot(id) {
    if (id === hot) return;
    hot = id;
    map.toggleAttribute('data-hot', !!id);
    CATS.forEach(c => {
      catEl[c.id].classList.toggle('hot', c.id === id);
      rowEl[c.id].classList.toggle('hot', c.id === id);
    });
    showHover();
  }

  function sync() {
    let gb = 0;
    CATS.forEach(c => {
      const sel = on.has(c.id);
      if (sel) gb += c.gb;
      catEl[c.id].classList.toggle('on', sel);
      rowEl[c.id].setAttribute('aria-pressed', sel);
    });
    roll(gb);
    showHover();
  }

  grid.addEventListener('pointerover', e => {
    const cat = e.target.closest('.cat');
    if (cat) setHot(cat.dataset.id);
  });
  grid.addEventListener('pointerleave', () => setHot(null));

  rowsEl.addEventListener('pointerover', e => {
    const r = e.target.closest('.row');
    setHot(r ? r.dataset.id : null);
  });
  rowsEl.addEventListener('pointerleave', () => setHot(null));
  rowsEl.addEventListener('focusin', e => {
    const r = e.target.closest('.row');
    if (r) setHot(r.dataset.id);
  });
  rowsEl.addEventListener('focusout', () => setHot(null));
  rowsEl.addEventListener('click', e => {
    const r = e.target.closest('.row');
    if (!r) return;
    const id = r.dataset.id;
    on.has(id) ? on.delete(id) : on.add(id);
    sync();
  });

  // snap cells to whole pixels
  function fit() {
    const w = wrap.clientWidth;
    const gap = w < 560 ? 1 : 2;
    const cell = Math.max(3, Math.floor((w - gap * (COLS - 1)) / COLS));
    grid.style.setProperty('--cell', cell + 'px');
    grid.style.setProperty('--gap', gap + 'px');
    map.style.width = (cell * COLS + gap * (COLS - 1)) + 'px';
  }
  fit();
  new ResizeObserver(fit).observe(wrap);

  // intro: cells start empty, then fill
  void grid.offsetWidth;
  sync();
})();
```

Things to know before you open it:

- **The category split is made up.** Your original only had the 8.05 GB total. I invented 2.65 / 1.74 / 2.62 / 1.04 so it sums correctly. Swap the `gb` values in `CATS` for real scan output.
- **The default selection is now 7.01 GB** (Safe + Okay), not the old 4.39 GB, because 4.39 didn't map to any category split.
- **Cells only fill column by column.** Category boundaries land mid-column, which gives the stepped, dithered edge, but a category's cell count is rounded from its GB.
- **The grid is hover-only.** Selecting happens through the rows, so a tap on mobile doesn't toggle things by accident.
- **The icons are drawn from character grids.** I checked every row length by hand, but if one looks off, the grid string in `ICONS` is where to fix it.
