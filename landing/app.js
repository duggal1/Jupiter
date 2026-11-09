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
