// test_page.mjs — assert the built showcase page's STRUCTURE and de-id/theme
// policy: zero JS, one light theme, main holds exactly the four sections in
// order, one bar per month in each delivered chart, and every rendered string
// (tooltips + text) passes the same blocklist the data-layer gate enforces.
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

// ---- 0. zero JS anywhere ----
(html.match(/<script/g) || []).length === 0 ? ok('zero <script occurrences') : bad('found <script in the page');

// ---- 1. containment, not just order: a stray </div> can close a section early
// while every string check still passes. Tiny stack parser over the static
// markup (copied verbatim from cpu-cds-scc/scripts/test_page.mjs).
const parentOf = (() => {
  const body = html.slice(html.indexOf('<body')).replace(/<script[\s\S]*?<\/script>/g, '');
  const stack = [], parent = {}; const voids = new Set(['br', 'img', 'input', 'meta', 'link', 'hr']);
  for (const m of body.matchAll(/<(\/?)([a-zA-Z0-9]+)([^>]*)>/g)) {
    const [, close, tag, attrs] = m;
    if (close) { for (let i = stack.length - 1; i >= 0; i--) if (stack[i].tag === tag) { stack.length = i; break; } continue; }
    const id = (attrs.match(/\bid="([^"]+)"/) || [])[1], cls = (attrs.match(/\bclass="([^"]+)"/) || [])[1];
    const lab = tag + (id ? '#' + id : '') + (cls ? '.' + cls.replace(/\s+/g, '.') : '');
    parent[lab] = stack.length ? stack[stack.length - 1].lab : '(root)';
    if (!voids.has(tag)) stack.push({ tag, lab, row: cls === 'deckrow' ? (parent.__rows = (parent.__rows || 0) + 1) : undefined });
  }
  return parent;
})();
const P = sel => parentOf[sel] || '(absent)';
P('div.headline') === 'main' ? ok('headline band is a direct child of main') : bad('headline band parent is ' + P('div.headline'));
P('section.hw.hw-cpu') === 'main' ? ok('CPU hardware section is a direct child of main') : bad('CPU hw section parent is ' + P('section.hw.hw-cpu'));
P('section.hw.hw-gpu') === 'main' ? ok('GPU hardware section is a direct child of main') : bad('GPU hw section parent is ' + P('section.hw.hw-gpu'));
P('section.delivered') === 'main' ? ok('delivered section is a direct child of main') : bad('delivered section parent is ' + P('section.delivered'));
{
  const main = html.slice(html.indexOf('<main>'), html.indexOf('</main>'));
  const kids = [...main.matchAll(/<(div|section)\b[^>]*>/g)].filter(m => {
    // only count the direct children we just asserted parentage for, not their descendants
    const idx = m.index;
    const before = main.slice(0, idx);
    return /<(div class="headline"|section class="hw hw-cpu"|section class="hw hw-gpu"|section class="delivered")/.test(m[0]);
  });
  kids.length === 4 ? ok('main holds exactly 4 sections (headline, 2 hardware, delivered)') : bad('main holds ' + kids.length + ' of the expected 4 top sections');
  const opens = (main.match(/<div\b/g) || []).length, closes = (main.match(/<\/div>/g) || []).length;
  opens === closes ? ok('div tags balance inside main (' + opens + ')') : bad('div tags unbalanced inside main: ' + opens + ' open vs ' + closes + ' close');
}

// ---- 2. header lockup ----
const head1 = (html.match(/<h1>([\s\S]*?)<\/h1>/) || ['', ''])[1];
has(head1, 'class="buplate"', 'h1 carries the University plate image');
has(head1, 'Faculty of Computing &amp; Data Sciences', 'h1 carries the school name');

// ---- 3. headline band labels ----
const headline = (html.match(/<div class="headline">([\s\S]*?)<\/div>\s*<section/) || ['', ''])[1] || html;
for (const lbl of ['cores', 'GPUs', 'core-hours', 'GPU-hours', 'jobs'])
  has(headline, lbl, 'headline band shows the "' + lbl + '" label');

const fmt = n => Math.round(n).toLocaleString('en-US');
has(headline, fmt(data.capacity.cpu.cores), 'headline shows the CPU core count');
has(headline, fmt(data.capacity.gpu.gpus), 'headline shows the GPU count');
has(headline, fmt(data.headline.cpu_core_h), 'headline shows the CPU core-hours total');
has(headline, fmt(data.headline.gpu_h), 'headline shows the GPU-hours total');
has(headline, fmt(data.headline.jobs), 'headline shows the jobs total');

// ---- 4. delivered charts: one bar per month ----
const chartSlice = (cls) => {
  const start = html.indexOf('class="chart ' + cls + '"');
  if (start < 0) return '';
  const next = html.indexOf('class="chart ', start + 10);
  return html.slice(start, next > 0 ? next : html.indexOf('</section>', start));
};
const cpuChart = chartSlice('chart-cpu');
const gpuChart = chartSlice('chart-gpu');
{
  const cpuBars = (cpuChart.match(/<div class=bar /g) || []).length;
  const gpuBars = (gpuChart.match(/<div class=bar /g) || []).length;
  cpuBars === data.meta.months_cpu.length ? ok('CPU chart renders one bar per month (' + cpuBars + ')') : bad('CPU chart has ' + cpuBars + ' bars, want ' + data.meta.months_cpu.length);
  gpuBars === data.meta.months_gpu.length ? ok('GPU chart renders one bar per month (' + gpuBars + ')') : bad('GPU chart has ' + gpuBars + ' bars, want ' + data.meta.months_gpu.length);
}
has(cpuChart, 'core-hours allocated to jobs', 'CPU chart caption names the measure');
has(gpuChart, 'GPU-hours allocated to jobs', 'GPU chart caption names the measure');

// ---- 5. blocklist: every tooltip and every rendered text node ----
const U_CODE = /\bu-\d+\b/, SCC_CODE = /\bscc-[a-z0-9]+\b/i;
{
  const titles = [...html.matchAll(/title="([^"]*)"/g)].map(m => m[1]);
  const bad_t = titles.filter(t => U_CODE.test(t) || SCC_CODE.test(t));
  bad_t.length === 0 ? ok('every title= tooltip passes the blocklist (' + titles.length + ' checked)') : bad('a tooltip matches the blocklist: ' + bad_t[0]);
  const text = html.replace(/<[^>]+>/g, ' ');
  (!U_CODE.test(text) && !SCC_CODE.test(text)) ? ok('rendered text passes the blocklist') : bad('rendered text matches a blocklist pattern');
}

// ---- 6. no theme machinery, single light theme ----
not(html, 'data-theme', 'no data-theme attribute anywhere');
not(html, 'localStorage', 'no localStorage anywhere');
not(html, 'prefers-color-scheme', 'no prefers-color-scheme anywhere');

// ---- 7. viewport meta ----
has(html, '<meta name="viewport"', 'viewport meta present');

console.log(FAILS ? FAILS + ' FAILED' : 'ALL PASS');
process.exit(FAILS ? 1 : 0);
