// test_page.mjs — assert the built public page's STRUCTURE, JS-execution safety, and
// de-id/blocklist policy for the portal-lift design (spec Revision R1): twin pool
// panels (GPU left, CPU right), a segmented [Past 3|6|All months] period bar plus a
// month-only <select> and a resolved-range text (default: trailing 3 complete
// months), and per-pool KPI totals cards recomputed by inline JS. The old zero-JS
// rule is dead; this suite checks the inline script is present, self-contained (no
// external requests / storage / theme machinery), and functionally correct
// (simulated segment clicks / month picks recompute the KPI cards and range text).
//
// Run: module load nodejs/20.12.2 && node scripts/test_page.mjs [index.html]
// Exit 0 = pass, 1 = wrong, 2 = usage.
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

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
// (the old zero-JS rule is dead per spec Revision R1 -- inline JS is now required, but it
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
// verbatim from the Task-3 test / cpu-cds-scc/scripts/test_page.mjs).
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
P('div#gpupanel.deck.pool-gpu') === 'div.deckrow' ? ok('GPU panel sits inside a deckrow') : bad('GPU panel parent is ' + P('div#gpupanel.deck.pool-gpu'));
P('div#cpupanel.deck.pool-cpu') === 'div.deckrow' ? ok('CPU panel sits inside a deckrow') : bad('CPU panel parent is ' + P('div#cpupanel.deck.pool-cpu'));
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
// the footer's stamp wording moves monthly -> quarterly per spec Revision R1
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

// ---- 6. two KPI totals cards with the portals' tile labels, GPU left / CPU right ----
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
for (const lbl of ['Held core-h', 'Avg Efficiency', 'Under-utilized core-h', 'Utilized core-h', 'Jobs', 'Walltime Accuracy', 'on hard-failed jobs', 'on wall-killed jobs'])
  has(cpuCard, lbl, 'CPU totals card shows the "' + lbl + '" tile');
for (const lbl of ['Held GPU-h', 'Avg Utilization', 'Under-Utilized GPU-h', 'Non-Utilized GPU-h', 'Energy kWh', 'Mean VRAM', 'on hard-failed jobs', 'on wall-killed jobs'])
  has(gpuCard, lbl, 'GPU totals card shows the "' + lbl + '" tile');

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
has(cpuCard, fmth(wCpu.held), 'CPU totals: Held core-h matches the recomputed window3 total');
has(cpuCard, (wCpu.held ? Math.round(100 * wCpu.utilized / wCpu.held) : 0) + '%', 'CPU totals: Avg Efficiency % matches recomputed window3');
has(gpuCard, fmth(wGpu.held), 'GPU totals: Held GPU-h matches the recomputed window3 total');
has(gpuCard, (wGpu.held ? Math.round(100 * wGpu.real / wGpu.held) : 0) + '%', 'GPU totals: Avg Utilization % matches recomputed window3');

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

    // click "All months": both cards and the range text should update together
    if (handlers['seg-all'].length) handlers['seg-all'].forEach(fn => fn({ target: els['#seg-all'] }));
    else bad('functional: the "All months" segment click handler was never registered');
    const wCpuAll = sumWindow(data.cpu_monthly, data.meta.months_cpu, CPU_FIELDS);
    const wGpuAll = sumWindow(data.gpu_monthly, data.meta.months_gpu, GPU_FIELDS);
    has(els['#kpi-cpu'].innerHTML, fmth(wCpuAll.held), 'functional: clicking "All months" recomputes CPU Held core-h correctly');
    has(els['#kpi-gpu'].innerHTML, fmth(wGpuAll.held), 'functional: clicking "All months" recomputes GPU Held GPU-h correctly');
    const allUnion = [...new Set([...data.meta.months_cpu, ...data.meta.months_gpu])].sort();
    const expectAllRange = rangeTextJS(allUnion);
    els['#prange'].textContent === expectAllRange
      ? ok('functional: clicking "All months" updates the range text correctly ("' + expectAllRange + '")')
      : bad('functional: range text after "All months" is "' + els['#prange'].textContent + '", expected "' + expectAllRange + '"');

    // pick a single month: cards + range text should recompute to that one month
    const singleMonth = data.meta.months_cpu[data.meta.months_cpu.length - 1];
    els['#pmonth'].value = singleMonth;
    if (handlers.pmonth.length) handlers.pmonth.forEach(fn => fn({ target: els['#pmonth'] }));
    else bad('functional: the month-select change handler was never registered');
    const wCpuMonth = sumWindow(data.cpu_monthly, [singleMonth], CPU_FIELDS);
    has(els['#kpi-cpu'].innerHTML, fmth(wCpuMonth.held), 'functional: selecting a single month recomputes CPU Held core-h correctly');
    const expectMonthRange = rangeTextJS([singleMonth]);
    els['#prange'].textContent === expectMonthRange
      ? ok('functional: selecting a single month updates the range text correctly ("' + expectMonthRange + '")')
      : bad('functional: range text after a single-month pick is "' + els['#prange'].textContent + '", expected "' + expectMonthRange + '"');
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

