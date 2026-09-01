// test_page.mjs — assert the built public page's STRUCTURE, JS-execution safety, and
// de-id/blocklist policy for the portal-lift design (design revision of 2026-08-31): twin pool
// panels (GPU left, CPU right), a segmented [Past 3|6|All months] period bar plus a
// month-only <select> and a resolved-range text (default: trailing 3 complete
// months), and per-pool KPI totals cards recomputed by inline JS. The old zero-JS
// rule is dead; this suite checks the inline script is present, self-contained (no
// external requests / storage / theme machinery), and functionally correct
// (simulated segment clicks / month picks recompute the KPI cards and range text).
//
// Run: module load nodejs/20.12.2 && node scripts/test_page.mjs [index.html]
// Exit 0 = pass, 1 = wrong, 2 = usage.
import { readFileSync, mkdtempSync, mkdirSync, writeFileSync, rmSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { tmpdir } from 'node:os';
import { execFileSync } from 'node:child_process';

const SDIR = dirname(fileURLToPath(import.meta.url));
const path = process.argv[2] || join(SDIR, '..', 'index.html');
let html;
try { html = readFileSync(path, 'utf8'); } catch { console.error('test_page: cannot read ' + path); process.exit(2); }

const dataPath = join(SDIR, '..', 'output', 'cluster_data.json');
let data;
try { data = JSON.parse(readFileSync(dataPath, 'utf8')); }
catch (e) { console.error('test_page: cannot read/parse ' + dataPath + ': ' + e.message); process.exit(2); }

let FAILS = 0;
const ok  = m => console.log('PASS: ' + m);
const bad = m => { console.log('FAIL: ' + m); FAILS++; };
const has = (s, needle, m) => (s.includes(needle) ? ok(m) : bad(m + ' -- missing: ' + JSON.stringify(needle).slice(0, 90)));
const not = (s, needle, m) => (s.includes(needle) ? bad(m + ' -- present: ' + JSON.stringify(needle).slice(0, 90)) : ok(m));

// mirrors the page's own monthLabel()/rangeText() (build_cluster_page.R JS block)
const MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const monthLbl = (m, withYear) => MON[+m.slice(5, 7) - 1] + (withYear ? ' ' + m.slice(0, 4) : '');
const rangeTextJS = (months) => {
  if (!months.length) return '';
  const a = months[0], b = months[months.length - 1];
  if (a === b) return monthLbl(a, true);
  const sameYear = a.slice(0, 4) === b.slice(0, 4);
  return monthLbl(a, !sameYear) + ' – ' + monthLbl(b, true);
};

// ---- 0. exactly one inline <script>; no external requests / storage / theme machinery ----
// (the old zero-JS rule is dead per the 2026-08-31 design revision -- inline JS is now required, but it
// must stay self-contained: no fetch/XHR, no browser storage, no OS-theme detection.)
{
  const scriptCount = (html.match(/<script\b/g) || []).length;
  scriptCount === 1 ? ok('page carries exactly one inline <script>') : bad('found ' + scriptCount + ' <script> tags, want exactly 1');
}
not(html, '<script src=', 'no externally-sourced <script src=> (inline only)');
for (const needle of ['fetch(', 'XMLHttpRequest', 'localStorage', 'document.cookie', 'prefers-color-scheme'])
  not(html, needle, 'no "' + needle + '" anywhere (no external requests / storage / theme machinery)');

// ---- 1. containment, not just order: a stray </div> can close a section early while
// every string check still passes. Tiny stack parser over the static markup (copied
// verbatim from cpu-cds-scc/scripts/test_page.mjs's own containment parser).
const parentOf = (() => {
  const body = html.slice(html.indexOf('<body')).replace(/<script[\s\S]*?<\/script>/g, '');
  const stack = [], parent = {}; const voids = new Set(['br', 'img', 'input', 'meta', 'link', 'hr']);
  for (const m of body.matchAll(/<(\/?)([a-zA-Z0-9]+)([^>]*)>/g)) {
    const [, close, tag, attrs] = m;
    if (close) { for (let i = stack.length - 1; i >= 0; i--) if (stack[i].tag === tag) { stack.length = i; break; } continue; }
    const id = (attrs.match(/\bid="([^"]+)"/) || [])[1], cls = (attrs.match(/\bclass="([^"]+)"/) || [])[1];
    const lab = tag + (id ? '#' + id : '') + (cls ? '.' + cls.replace(/\s+/g, '.') : '');
    parent[lab] = stack.length ? stack[stack.length - 1].lab : '(root)';
    if (!voids.has(tag)) stack.push({ tag, lab });
  }
  return parent;
})();
// note: the parser's label key is "tag#id.class1.class2..." when an element carries
// both -- these wrapper divs carry an id (for the JS/test hooks) AND a class (for
// per-pool CSS), so the lookup key must include both, in source attribute order.
const P = sel => parentOf[sel] || '(absent)';
P('div.deckrow') === 'main' ? ok('a deckrow is a direct child of main') : bad('deckrow parent is ' + P('div.deckrow'));
P('div#gpupanel.deck.pool.pool-gpu') === 'div.deckrow' ? ok('GPU panel sits inside a deckrow') : bad('GPU panel parent is ' + P('div#gpupanel.deck.pool.pool-gpu'));
P('div#cpupanel.deck.pool.pool-cpu') === 'div.deckrow' ? ok('CPU panel sits inside a deckrow') : bad('CPU panel parent is ' + P('div#cpupanel.deck.pool.pool-cpu'));
P('div#sechead.sechead') === 'main' ? ok('the section-header period control is a direct child of main') : bad('section-header parent is ' + P('div#sechead.sechead'));
P('div#gpucard.deck') === 'div.deckrow' ? ok('GPU totals card sits inside a deckrow') : bad('GPU totals card parent is ' + P('div#gpucard.deck'));
P('div#cpucard.deck') === 'div.deckrow' ? ok('CPU totals card sits inside a deckrow') : bad('CPU totals card parent is ' + P('div#cpucard.deck'));

(html.indexOf('id="gpupanel"') >= 0 && html.indexOf('id="gpupanel"') < html.indexOf('id="cpupanel"'))
  ? ok('GPU panel renders before the CPU panel (GPU left, CPU right)')
  : bad('GPU panel does not precede the CPU panel in source order');
(html.indexOf('id="gpucard"') >= 0 && html.indexOf('id="gpucard"') < html.indexOf('id="cpucard"'))
  ? ok('GPU totals card renders before the CPU totals card (GPU left, CPU right)')
  : bad('GPU totals card does not precede the CPU totals card in source order');

{
  const main = html.slice(html.indexOf('<main>'), html.indexOf('</main>'));
  const opens = (main.match(/<div\b/g) || []).length, closes = (main.match(/<\/div>/g) || []).length;
  opens === closes ? ok('div tags balance inside main (' + opens + ')') : bad('div tags unbalanced inside main: ' + opens + ' open vs ' + closes + ' close');
}

// ---- 2. header lockup (unchanged) ----
const head1 = (html.match(/<h1>([\s\S]*?)<\/h1>/) || ['', ''])[1];
has(head1, 'class="buplate"', 'h1 carries the University plate image');
has(head1, 'Faculty of Computing &amp; Data Sciences', 'h1 carries the school name');

// ---- 3. every panel block renders fully saturated: capacity, not occupancy ----
{
  const totalBlocks = (html.match(/<i\b[^>]*><\/i>/g) || []).length;
  const onBlocks = (html.match(/<i class="on"><\/i>/g) || []).length;
  totalBlocks > 0 && totalBlocks === onBlocks
    ? ok('every panel block is saturated (' + onBlocks + '/' + totalBlocks + ')')
    : bad('panel blocks not fully saturated: ' + onBlocks + ' of ' + totalBlocks + ' carry class="on"');
}

// ---- 4. no LIVE/STALE machinery (this is capacity, not a live occupancy feed) ----
for (const needle of ['livebadge', 'stalebadge', 'livedot', 'LIVE</span>', '>STALE<'])
  not(html, needle, 'no "' + needle + '" (capacity panels carry no live/stale badge)');
// the footer's stamp wording moves monthly -> quarterly per the 2026-08-31 design revision
// (cadence: quarterly); deploy.sh's stamp grep is updated to match -- must
// still be present, not forbidden.
has(html, 'updated quarterly', 'footer keeps the "updated quarterly" stamp deploy.sh checks for');

// ---- 5. period controls: a "Totals" section header carrying the range text
// (.ttl) plus the segmented [Past 3|6|All] bar + month select (.ctl) ----
const secheadStart = html.indexOf('id="sechead"');
const secheadEnd = secheadStart >= 0 ? html.indexOf('<div class="deckrow">', secheadStart) : -1;
const secheadBlock = secheadStart >= 0 && secheadEnd >= 0 ? html.slice(secheadStart, secheadEnd) : '';
const ttlBlock = (secheadBlock.match(/class="ttl">([\s\S]*?)<\/div>/) || ['', ''])[1];
const ctlBlock = secheadBlock.slice(secheadBlock.indexOf('class="ctl"'));
secheadBlock ? ok('the "Totals" section header (#sechead) was located') : bad('could not locate #sechead');
has(ttlBlock, 'Totals', '.ttl carries the "Totals" heading');
has(ttlBlock, 'id="prange"', '.ttl carries the #prange range-text element');
has(ctlBlock, 'class="seg"', '.ctl carries the segmented period bar (.seg)');
for (const lbl of ['Past 3 months', 'Past 6 months', 'All months'])
  has(ctlBlock, '>' + lbl + '<', '.ctl segmented bar offers "' + lbl + '"');
/<button id="seg-p3" class="on"[^>]*>Past 3 months<\/button>/.test(ctlBlock)
  ? ok('segmented bar defaults to "Past 3 months" active (class="on")')
  : bad('segmented bar default "on" button is not Past 3 months');
has(ctlBlock, '<select id="pmonth"', '.ctl carries the month-only <select>');
has(ctlBlock, 'aria-label="Month"', 'the month select carries an accessible name (aria-label="Month")');
has(ctlBlock, '<option value="" selected>Month', 'month select defaults to the neutral "Month…" placeholder');
for (const m of [...new Set([...data.meta.months_cpu.slice(-2), ...data.meta.months_gpu.slice(-2)])])
  has(ctlBlock, '<option value="' + m + '"', 'month select lists month ' + m);
{
  const expected = rangeTextJS(data.meta.window3);
  const got = (ttlBlock.match(/id="prange">([^<]*)</) || ['', '(absent)'])[1];
  got === expected
    ? ok('range text matches window3 initially ("' + expected + '", no leading separator)')
    : bad('range text is "' + got + '", expected "' + expected + '" (window3)');
}

// ---- 6. two KPI totals cards, positive/neutral tile set (no negative-
// connotation counterparts), GPU left / CPU right ----
const sliceFrom = (startMarker, endMarkers) => {
  const s = html.indexOf(startMarker);
  if (s < 0) return '';
  const ends = endMarkers.map(e => html.indexOf(e)).filter(i => i > s);
  const e = ends.length ? Math.min(...ends) : html.indexOf('</main>');
  return html.slice(s, e);
};
const gpuCard = sliceFrom('id="gpucard"', ['id="cpucard"']);
const cpuCard = sliceFrom('id="cpucard"', ['</main>']);
gpuCard && cpuCard ? ok('both KPI totals cards were located in the page') : bad('could not locate both KPI totals cards');
has(gpuCard, 'GPU Totals', 'GPU card carries its "GPU Totals" heading');
has(cpuCard, 'CPU Totals', 'CPU card carries its "CPU Totals" heading');
for (const lbl of ['Reserved core-h', 'Utilized core-h', 'Avg efficiency', 'Jobs run', 'Core-h per job'])
  has(cpuCard, lbl, 'CPU totals card shows the "' + lbl + '" tile');
for (const lbl of ['Reserved GPU-h', 'Utilized GPU-h', 'Avg utilization', 'Jobs run', 'Energy used (kWh)', 'Mean VRAM in use'])
  has(gpuCard, lbl, 'GPU totals card shows the "' + lbl + '" tile');

// negative assertion: none of the removed tile labels or banned tooltip
// phrases may appear anywhere on the page
for (const lbl of ['Under-Utilized', 'Under-utilized', 'Non-Utilized', 'on hard-failed jobs', 'on wall-killed jobs', 'Walltime Accuracy'])
  not(html, lbl, 'removed tile label "' + lbl + '" no longer appears anywhere');
for (const phrase of ['lower is better', 'Lower is better', 'worst waste', 'broke', 'killed'])
  not(html, phrase, 'banned tooltip phrase "' + phrase + '" does not appear anywhere');

// ---- 6b. the server-rendered DEFAULT window figures are actually correct, not just present --
const fmt = n => Math.round(n).toLocaleString('en-US');
const fmth = x => { if (x == null) return '—'; if (x <= 0) return '0'; if (x < 1) return '&lt;1'; return Math.round(x).toLocaleString('en-US'); };
const CPU_FIELDS = ['held', 'utilized', 'fail_h', 'wkill_h', 'njobs', 'wa_used_h', 'wa_req_h'];
const GPU_FIELDS = ['held', 'real', 'residle_h', 'kwh', 'vram_h', 'fail_h', 'wkill_h', 'njobs'];
const sumWindow = (rows, months, fields) => {
  const set = new Set(months);
  const T = Object.fromEntries(fields.map(f => [f, 0]));
  for (const r of rows) if (set.has(r[0])) fields.forEach((f, i) => { T[f] += r[2 + i]; });
  return T;
};
const wCpu = sumWindow(data.cpu_monthly, data.meta.window3, CPU_FIELDS);
const wGpu = sumWindow(data.gpu_monthly, data.meta.window3, GPU_FIELDS);
has(cpuCard, fmth(wCpu.held), 'CPU totals: Reserved core-h matches the recomputed window3 total');
has(cpuCard, fmth(wCpu.utilized), 'CPU totals: Utilized core-h matches the recomputed window3 total');
has(cpuCard, (wCpu.held ? Math.round(100 * wCpu.utilized / wCpu.held) : 0) + '%', 'CPU totals: Avg efficiency matches recomputed window3');
has(cpuCard, fmt(wCpu.njobs), 'CPU totals: Jobs run matches the recomputed window3 total');
has(cpuCard, wCpu.njobs > 0 ? fmt(wCpu.held / wCpu.njobs) : '—', 'CPU totals: Core-h per job matches the recomputed window3 value');
has(gpuCard, fmth(wGpu.held), 'GPU totals: Reserved GPU-h matches the recomputed window3 total');
has(gpuCard, fmth(wGpu.real), 'GPU totals: Utilized GPU-h matches the recomputed window3 total');
has(gpuCard, (wGpu.held ? Math.round(100 * wGpu.real / wGpu.held) : 0) + '%', 'GPU totals: Avg utilization matches recomputed window3');
has(gpuCard, fmt(wGpu.njobs), 'GPU totals: Jobs run matches the recomputed window3 total');
has(gpuCard, fmth(wGpu.kwh), 'GPU totals: Energy used (kWh) matches the recomputed window3 total');
has(gpuCard, (wGpu.held ? Math.round(100 * wGpu.vram_h / wGpu.held) : 0) + '%', 'GPU totals: Mean VRAM in use matches recomputed window3');

// ---- 6c. R5.1 community tiles (Researchers served / Research groups / Capacity
// reserved) lead each totals card, in that order, followed by the existing R3
// tiles unchanged (GPU 9 tiles total, CPU 8) -- tooltips verbatim, values equal
// to `community` P3 rows and Σheld/Σcap_h over window3, rounded like every
// other percent tile ----
const communityFor = (key, pool) => {
  const r = data.community.find((row) => row[0] === key && row[1] === pool);
  return r ? { users: r[2], groups: r[3] } : { users: 0, groups: 0 };
};
const capSumFor = (months, pool) => {
  const set = new Set(months);
  let s = 0;
  for (const r of data.capacity_monthly) if (r[1] === pool && set.has(r[0])) s += r[2];
  return s;
};
const pctOf = (num, den) => (den ? Math.round((100 * num) / den) : 0) + '%';
const COMMUNITY_TIPS = {
  users: 'Distinct researchers who ran at least one job in the period.',
  groups: 'Distinct research groups with at least one job in the period.',
  cap: "Share of the pool's nominal capacity-hours reserved by jobs. Reserved is not the same as busy — see Avg utilization.",
};
{
  const orderCheck = (block, labels, label) => {
    let last = -1, inOrder = true;
    for (const l of labels) {
      const idx = block.indexOf('>' + l + '<');
      if (idx < 0 || idx < last) { inOrder = false; break; }
      last = idx;
    }
    inOrder ? ok(label + ' tiles appear in the R5.1 order (Researchers served, Research groups, Capacity reserved, then the existing tiles)')
            : bad(label + ' tiles are missing or out of the expected R5.1 order');
  };
  const GPU_TILE_ORDER = ['Researchers served', 'Research groups', 'Capacity reserved', 'Reserved GPU-h', 'Utilized GPU-h', 'Avg utilization', 'Jobs run', 'Energy used (kWh)', 'Mean VRAM in use'];
  const CPU_TILE_ORDER = ['Researchers served', 'Research groups', 'Capacity reserved', 'Reserved core-h', 'Utilized core-h', 'Avg efficiency', 'Jobs run', 'Core-h per job'];
  orderCheck(gpuCard, GPU_TILE_ORDER, 'GPU totals card');
  orderCheck(cpuCard, CPU_TILE_ORDER, 'CPU totals card');

  const gpuTileCount = (gpuCard.match(/class="?kl"?>/g) || []).length;
  gpuTileCount === 9 ? ok('GPU totals card renders exactly 9 tiles') : bad('GPU totals card renders ' + gpuTileCount + ' tiles, want 9');
  const cpuTileCount = (cpuCard.match(/class="?kl"?>/g) || []).length;
  cpuTileCount === 8 ? ok('CPU totals card renders exactly 8 tiles') : bad('CPU totals card renders ' + cpuTileCount + ' tiles, want 8');

  for (const [key, tip] of Object.entries(COMMUNITY_TIPS)) {
    has(gpuCard, 'data-tip="' + tip + '"', 'GPU card carries the verbatim R5.1 tooltip for ' + key);
    has(cpuCard, 'data-tip="' + tip + '"', 'CPU card carries the verbatim R5.1 tooltip for ' + key);
  }
}
{
  const cpuCmtyDefault = communityFor('P3', 'cpu');
  const gpuCmtyDefault = communityFor('P3', 'gpu');
  const cpuCapDefault = pctOf(wCpu.held, capSumFor(data.meta.window3, 'cpu'));
  const gpuCapDefault = pctOf(wGpu.held, capSumFor(data.meta.window3, 'gpu'));
  has(cpuCard, fmt(cpuCmtyDefault.users), 'CPU totals: Researchers served matches recomputed community P3');
  has(cpuCard, fmt(cpuCmtyDefault.groups), 'CPU totals: Research groups matches recomputed community P3');
  has(cpuCard, cpuCapDefault, 'CPU totals: Capacity reserved matches recomputed window3 Σheld/Σcap_h');
  has(gpuCard, fmt(gpuCmtyDefault.users), 'GPU totals: Researchers served matches recomputed community P3');
  has(gpuCard, fmt(gpuCmtyDefault.groups), 'GPU totals: Research groups matches recomputed community P3');
  has(gpuCard, gpuCapDefault, 'GPU totals: Capacity reserved matches recomputed window3 Σheld/Σcap_h');
}

// ---- 7. functional: execute the page's inline JS and simulate period-control
// interactions, verifying the KPI cards AND the range text recompute correctly ----
{
  const scripts = [...html.matchAll(/<script\b[^>]*>([\s\S]*?)<\/script>/g)].map(m => m[1]).join('\n;\n');
  const handlers = { 'seg-p3': [], 'seg-p6': [], 'seg-all': [], pmonth: [] };
  const makeEl = (id, extra = {}) => ({
    id, value: '', innerHTML: '', textContent: '', dataset: {}, style: {},
    addEventListener(ev, fn) {
      if (id in handlers && ((id === 'pmonth' && ev === 'change') || (id !== 'pmonth' && ev === 'click'))) handlers[id].push(fn);
    },
    appendChild() {}, setAttribute() {},
    classList: { add() {}, remove() {}, toggle() {}, contains: () => false },
    querySelectorAll: () => [], closest: () => null,
    ...extra,
  });
  const els = {
    '#seg-p3': makeEl('seg-p3', { dataset: { w: 'past3' } }),
    '#seg-p6': makeEl('seg-p6', { dataset: { w: 'past6' } }),
    '#seg-all': makeEl('seg-all', { dataset: { w: 'all' } }),
    '#pmonth': makeEl('pmonth'),
    '#kpi-cpu': makeEl('kpi-cpu'),
    '#kpi-gpu': makeEl('kpi-gpu'),
    '#prange': makeEl('prange'),
    '#gpu-cov': makeEl('gpu-cov'),
    '#cpu-cov': makeEl('cpu-cov'),
  };
  const document = {
    querySelector: (sel) => els[sel] || makeEl(sel.replace(/^[.#]/, '')),
    querySelectorAll: () => [],
    getElementById: (id) => els['#' + id] || makeEl(id),
    createElement: () => makeEl('tip'),
    addEventListener: () => {},
    body: { appendChild() {} },
  };
  const window = { addEventListener: () => {}, matchMedia: () => ({ matches: false, addEventListener() {} }) };
  const localStorage = { getItem: () => null, setItem() {} };
  try {
    if (!scripts.trim()) throw new Error('no <script> content found');
    new Function('document', 'window', 'localStorage', scripts)(document, window, localStorage);

    // click "Past 3 months" (the default) explicitly: the JS recompute must
    // match the server-rendered default exactly, tile for tile (all 11 tiles)
    if (handlers['seg-p3'].length) handlers['seg-p3'].forEach(fn => fn({ target: els['#seg-p3'] }));
    else bad('functional: the "Past 3 months" segment click handler was never registered');
    const wCpuDefault = sumWindow(data.cpu_monthly, data.meta.window3, CPU_FIELDS);
    const wGpuDefault = sumWindow(data.gpu_monthly, data.meta.window3, GPU_FIELDS);
    const cpuDefaultTiles = [
      [fmth(wCpuDefault.held), 'Reserved core-h'],
      [fmth(wCpuDefault.utilized), 'Utilized core-h'],
      [(wCpuDefault.held ? Math.round(100 * wCpuDefault.utilized / wCpuDefault.held) : 0) + '%', 'Avg efficiency'],
      [fmt(wCpuDefault.njobs), 'Jobs run'],
      [wCpuDefault.njobs > 0 ? fmt(wCpuDefault.held / wCpuDefault.njobs) : '—', 'Core-h per job'],
    ];
    for (const [val, label] of cpuDefaultTiles)
      has(els['#kpi-cpu'].innerHTML, val, 'functional: JS recompute for the default window matches the CPU "' + label + '" tile (' + val + ')');
    const gpuDefaultTiles = [
      [fmth(wGpuDefault.held), 'Reserved GPU-h'],
      [fmth(wGpuDefault.real), 'Utilized GPU-h'],
      [(wGpuDefault.held ? Math.round(100 * wGpuDefault.real / wGpuDefault.held) : 0) + '%', 'Avg utilization'],
      [fmt(wGpuDefault.njobs), 'Jobs run'],
      [fmth(wGpuDefault.kwh), 'Energy used (kWh)'],
      [(wGpuDefault.held ? Math.round(100 * wGpuDefault.vram_h / wGpuDefault.held) : 0) + '%', 'Mean VRAM in use'],
    ];
    for (const [val, label] of gpuDefaultTiles)
      has(els['#kpi-gpu'].innerHTML, val, 'functional: JS recompute for the default window matches the GPU "' + label + '" tile (' + val + ')');

    // click "Past 6 months": the R5.1 tiles must recompute via a community "P6"
    // lookup and a capacity_monthly sum over P6's months (not just re-sum window3)
    if (handlers['seg-p6'].length) handlers['seg-p6'].forEach(fn => fn({ target: els['#seg-p6'] }));
    else bad('functional: the "Past 6 months" segment click handler was never registered');
    {
      const allUnionP6 = [...new Set([...data.meta.months_cpu, ...data.meta.months_gpu])].sort();
      const p6Months = allUnionP6.slice(-6);
      const wCpuP6 = sumWindow(data.cpu_monthly, p6Months, CPU_FIELDS);
      const wGpuP6 = sumWindow(data.gpu_monthly, p6Months, GPU_FIELDS);
      const cpuCmtyP6 = communityFor('P6', 'cpu');
      const gpuCmtyP6 = communityFor('P6', 'gpu');
      const cpuCapP6 = pctOf(wCpuP6.held, capSumFor(p6Months, 'cpu'));
      const gpuCapP6 = pctOf(wGpuP6.held, capSumFor(p6Months, 'gpu'));
      has(els['#kpi-cpu'].innerHTML, fmt(cpuCmtyP6.users), 'functional: "Past 6 months" recomputes CPU Researchers served via the community "P6" lookup');
      has(els['#kpi-cpu'].innerHTML, fmt(cpuCmtyP6.groups), 'functional: "Past 6 months" recomputes CPU Research groups via the community "P6" lookup');
      has(els['#kpi-cpu'].innerHTML, cpuCapP6, 'functional: "Past 6 months" recomputes CPU Capacity reserved via a capacity_monthly sum over P6');
      has(els['#kpi-gpu'].innerHTML, fmt(gpuCmtyP6.users), 'functional: "Past 6 months" recomputes GPU Researchers served via the community "P6" lookup');
      has(els['#kpi-gpu'].innerHTML, fmt(gpuCmtyP6.groups), 'functional: "Past 6 months" recomputes GPU Research groups via the community "P6" lookup');
      has(els['#kpi-gpu'].innerHTML, gpuCapP6, 'functional: "Past 6 months" recomputes GPU Capacity reserved via a capacity_monthly sum over P6');
    }

    // click "All months": both cards and the range text should update together
    if (handlers['seg-all'].length) handlers['seg-all'].forEach(fn => fn({ target: els['#seg-all'] }));
    else bad('functional: the "All months" segment click handler was never registered');
    const wCpuAll = sumWindow(data.cpu_monthly, data.meta.months_cpu, CPU_FIELDS);
    const wGpuAll = sumWindow(data.gpu_monthly, data.meta.months_gpu, GPU_FIELDS);
    has(els['#kpi-cpu'].innerHTML, fmth(wCpuAll.held), 'functional: clicking "All months" recomputes CPU Reserved core-h correctly');
    has(els['#kpi-cpu'].innerHTML, fmt(wCpuAll.njobs), 'functional: clicking "All months" recomputes CPU Jobs run correctly');
    has(els['#kpi-cpu'].innerHTML, wCpuAll.njobs > 0 ? fmt(wCpuAll.held / wCpuAll.njobs) : '—', 'functional: clicking "All months" recomputes CPU Core-h per job correctly');
    has(els['#kpi-gpu'].innerHTML, fmth(wGpuAll.held), 'functional: clicking "All months" recomputes GPU Reserved GPU-h correctly');
    const allUnion = [...new Set([...data.meta.months_cpu, ...data.meta.months_gpu])].sort();
    {
      const cpuCmtyAll = communityFor('ALL', 'cpu');
      const gpuCmtyAll = communityFor('ALL', 'gpu');
      const cpuCapAll = pctOf(wCpuAll.held, capSumFor(allUnion, 'cpu'));
      const gpuCapAll = pctOf(wGpuAll.held, capSumFor(allUnion, 'gpu'));
      has(els['#kpi-cpu'].innerHTML, fmt(cpuCmtyAll.users), 'functional: "All months" recomputes CPU Researchers served via the community "ALL" lookup');
      has(els['#kpi-cpu'].innerHTML, fmt(cpuCmtyAll.groups), 'functional: "All months" recomputes CPU Research groups via the community "ALL" lookup');
      has(els['#kpi-cpu'].innerHTML, cpuCapAll, 'functional: "All months" recomputes CPU Capacity reserved via a capacity_monthly sum over ALL');
      has(els['#kpi-gpu'].innerHTML, fmt(gpuCmtyAll.users), 'functional: "All months" recomputes GPU Researchers served via the community "ALL" lookup');
      has(els['#kpi-gpu'].innerHTML, fmt(gpuCmtyAll.groups), 'functional: "All months" recomputes GPU Research groups via the community "ALL" lookup');
      has(els['#kpi-gpu'].innerHTML, gpuCapAll, 'functional: "All months" recomputes GPU Capacity reserved via a capacity_monthly sum over ALL');
    }
    const expectAllRange = rangeTextJS(allUnion);
    els['#prange'].textContent === expectAllRange
      ? ok('functional: clicking "All months" updates the range text correctly ("' + expectAllRange + '")')
      : bad('functional: range text after "All months" is "' + els['#prange'].textContent + '", expected "' + expectAllRange + '"');

    // Coverage: GPU's own series (trailing) rarely covers the full union -- "All months"
    // should caption the GPU card with its actual coverage, while still rendering
    // real (not zeroed-out-looking) tiles; CPU's series covers the union, so its
    // caption stays empty.
    const gpuCoveredAll = data.meta.months_gpu.filter(m => allUnion.includes(m));
    const expectGpuCovAll = (gpuCoveredAll.length > 0 && gpuCoveredAll.length < allUnion.length)
      ? 'GPU data: ' + rangeTextJS(gpuCoveredAll) : '';
    els['#gpu-cov'].textContent === expectGpuCovAll
      ? ok('functional: "All months" shows the GPU coverage note ("' + expectGpuCovAll + '")')
      : bad('functional: GPU coverage note after "All months" is "' + els['#gpu-cov'].textContent + '", expected "' + expectGpuCovAll + '"');
    has(els['#kpi-gpu'].innerHTML, 'Reserved GPU-h', 'functional: GPU tiles still render for "All months" (partial coverage, not replaced)');
    els['#cpu-cov'].textContent === ''
      ? ok('functional: CPU coverage note stays empty for "All months" (CPU\'s own series covers the whole union)')
      : bad('functional: CPU coverage note should be empty for "All months", got "' + els['#cpu-cov'].textContent + '"');

    // pick a single month: cards + range text should recompute to that one month
    const singleMonth = data.meta.months_cpu[data.meta.months_cpu.length - 1];
    els['#pmonth'].value = singleMonth;
    if (handlers.pmonth.length) handlers.pmonth.forEach(fn => fn({ target: els['#pmonth'] }));
    else bad('functional: the month-select change handler was never registered');
    const wCpuMonth = sumWindow(data.cpu_monthly, [singleMonth], CPU_FIELDS);
    has(els['#kpi-cpu'].innerHTML, fmth(wCpuMonth.held), 'functional: selecting a single month recomputes CPU Reserved core-h correctly');
    has(els['#kpi-cpu'].innerHTML, fmt(wCpuMonth.njobs), 'functional: selecting a single month recomputes CPU Jobs run correctly');
    has(els['#kpi-cpu'].innerHTML, wCpuMonth.njobs > 0 ? fmt(wCpuMonth.held / wCpuMonth.njobs) : '—', 'functional: selecting a single month recomputes CPU Core-h per job correctly');
    {
      const cpuCmtyMonth = communityFor('M:' + singleMonth, 'cpu');
      const cpuCapMonth = pctOf(wCpuMonth.held, capSumFor([singleMonth], 'cpu'));
      has(els['#kpi-cpu'].innerHTML, fmt(cpuCmtyMonth.users), 'functional: selecting a single month recomputes CPU Researchers served via the community "M:' + singleMonth + '" lookup');
      has(els['#kpi-cpu'].innerHTML, fmt(cpuCmtyMonth.groups), 'functional: selecting a single month recomputes CPU Research groups via the community "M:' + singleMonth + '" lookup');
      has(els['#kpi-cpu'].innerHTML, cpuCapMonth, 'functional: selecting a single month recomputes CPU Capacity reserved via a capacity_monthly sum over that month');
    }
    // GPU mirror: singleMonth (CPU's most recent month) is also within GPU's own
    // coverage today, so the GPU card's new tiles must recompute for it too --
    // not just fall back on the "no data" replacement exercised by earlyMonth below.
    if (data.meta.months_gpu.includes(singleMonth)) {
      const wGpuMonth = sumWindow(data.gpu_monthly, [singleMonth], GPU_FIELDS);
      const gpuCmtyMonth = communityFor('M:' + singleMonth, 'gpu');
      const gpuCapMonth = pctOf(wGpuMonth.held, capSumFor([singleMonth], 'gpu'));
      has(els['#kpi-gpu'].innerHTML, fmt(gpuCmtyMonth.users), 'functional: selecting a single month recomputes GPU Researchers served via the community "M:' + singleMonth + '" lookup');
      has(els['#kpi-gpu'].innerHTML, fmt(gpuCmtyMonth.groups), 'functional: selecting a single month recomputes GPU Research groups via the community "M:' + singleMonth + '" lookup');
      has(els['#kpi-gpu'].innerHTML, gpuCapMonth, 'functional: selecting a single month recomputes GPU Capacity reserved via a capacity_monthly sum over that month');
    } else {
      bad('functional: expected singleMonth (' + singleMonth + ') to be within GPU coverage so the GPU mirror check can run');
    }
    const expectMonthRange = rangeTextJS([singleMonth]);
    els['#prange'].textContent === expectMonthRange
      ? ok('functional: selecting a single month updates the range text correctly ("' + expectMonthRange + '")')
      : bad('functional: range text after a single-month pick is "' + els['#prange'].textContent + '", expected "' + expectMonthRange + '"');

    // Coverage: a month before GPU's own series began (CPU's earliest month) must
    // replace the GPU tiles with a "no data" message, not render misleading
    // zero-value tiles that read as "the GPU pool did nothing"
    const earlyMonth = data.meta.months_cpu[0];
    els['#pmonth'].value = earlyMonth;
    handlers.pmonth.forEach(fn => fn({ target: els['#pmonth'] }));
    has(els['#kpi-gpu'].innerHTML, 'No GPU data for this period', 'functional: a pre-GPU-range month (' + earlyMonth + ') replaces the GPU tiles with "No GPU data for this period"');
    els['#gpu-cov'].textContent === ''
      ? ok('functional: GPU coverage note stays empty when GPU has no data at all (the "no data" tile message carries it instead)')
      : bad('functional: GPU coverage note should be empty (not a caption) when GPU has zero data, got "' + els['#gpu-cov'].textContent + '"');
    has(els['#kpi-cpu'].innerHTML, 'Reserved core-h', 'functional: CPU tiles still render normally for its own earliest month');
  } catch (e) {
    bad('functional: page JS threw during simulated period-control interaction -- ' + (e && e.message ? e.message : e));
  }
}

// ---- 8. blocklist: every data-tip tooltip and every rendered text node ----
const U_CODE = /\bu-\d+\b/, SCC_CODE = /\bscc-[a-z0-9]+\b/i;
{
  const tips = [...html.matchAll(/data-tip="([^"]*)"/g)].map(m => m[1]);
  const bad_t = tips.filter(t => U_CODE.test(t) || SCC_CODE.test(t));
  (tips.length > 0 && bad_t.length === 0) ? ok('every data-tip tooltip passes the blocklist (' + tips.length + ' checked)') : bad('a tooltip matches the blocklist: ' + (bad_t[0] || '(no tooltips found)'));
  const text = html.replace(/<[^>]+>/g, ' ');
  (!U_CODE.test(text) && !SCC_CODE.test(text)) ? ok('rendered text (incl. embedded JSON) passes the blocklist') : bad('rendered text matches a blocklist pattern');
}

// ---- 9. viewport meta ----
has(html, '<meta name="viewport"', 'viewport meta present');

// ---- 10. layout-tightening pass (computed-layout pass): fitted
// GPU blocks, narrower label columns, a 3-column CPU node grid, an aligned
// 4-column KPI grid, deck-titled h3s, and a slim centered period strip ----
const styleBlock = (html.match(/<style>([\s\S]*?)<\/style>/) || ['', ''])[1];
has(styleBlock, '.deck h3{', 'deck titles (GPU/CPU Pool, GPU/CPU Totals) get their own h3 rule');
has(styleBlock, '.kpi{display:grid;grid-template-columns:repeat(2,1fr)', 'KPI cards use a 2-column grid (portals\' own 2-across layout, no label wraps)');
has(styleBlock, '.kpi .kl{font-size:0.688rem;font-weight:600;color:var(--muted);text-transform:uppercase;letter-spacing:.04em;margin-bottom:2px;white-space:nowrap', 'KPI tile labels never wrap (.kl gets white-space:nowrap)');
has(styleBlock, '.pool-gpu h3,#gpucard h3{border-color:#baf72e', 'GPU panel + totals titles carry the chartreuse pool-accent rule line');
has(styleBlock, '.pool-cpu h3,#cpucard h3{border-color:#4cc9db', 'CPU panel + totals titles carry the cyan pool-accent rule line');
not(styleBlock, 'h2{', 'the unused h2 rule was removed (dead CSS -- no <h2> in the markup)');
has(styleBlock, '.sechead{display:flex;align-items:baseline;justify-content:space-between', 'the period control is a "Totals" section-header row (V2 mockup)');
has(styleBlock, 'border-bottom:1px solid var(--rule)', 'the section header carries a rule line underneath');
has(styleBlock, '.sechead .ttl{font-size:.8rem;font-weight:700', '.ttl (the "Totals" title) is styled per the mockup');
has(styleBlock, '.sechead .ctl{display:flex;align-items:center;gap:10px', '.ctl (the segment/select controls) is styled per the mockup');
not(styleBlock, '.periodbar', 'the old .periodbar rules were removed (replaced by .sechead)');
not(styleBlock, '#periodctl', 'the old #periodctl deck rules were removed (replaced by the .sechead section header)');
has(styleBlock, '.sechead{flex-wrap:wrap', 'the section header wraps controls under the title on narrow screens (<=900px)');

// ---- 11. asymmetric pool split: CPU container wider so
// the 6-cluster E5 row renders on one line, panel heights come closer ----
has(styleBlock, '#gpupanel,#gpucard{flex:0 1 37%', 'GPU panel + totals card take the narrower 37% flex share');
has(styleBlock, '#cpupanel,#cpucard{flex:1 1 0', 'CPU panel + totals card take the wider (~63%) flex share');
has(styleBlock, '.hwlbl{color:var(--text);white-space:nowrap', 'hardware labels never wrap mid-name (.hwlbl gets white-space:nowrap)');
not(styleBlock, '.pool-cpu .hwnodes{display:grid', 'CPU node grid override was dropped -- back to flex-wrap now that the wider 60% column fits the E5 row on one line');
/--core-s:clamp\(5px,0\.35vw,12px\)/.test(styleBlock)
  ? ok('CPU core-square size carries a real fit buffer (clamp(5px,0.35vw,12px), ~31px margin at 1440)')
  : bad('--core-s is not buffered to the fitted clamp(5px,0.35vw,12px)');
/--gpu-w:clamp\(13px,0\.93vw,40px\)/.test(styleBlock)
  ? ok('GPU block width is retuned down (40% column is narrower than the old 50/50 half)')
  : bad('--gpu-w is not retuned to the fitted clamp(13px,0.93vw,40px)');

// ---- 12. even column gutters: a uniform-gutter grid with
// snug per-pool label/value column widths, instead of a one-size-fits-all
// flex-basis that left ~70px of dead space before short GPU labels ----
has(styleBlock, '.hwcols,.hwrow{display:grid;grid-template-columns:var(--lblw) var(--valw) 1fr;column-gap:18px', 'hardware rows use a uniform-gutter grid (one column-gap, per-pool column widths via --lblw/--valw); GPU keeps this shared 3-column template unmodified');
has(styleBlock, '.pool-gpu{--lblw:80px;--valw:56px', 'GPU panel gets snug columns sized to its longest label/value ("RTXP6000" / "144 GB")');
has(styleBlock, '.pool-cpu .hwcols,.pool-cpu .hwrow{grid-template-columns:var(--lblw) var(--valw) var(--ramw) 1fr;}', 'CPU gets a pool-scoped 4th column (RAM) via an override rule, not by changing the shared 3-column template');
has(styleBlock, '.pool-cpu{--lblw:120px;--valw:60px;--ramw:66px', 'CPU panel columns are sized to real measured text: label narrows (still fits "Xeon E5-2660\\u00a0v3"), Cores/RAM widen from the brief\'s literal 44px/64px pitch to fit the longest real values ("32 cores" / "1,007 GB")');

// ---- 12b. memory shown exactly once per panel: CPU gains a RAM column
// (Cores/RAM/Nodes plus the label -> CPU, Cores, RAM, Nodes); both panels'
// model tooltips drop the redundant RAM/VRAM line (node-square tooltips and
// the GPU panel's own VRAM column are unchanged) ----
const gpuPanel = sliceFrom('id="gpupanel"', ['id="cpupanel"']);
const cpuPanel = sliceFrom('id="cpupanel"', ['id="sechead"']);
gpuPanel && cpuPanel ? ok('both hardware panels were located in the page') : bad('could not locate both hardware panels');
{
  const cpuColsBlock = (cpuPanel.match(/<div class="hwcols">([\s\S]*?)<\/div>/) || ['', ''])[1];
  const cpuColLabels = [...cpuColsBlock.matchAll(/<span[^>]*>([^<]*)<\/span>/g)].map(m => m[1]);
  JSON.stringify(cpuColLabels) === JSON.stringify(['CPU', 'Cores', 'RAM', 'Nodes'])
    ? ok('CPU .hwcols header reads CPU, Cores, RAM, Nodes in that order')
    : bad('CPU .hwcols header is ' + JSON.stringify(cpuColLabels) + ', want ["CPU","Cores","RAM","Nodes"]');

  const gpuColsBlock = (gpuPanel.match(/<div class="hwcols">([\s\S]*?)<\/div>/) || ['', ''])[1];
  const gpuColLabels = [...gpuColsBlock.matchAll(/<span[^>]*>([^<]*)<\/span>/g)].map(m => m[1]);
  JSON.stringify(gpuColLabels) === JSON.stringify(['GPU', 'VRAM', 'Nodes'])
    ? ok('GPU .hwcols header is unchanged: GPU, VRAM, Nodes')
    : bad('GPU .hwcols header is ' + JSON.stringify(gpuColLabels) + ', want ["GPU","VRAM","Nodes"] (unchanged)');
}
{
  // recompute each CPU model's per-node RAM straight from capacity.cpu.types
  // (5th field, GB) and check every rendered RAM cell against it
  const cpuRows = [...cpuPanel.matchAll(/<div class="hwrow">([\s\S]*?)<\/div>/g)].map(m => m[1]);
  cpuRows.length === data.capacity.cpu.types.length
    ? ok('CPU panel renders one .hwrow per capacity.cpu.types entry (' + cpuRows.length + ')')
    : bad('CPU panel renders ' + cpuRows.length + ' .hwrow, want ' + data.capacity.cpu.types.length);
  cpuRows.forEach((row, i) => {
    const ramCell = (row.match(/<span class="hwc hwram">([^<]*)<\/span>/) || ['', ''])[1];
    const shapeOk = /^\d{1,3}(,\d{3})* GB$/.test(ramCell);
    const ramGb = Number(data.capacity.cpu.types[i][4]);
    const expected = Math.round(ramGb).toLocaleString('en-US') + ' GB';
    (shapeOk && ramCell === expected)
      ? ok('CPU row ' + i + ' RAM cell reads "' + ramCell + '" (matches capacity.cpu.types, /^\\d{1,3}(,\\d{3})* GB$/)')
      : bad('CPU row ' + i + ' RAM cell is "' + ramCell + '", want "' + expected + '" matching /^\\d{1,3}(,\\d{3})* GB$/');
  });
}
{
  // every model tooltip (both panels) is exactly "<b>Model</b><br>Server: X" --
  // no RAM/VRAM line. Node-square tooltips (class="cnode") are untouched and
  // deliberately excluded from this selector.
  const tips = [...html.matchAll(/class="hwlbl" data-tip="([^"]*)"/g)].map(m => m[1]);
  tips.length > 0
    ? ok('found ' + tips.length + ' model tooltips (.hwlbl data-tip) to check')
    : bad('found no .hwlbl model tooltips');
  const unesc = s => s.replace(/&amp;/g, '&').replace(/&quot;/g, '"').replace(/&lt;/g, '<');
  tips.forEach((t, i) => {
    const plain = unesc(t);
    /^<b>[^<]+<\/b><br>Server: [^<]+$/.test(plain)
      ? ok('model tooltip ' + i + ' matches "<b>Model</b><br>Server: X" exactly (no RAM/VRAM line)')
      : bad('model tooltip ' + i + ' is "' + plain + '", does not match "<b>Model</b><br>Server: X"');
  });
  for (const needle of ['RAM:', 'VRAM:'])
    not(html, needle, 'no data-tip (or any other page text) contains "' + needle + '" -- memory appears once, as the CPU RAM column / the GPU VRAM column');
}

// ---- 13. sticky footer + wide-screen growth ----
has(styleBlock, 'body{display:flex;flex-direction:column', 'body is a flex column (sticky-footer pattern)');
has(styleBlock, 'main{max-width:min(var(--content-max),98vw);width:100%;margin:0 auto;padding:14px var(--content-pad) 60px;flex:1 0 auto', 'main grows to fill the flex column (flex:1 0 auto)');
has(styleBlock, 'main{max-width:min(var(--content-max),98vw);width:100%', 'main carries width:100% -- in a column-flex body a margin:0 auto item is fit-content wide unless width is set, and the >=1700px growth rule + all fit margins assume main = min(var(--content-max),98vw)');
has(styleBlock, 'margin-top:auto', 'the footer is pushed to the bottom on tall/short pages (margin-top:auto)');
{
  const bodyIdx = html.indexOf('<body');
  const headerIdx = html.indexOf('<header');
  const mainIdx = html.indexOf('<main>');
  const footerIdx = html.indexOf('<footer');
  (bodyIdx >= 0 && bodyIdx < headerIdx && headerIdx < mainIdx && mainIdx < footerIdx)
    ? ok('header, main, footer are direct children of body in that order')
    : bad('header/main/footer are not in the expected body order');
}
has(styleBlock, '@media(min-width:1700px){.pool-cpu{--core-s:clamp(8px,0.5vw,12px)', 'wide-screen (>=1700px) media block retunes --core-s for bigger units on desktops');
has(styleBlock, '.pool-gpu{--gpu-w:clamp(22px,1.4vw,40px);--gpu-h:clamp(11px,0.7vw,20px)', 'wide-screen media block retunes --gpu-w/--gpu-h');
has(styleBlock, '.deck{padding:13px 14px', 'wide-screen media block gives decks slightly airier padding');
has(styleBlock, '.kpi .kn{font-size:1.3rem', 'wide-screen media block gives KPI numbers a larger font');

// ---- 14. tighter page margins: 96vw -> 98vw, content-pad
// 20px -> 12px, deck padding tightened to match ----
has(styleBlock, '--content-max:2100px;--content-pad:12px', 'content-pad is tightened to 12px');
has(styleBlock, 'main{max-width:min(var(--content-max),98vw)', 'main uses the wider 98vw outer gutter');
has(styleBlock, '.hwrap{max-width:min(var(--content-max),98vw)', 'the header lockup (.hwrap) uses the wider 98vw outer gutter (stays aligned with the decks)');
has(styleBlock, '.pagefoot{max-width:min(var(--content-max),98vw)', 'the footer (.pagefoot) uses the wider 98vw outer gutter (stays aligned with the decks)');
has(styleBlock, '.deck{background:var(--surface);border:1px solid var(--border);border-radius:8px;padding:11px 12px', 'deck padding is tightened to 11px 12px below the wide-screen breakpoint');

// ---- 15. footer mirrors the portals ----
{
  const footerStart = html.indexOf('<footer class="pagefoot"');
  const footerEnd = html.indexOf('</footer>', footerStart) + '</footer>'.length;
  const footerBlock = footerStart >= 0 ? html.slice(footerStart, footerEnd) : '';

  P('div.ft-l') === 'footer.pagefoot' ? ok('.ft-l sits inside <footer class="pagefoot">') : bad('.ft-l parent is ' + P('div.ft-l'));
  P('div.ft-c') === 'footer.pagefoot' ? ok('.ft-c sits inside <footer class="pagefoot">') : bad('.ft-c parent is ' + P('div.ft-c'));
  P('div.ft-r') === 'footer.pagefoot' ? ok('.ft-r sits inside <footer class="pagefoot">') : bad('.ft-r parent is ' + P('div.ft-r'));
  (footerBlock.indexOf('class="ft-l"') >= 0 && footerBlock.indexOf('class="ft-l"') < footerBlock.indexOf('class="ft-c"') && footerBlock.indexOf('class="ft-c"') < footerBlock.indexOf('class="ft-r"'))
    ? ok('footer zones appear in order: ft-l, ft-c, ft-r')
    : bad('footer zones are not in ft-l/ft-c/ft-r order');

  (footerBlock.match(/class="ft-emblem"/g) || []).length === 1
    ? ok('exactly one .ft-emblem image in the footer (single emblem, no theme pair)')
    : bad('footer does not have exactly one .ft-emblem image');
  for (const needle of ['ft-light', 'ft-dark', 'id="poke"', 'ft-m'])
    not(html, needle, 'no "' + needle + '" anywhere (no theme pair, no codename toggle)');

  const ftGh = (footerBlock.match(/<a class="ft-link ft-gh"[^>]*>/) || [''])[0];
  has(ftGh, 'href="https://github.com/BU-CDS/pub-cds-scc"', '.ft-gh anchor points at this page\'s own public repo');
  has(ftGh, 'target="_blank"', '.ft-gh anchor opens in a new tab');
  has(ftGh, 'rel="noopener"', '.ft-gh anchor carries rel="noopener"');
  has(ftGh, 'aria-label="GitHub repository"', '.ft-gh anchor carries an aria-label');
  (footerBlock.match(/<svg viewBox="0 0 16 16"/g) || []).length === 1
    ? ok('.ft-gh contains exactly one <svg viewBox="0 0 16 16"> (the GitHub mark)')
    : bad('.ft-gh does not contain exactly one GitHub-mark svg');

  const ftR = (footerBlock.match(/<div class="ft-r">([\s\S]*?)<\/div>/) || ['', ''])[1];
  has(ftR, 'href="https://www.bu.edu/policies/digital-privacy-statement/"', '.ft-r anchor links to the BU Privacy Statement');
  has(ftR, 'rel="noopener"', '.ft-r anchor carries rel="noopener"');
  has(ftR, '>Privacy Statement<', '.ft-r anchor reads "Privacy Statement"');

  const FOOTER_CSS_RULES = [
    '.pagefoot{max-width:min(var(--content-max),98vw);width:100%;margin:0 auto;margin-top:auto;padding:18px var(--content-pad) 30px;border-top:1px solid var(--border);display:flex;align-items:center;justify-content:space-between;gap:18px;flex-wrap:wrap;}',
    '.pagefoot .ft-l{flex:1 1 200px;display:flex;align-items:center;}',
    '.pagefoot .ft-c{flex:0 0 auto;text-align:center;}',
    '.pagefoot .ft-r{flex:1 1 200px;text-align:right;}',
    '.ft-emblem{height:30px;width:auto;display:block;}',
    '.ft-link{color:var(--muted);font-size:0.75rem;text-decoration:none;display:inline-flex;align-items:center;}',
    '.ft-link:hover{color:var(--used);text-decoration:underline;}',
    '.ft-gh{color:var(--muted);}',
    '.ft-gh:hover{color:var(--used);}',
    '.ft-gh svg{height:30px;width:auto;display:block;}',
  ];
  for (const rule of FOOTER_CSS_RULES) has(styleBlock, rule, 'footer CSS rule present verbatim: ' + rule.slice(0, 44) + (rule.length > 44 ? '...' : ''));
  not(html, 'ft-text', '.ft-text is gone from both markup and CSS');
  has(styleBlock, '.pagefoot{max-width:min(var(--content-max),98vw);width:100%', '.pagefoot carries width:100% -- in a column-flex body a margin:0 auto item is fit-content wide unless width is set, which was shrink-wrapping the footer\'s three zones into a jumbled center block');

  const LIVEWRAP_PREFIX = '<div class="livewrap"><span class="liveupd"><a href="https://rcs.bu.edu" target="_blank" rel="noopener">Data from BU SCC</a> · updated quarterly · ';
  const livewrapCount = html.split(LIVEWRAP_PREFIX).length - 1;
  livewrapCount === 1
    ? ok('the livewrap status line occurs exactly once')
    : bad('livewrap occurs ' + livewrapCount + ' times, want exactly 1');
  const mainIdx = html.indexOf('<main>');
  const livewrapIdx = html.indexOf(LIVEWRAP_PREFIX);
  const firstDeckrowIdx = html.indexOf('<div class="deckrow">');
  (mainIdx >= 0 && livewrapIdx > mainIdx && livewrapIdx < firstDeckrowIdx)
    ? ok('livewrap sits between <main> and the first deckrow')
    : bad('livewrap is not positioned between <main> and the first deckrow');
  not(footerBlock, 'updated quarterly', 'the footer no longer carries the data stamp (moved to livewrap)');
  not(html, 'SGE accounting', '"SGE accounting" no longer appears anywhere (status line reads "Data from BU SCC")');
}

// ---- 16. livewrap must not double-pad: it is nested
// inside <main>, which already applies the 98vw max-width and content-pad,
// so .livewrap itself must carry neither -- only the portals' top-level
// .livewrap needs its own gutter ----
has(styleBlock, '.livewrap{margin:0 0 10px;padding:0;display:flex;flex-wrap:wrap;gap:16px;align-items:center;}', '.livewrap uses the no-double-pad rule (nested under main, not top-level like the portals\')');
{
  const livewrapRule = (styleBlock.match(/\.livewrap\{[^}]*\}/) || [''])[0];
  (!livewrapRule.includes('var(--content-pad)') && !livewrapRule.includes('max-width'))
    ? ok('.livewrap carries neither var(--content-pad) nor max-width (main already applies both)')
    : bad('.livewrap still double-pads: ' + livewrapRule);
}

// ---- 17. status-line stamp copy + link: "Data from
// SGE accounting and gpustats" renamed to "Data from BU SCC", hyperlinked
// to rcs.bu.edu; " · updated quarterly · <date>" stays plain text ----
has(styleBlock, '.liveupd a{color:inherit;text-decoration:underline;text-decoration-color:var(--muted);text-underline-offset:2px;}', '.liveupd a carries the underline-link styling');
has(styleBlock, '.liveupd a:hover{color:var(--used);text-decoration-color:currentColor;}', '.liveupd a:hover carries the hover-color rule');

// ---- 18. embedded assets are never silently empty (b64() now fails closed on a
// missing file at build time; this checks the payloads it does embed aren't
// near-empty either -- each must clear a real floor size) ----
{
  const payloads = [...html.matchAll(/data:(?:image\/png|font\/woff2);base64,([A-Za-z0-9+/=]+)/g)].map(m => m[1]);
  payloads.length === 4
    ? ok('found exactly 4 embedded base64 payloads (plate, emblem, 2 font weights)')
    : bad('found ' + payloads.length + ' embedded base64 payloads, want 4 (plate, emblem, 2 fonts)');
  payloads.forEach((p, i) => {
    p.length > 1024
      ? ok('embedded asset payload #' + (i + 1) + ' clears the empty-file floor (' + p.length + ' base64 chars)')
      : bad('embedded asset payload #' + (i + 1) + ' is suspiciously small (' + p.length + ' base64 chars) -- possible truncated/near-empty asset');
  });
}

// ---- 19. per-card coverage notes: "<Pool> data: <range>" when a selected
// window is only partly covered by that pool's own series, "No <Pool> data for
// this period" (tiles replaced) when not covered at all, nothing when fully
// covered. window3 (the default) is, by construction, fully covered by both
// pools, so both notes render empty here; the functional block above exercises
// the partial- and zero-coverage cases ----
has(html, 'id="gpu-cov"', 'GPU coverage-note element is present');
has(html, 'id="cpu-cov"', 'CPU coverage-note element is present');
{
  const gpuCovDefault = (html.match(/id="gpu-cov">([^<]*)</) || ['', '(absent)'])[1];
  const cpuCovDefault = (html.match(/id="cpu-cov">([^<]*)</) || ['', '(absent)'])[1];
  (gpuCovDefault === '' && cpuCovDefault === '')
    ? ok('window3 (the default) is fully covered by both pools, so both coverage notes render empty')
    : bad('default-window coverage notes are not empty: gpu="' + gpuCovDefault + '", cpu="' + cpuCovDefault + '"');
}

// ---- 20. R5.2 growth note: a pool panel's <h3> ("GPU Pool" / "CPU Pool", not
// the totals cards) carries a right-aligned, muted <span class="hnote"> reading
// "{n} GPUs/GPU added in the past 12 months" (GPU) / "{n} nodes/node added in
// the past 12 months" (CPU), rendered ONLY when that pool's added_12m is > 0;
// no .hnote at all otherwise. Checked against today's real data (present case:
// GPU; absent case: CPU) ----
{
  const gpuPanelH3 = (gpuPanel.match(/<h3>([\s\S]*?)<\/h3>/) || ['', ''])[1];
  const cpuPanelH3 = (cpuPanel.match(/<h3>([\s\S]*?)<\/h3>/) || ['', ''])[1];
  const gpuAdded = Number(data.capacity.gpu.added_12m);
  const cpuAdded = Number(data.capacity.cpu.added_12m);
  const gpuWord = gpuAdded === 1 ? 'GPU' : 'GPUs';
  const cpuWord = cpuAdded === 1 ? 'node' : 'nodes';
  if (gpuAdded > 0) {
    has(gpuPanelH3, '<span class="hnote">' + gpuAdded + ' ' + gpuWord + ' added in the past 12 months</span>', 'GPU panel <h3> carries the growth note span (added_12m=' + gpuAdded + ')');
  } else {
    not(gpuPanelH3, 'class="hnote"', 'GPU panel <h3> carries no .hnote (added_12m=0)');
  }
  if (cpuAdded > 0) {
    has(cpuPanelH3, '<span class="hnote">' + cpuAdded + ' ' + cpuWord + ' added in the past 12 months</span>', 'CPU panel <h3> carries the growth note span (added_12m=' + cpuAdded + ')');
  } else {
    not(cpuPanelH3, 'class="hnote"', 'CPU panel <h3> carries no .hnote (added_12m=0)');
  }
  has(styleBlock, '.pool h3{display:flex;justify-content:space-between;align-items:baseline}', '.pool h3 gets the flex rule that right-aligns the growth note');
  has(styleBlock, '.hnote{font-weight:400;font-size:0.72rem;color:var(--muted);letter-spacing:0;white-space:nowrap}', '.hnote is styled per R5.2 (muted, small, non-wrapping)');
}

// ---- 20b. fixture checks: rebuild the page from a copy of the real data
// with capacity.{cpu,gpu}.added_12m mutated, to prove the growth note is
// genuinely data-driven rather than hardcoded ----
const buildFixturePage = (mutator) => {
  const tmp = mkdtempSync(join(tmpdir(), 'cluster-page-fixture-'));
  try {
    const pageSrc = readFileSync(join(SDIR, '..', 'build_cluster_page.R'), 'utf8');
    writeFileSync(join(tmp, 'build_cluster_page.R'), pageSrc);
    const fixture = JSON.parse(JSON.stringify(data));
    mutator(fixture);
    mkdirSync(join(tmp, 'output'), { recursive: true });
    writeFileSync(join(tmp, 'output', 'cluster_data.json'), JSON.stringify(fixture));
    execFileSync('Rscript', [join(tmp, 'build_cluster_page.R')], { stdio: 'pipe' });
    const fixtureHtml = readFileSync(join(tmp, 'index.html'), 'utf8');
    const fGpuPanel = fixtureHtml.slice(fixtureHtml.indexOf('id="gpupanel"'), fixtureHtml.indexOf('id="cpupanel"'));
    const fCpuPanel = fixtureHtml.slice(fixtureHtml.indexOf('id="cpupanel"'), fixtureHtml.indexOf('id="sechead"'));
    return {
      gpuH3: (fGpuPanel.match(/<h3>([\s\S]*?)<\/h3>/) || ['', ''])[1],
      cpuH3: (fCpuPanel.match(/<h3>([\s\S]*?)<\/h3>/) || ['', ''])[1],
    };
  } finally {
    try { rmSync(tmp, { recursive: true, force: true }); } catch {}
  }
};

// swapped: capacity.cpu.added_12m and capacity.gpu.added_12m swapped, confirm
// which panel carries the .hnote span flips with it -- proves the note is
// genuinely data-driven, not hardcoded to "GPU always present / CPU always absent"
{
  try {
    const realCpuAdded = Number(data.capacity.cpu.added_12m);
    const realGpuAdded = Number(data.capacity.gpu.added_12m);
    const { gpuH3: fGpuH3, cpuH3: fCpuH3 } = buildFixturePage((fixture) => {
      fixture.capacity.cpu.added_12m = realGpuAdded > 0 ? realGpuAdded : 3;
      fixture.capacity.gpu.added_12m = 0;
    });
    not(fGpuH3, 'class="hnote"', 'fixture (swapped): GPU panel <h3> carries no .hnote once its added_12m is 0');
    has(fCpuH3, 'class="hnote"', 'fixture (swapped): CPU panel <h3> now carries the .hnote span once its added_12m is > 0 -- the note flips panels with the data');
  } catch (e) {
    bad('fixture (swapped) growth-note rebuild failed: ' + (e && e.message ? e.message : e));
  }
}

// singular: added_12m === 1 must render the singular word ("1 GPU added...",
// never "1 GPUs added...")
{
  try {
    const { gpuH3: fGpuH3, cpuH3: fCpuH3 } = buildFixturePage((fixture) => {
      fixture.capacity.gpu.added_12m = 1;
      fixture.capacity.cpu.added_12m = 0;
    });
    has(fGpuH3, '<span class="hnote">1 GPU added in the past 12 months</span>', 'fixture (added_12m=1): GPU panel <h3> uses the singular "GPU" wording, not "GPUs"');
    not(fGpuH3, '1 GPUs added', 'fixture (added_12m=1): GPU panel <h3> never renders the plural "GPUs" wording for n=1');
    not(fCpuH3, 'class="hnote"', 'fixture (added_12m=1): CPU panel <h3> still carries no .hnote (its added_12m stayed 0)');
  } catch (e) {
    bad('fixture (added_12m=1) growth-note rebuild failed: ' + (e && e.message ? e.message : e));
  }
}

// ---- 21. negative: no user code or project name from either internal
// de-identified emit (read fresh at test time, mirroring scripts/gate_cluster.mjs's
// own leak-check reader) appears anywhere in the page ----
{
  const PUB_CPU_CLONE = process.env.PUB_CPU_CLONE || '/usr3/bustaff/mhorn/repos/cpu-cds-scc';
  const PUB_GPU_CLONE = process.env.PUB_GPU_CLONE || '/usr3/bustaff/mhorn/repos/gpu-cds-scc';
  const readInternalCodes = (path) => {
    let d;
    try { d = JSON.parse(readFileSync(path, 'utf8')); }
    catch { return { users: [], projects: [] }; }
    const cols = d.Fcols || [];
    const ui = cols.indexOf('user'), pi = cols.indexOf('proj');
    if (ui < 0 || pi < 0) return { users: [], projects: [] };
    const users = new Set(), projects = new Set();
    for (const row of d.F || []) {
      if (row[ui]) users.add(row[ui]);
      if (row[pi]) projects.add(row[pi]);
    }
    return { users: [...users], projects: [...projects] };
  };
  const cpuCodes = readInternalCodes(join(PUB_CPU_CLONE, 'output', 'portal_data.json'));
  const gpuCodes = readInternalCodes(join(PUB_GPU_CLONE, 'output', 'portal_data.json'));
  const userCodes = [...new Set([...cpuCodes.users, ...gpuCodes.users])];
  const projectNames = [...new Set([...cpuCodes.projects, ...gpuCodes.projects])];
  (userCodes.length > 0 && projectNames.length > 0)
    ? ok('leak-check blocklist loaded from both internal emits (' + userCodes.length + ' user codes, ' + projectNames.length + ' project names)')
    : bad('leak-check blocklist is empty -- internal emit unreadable/unusable');
  const leakedUsers = userCodes.filter((u) => html.includes(u));
  const leakedProjects = projectNames.filter((p) => html.includes(p));
  leakedUsers.length === 0 ? ok('no internal-emit user code appears anywhere in the page') : bad('user code(s) leaked into the page: ' + leakedUsers.length + ' hit(s)');
  leakedProjects.length === 0 ? ok('no internal-emit project name appears anywhere in the page') : bad('project name(s) leaked into the page: ' + leakedProjects.length + ' hit(s)');
}

console.log(FAILS ? FAILS + ' FAILED' : 'ALL PASS');
process.exit(FAILS ? 1 : 0);