// ---- 10. layout-tightening pass (maintainer computed-layout review): fitted
// GPU blocks, narrower label columns, a 3-column CPU node grid, an aligned
// 4-column KPI grid, deck-titled h3s, and a slim centered period strip ----
const styleBlock = (html.match(/<style>([\s\S]*?)<\/style>/) || ['', ''])[1];
has(styleBlock, '.deck h3{', 'deck titles (GPU/CPU Pool, GPU/CPU Totals) get their own h3 rule');
has(styleBlock, '.kpi{display:grid;grid-template-columns:repeat(4,1fr)', 'KPI cards use a 4-column grid so both cards align tile-for-tile');
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

// ---- 11. asymmetric pool split (maintainer round 2): CPU container wider so
// the 6-cluster E5 row renders on one line, panel heights come closer ----
has(styleBlock, '#gpupanel,#gpucard{flex:0 1 40%', 'GPU panel + totals card take the narrower 40% flex share');
has(styleBlock, '#cpupanel,#cpucard{flex:1 1 0', 'CPU panel + totals card take the wider (~60%) flex share');
has(styleBlock, '.hwlbl{color:var(--text);white-space:nowrap', 'hardware labels never wrap mid-name (.hwlbl gets white-space:nowrap)');
not(styleBlock, '.pool-cpu .hwnodes{display:grid', 'CPU node grid override was dropped -- back to flex-wrap now that the wider 60% column fits the E5 row on one line');
/--core-s:clamp\(5px,0\.35vw,12px\)/.test(styleBlock)
  ? ok('CPU core-square size carries a real fit buffer (clamp(5px,0.35vw,12px), ~31px margin at 1440)')
  : bad('--core-s is not buffered to the fitted clamp(5px,0.35vw,12px)');
/--gpu-w:clamp\(13px,0\.93vw,40px\)/.test(styleBlock)
  ? ok('GPU block width is retuned down (40% column is narrower than the old 50/50 half)')
  : bad('--gpu-w is not retuned to the fitted clamp(13px,0.93vw,40px)');

// ---- 12. even column gutters (maintainer round 4): a uniform-gutter grid with
// snug per-pool label/value column widths, instead of a one-size-fits-all
// flex-basis that left ~70px of dead space before short GPU labels ----
has(styleBlock, '.hwcols,.hwrow{display:grid;grid-template-columns:var(--lblw) var(--valw) 1fr;column-gap:18px', 'hardware rows use a uniform-gutter grid (one column-gap, per-pool column widths via --lblw/--valw)');
has(styleBlock, '.pool-gpu{--lblw:80px;--valw:56px', 'GPU panel gets snug columns sized to its longest label/value ("RTXP6000" / "144 GB")');
has(styleBlock, '.pool-cpu{--lblw:130px;--valw:64px', 'CPU panel keeps its wider columns sized to its longest label/value ("Xeon E5-2660\\u00a0v3" / "32 cores")');

console.log(FAILS ? FAILS + ' FAILED' : 'ALL PASS');
process.exit(FAILS ? 1 : 0);
