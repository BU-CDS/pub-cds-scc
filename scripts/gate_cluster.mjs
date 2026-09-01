// gate_cluster.mjs — de-id gate for output/cluster_data.json and the built public
// page. Whitelist first, blocklist second, conservation third. ANY violation
// exits 1 and the pipeline stops before deploy can run. Fails safe: a false
// positive blocks a publish; a miss cannot, because the whitelist rejects every
// string outside the enumerated vocabularies (hardware models, server models,
// cards, node classes, YYYY-MM periods) and the blocklist scans the full text
// for real hostnames and registry codes regardless of where they land.
//
// Contract v3 (2026-09-01) adds: `community` (window_key/pool vocab, every
// key x pool pair present exactly once, monotone P3<=P6<=ALL checked as
// direct pairs and every M:<=ALL per pool/metric), `capacity_monthly` (month
// whitelisted against that pool's own published month list, cap_h > 0,
// exactly one row per pool per month of that pool's monthly table),
// `capacity.*.added_12m` (non-negative integer, <= that pool's total units),
// meta.contract === 3. The blocklist scan additionally reads every user code
// and project name out of BOTH internal de-identified emits (CPU's and the
// NEW GPU one) at gate time -- failing closed if either list comes back empty
// (an unusable leak check, not "nothing to leak") -- and asserts none occurs,
// raw or HTML-entity-decoded, anywhere in the scanned text; failure names the
// category (user code / project) plus a short local sha1 reference, never the
// value itself.
//
// Contract v4 (R6): `weekly` rows [monday, pool, held_h] — monday a `YYYY-MM-DD`
// Monday, per pool exactly the dense list of complete weeks inside that pool's
// published months, held_h ≥ 0, Σ within 5 % of the pool's monthly Σheld_h;
// meta.contract === 4. The gate never read the GPU public emit and still doesn't.
//
// Usage: node gate_cluster.mjs <cluster_data.json> [built_html]
//   - called before build with just the json (data-layer gate)
//   - called after build with the html too (page gate)
// Vocab + blocklist sources: sibling clones' config/ CSVs and (contract v3)
// output/portal_data.json internal emits (env-overridable, same PUB_CPU_CLONE
// / PUB_GPU_CLONE vars 50_cluster_data.R reads).
import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { createHash } from 'node:crypto';

const [dataPath, htmlPath] = process.argv.slice(2);
if (!dataPath) {
  console.error('usage: node gate_cluster.mjs <cluster_data.json> [built_html]');
  process.exit(2);
}

const PUB_CPU_CLONE = process.env.PUB_CPU_CLONE || '/usr3/bustaff/mhorn/repos/cpu-cds-scc';
const PUB_GPU_CLONE = process.env.PUB_GPU_CLONE || '/usr3/bustaff/mhorn/repos/gpu-cds-scc';

const errs = [];
const bad = (m) => errs.push(m);

// ---- tiny CSV reader: these config files have no quoted/embedded commas ----
const readCsv = (path) => {
  let text;
  try { text = readFileSync(path, 'utf8'); }
  catch (e) { bad(`cannot read config: ${path} (${e.message})`); return []; }
  const lines = text.trim().split('\n');
  const header = lines[0].split(',');
  return lines.slice(1).filter(Boolean).map((l) => {
    const cells = l.split(',');
    return Object.fromEntries(header.map((h, i) => [h, cells[i]]));
  });
};

// ---- vocabularies (single source: the same configs 50_cluster_data.R reads) --
const cpuInv = readCsv(join(PUB_CPU_CLONE, 'config', 'cds_cpu_inventory.csv'));
const cpuHosts = readCsv(join(PUB_CPU_CLONE, 'config', 'cds_cpu_hosts.csv'));
const gpuInv = readCsv(join(PUB_GPU_CLONE, 'config', 'gpu_inventory_history.csv'));
const gpuHosts = readCsv(join(PUB_GPU_CLONE, 'config', 'cds_gpu_hosts.csv'));

const setOf = (rows, col) => new Set(rows.map((r) => r[col]).filter(Boolean));
const CPU_MODELS = setOf(cpuInv, 'cpu_type');          // capacity.cpu.types[].label vocab
const CPU_SERVERS = setOf(cpuInv, 'server_model');     // capacity.cpu.types[].server vocab
const CARDS = new Set([...setOf(gpuInv, 'gpu_type'), ...setOf(gpuHosts, 'gpu_type')]);   // gpu label/card vocab
const GPU_SERVERS = setOf(gpuInv, 'server_model');     // capacity.gpu.types[].server vocab
const NODE_CLASSES = setOf(cpuHosts, 'node_class');    // cpu_monthly[].node_class vocab
const HOSTNAMES = [...new Set([
  ...cpuInv.map((r) => r.host), ...cpuHosts.map((r) => r.host),
  ...gpuInv.map((r) => r.host), ...gpuHosts.map((r) => r.host),
].filter(Boolean))];   // REAL hostnames: blocklisted below, never whitelisted anywhere

// contract v3: every user code and project name from BOTH internal de-identified
// emits, read fresh at gate time (not from the whitelist configs above) -- this
// is the blocklist source for the leak check, independent of what 50_cluster_data.R
// actually did with them.
const readInternalCodes = (path) => {
  let d;
  try { d = JSON.parse(readFileSync(path, 'utf8')); }
  catch (e) { bad(`cannot read internal emit for leak check: ${path} (${e.message})`); return { users: [], projects: [] }; }
  const cols = d.Fcols || [];
  const ui = cols.indexOf('user'), pi = cols.indexOf('proj');
  if (ui < 0 || pi < 0) { bad(`internal emit missing user/proj columns for leak check: ${path}`); return { users: [], projects: [] }; }
  const users = new Set(), projects = new Set();
  for (const row of d.F || []) {
    if (row[ui]) users.add(row[ui]);
    if (row[pi]) projects.add(row[pi]);
  }
  return { users: [...users], projects: [...projects] };
};
const cpuCodes = readInternalCodes(join(PUB_CPU_CLONE, 'output', 'portal_data.json'));
const gpuCodes = readInternalCodes(join(PUB_GPU_CLONE, 'output', 'portal_data.json'));
const LEAK_USER_CODES = [...new Set([...cpuCodes.users, ...gpuCodes.users])];
const LEAK_PROJECT_NAMES = [...new Set([...cpuCodes.projects, ...gpuCodes.projects])];
// An empty blocklist doesn't mean "nothing to leak" -- it means the leak check
// itself is unusable (e.g. an internal emit with F: [], or an unreadable/malformed
// one already flagged above). Fail closed rather than silently no-op the check.
// Checked per source: one healthy emit must not mask the other shipping F: [].
for (const [src, c] of [['CPU', cpuCodes], ['GPU', gpuCodes]])
  if (!c.users.length || !c.projects.length)
    bad(`leak-check blocklist empty for the ${src} internal emit (unusable)`);

const PERIOD = /^\d{4}-\d{2}$/;
const DATE = /^\d{4}-\d{2}-\d{2}$/;
const POOLS = new Set(['cpu', 'gpu']);

// ---- 1. structural + value whitelist -----------------------------------
let data;
let rawText;
try { rawText = readFileSync(dataPath, 'utf8'); data = JSON.parse(rawText); }
catch (e) { bad(`cannot read/parse ${dataPath}: ${e.message}`); }

if (data) {
  const TOP = ['meta', 'capacity', 'cpu_monthly', 'gpu_monthly', 'headline', 'community', 'capacity_monthly', 'weekly'];
  for (const k of Object.keys(data)) if (!TOP.includes(k)) bad(`unexpected top-level key: ${k}`);
  for (const k of TOP) if (!(k in data)) bad(`missing top-level key: ${k}`);

  const META_KEYS = ['updated', 'public', 'months_cpu', 'months_gpu', 'window3', 'contract'];
  const meta = data.meta || {};
  for (const k of Object.keys(meta)) if (!META_KEYS.includes(k)) bad(`unexpected meta key: ${k}`);
  if (!DATE.test(meta.updated)) bad(`meta.updated not YYYY-MM-DD: ${meta.updated}`);
  if (meta.public !== true) bad('meta.public is not true');
  if (Number(meta.contract) !== 4) bad(`meta.contract must be 4: ${meta.contract}`);
  for (const listKey of ['months_cpu', 'months_gpu', 'window3']) {
    for (const m of meta[listKey] || []) if (!PERIOD.test(m)) bad(`meta.${listKey}: bad period: ${m}`);
  }
  const monthsCpu = new Set(meta.months_cpu || []);
  const monthsGpu = new Set(meta.months_gpu || []);
  const window3 = new Set(meta.window3 || []);
  if (window3.size < 1 || window3.size > 3) bad(`meta.window3 has ${window3.size} months (want 1..3)`);

  // ---- capacity ----
  const capCheck = (group, keys, modelSet, serverSet, totalKey) => {
    const c = (data.capacity || {})[group];
    if (!c) { bad(`missing capacity.${group}`); return; }
    for (const k of Object.keys(c)) if (!keys.includes(k)) bad(`unexpected capacity.${group} key: ${k}`);
    for (const k of keys) if (!(k in c)) bad(`missing capacity.${group}.${k}`);
    for (const row of c.types || []) {
      if (row.length !== 5) { bad(`capacity.${group}.types: row length ${row.length} != 5`); continue; }
      const [label, server, count, per_node, per_node_ram_gb] = row;
      if (!modelSet.has(label)) bad(`capacity.${group}.types: unknown label: ${label}`);
      if (!serverSet.has(server)) bad(`capacity.${group}.types: unknown server model: ${server}`);
      for (const v of [count, per_node, per_node_ram_gb])
        if (!(Number(v) > 0)) bad(`capacity.${group}.types: non-positive count in ${JSON.stringify(row)}`);
    }
    const total = Number(c[totalKey]);
    if (!(Number.isInteger(Number(c.added_12m)) && Number(c.added_12m) >= 0 && Number(c.added_12m) <= total))
      bad(`capacity.${group}.added_12m invalid or exceeds pool total (${totalKey}=${total}): ${c.added_12m}`);
  };
  capCheck('cpu', ['nodes', 'cores', 'ram_gb', 'types', 'added_12m'], CPU_MODELS, CPU_SERVERS, 'cores');
  capCheck('gpu', ['nodes', 'gpus', 'vram_gb', 'types', 'added_12m'], CARDS, GPU_SERVERS, 'gpus');

  // ---- monthly tables ----
  // contract v2 row shape: [month, class, ...numFields] -- numFields named in
  // order so a bad value's error message names the actual field, not an index.
  const CPU_NUM_FIELDS = ['held_h', 'utilized_h', 'fail_h', 'wkill_h', 'njobs', 'wa_used_h', 'wa_req_h'];
  const GPU_NUM_FIELDS = ['held_h', 'real_h', 'residle_h', 'kwh', 'vram_h', 'fail_h', 'wkill_h', 'njobs'];
  const monthlyCheck = (rows, name, classSet, monthSet, numFields) => {
    const width = 2 + numFields.length;
    for (const row of rows || []) {
      if (row.length !== width) { bad(`${name}: row length ${row.length} != ${width}`); continue; }
      const [m, cls, ...nums] = row;
      if (!PERIOD.test(m)) bad(`${name}: bad period: ${m}`);
      else if (!monthSet.has(m)) bad(`${name}: period out of meta's month list: ${m}`);
      if (!classSet.has(cls)) bad(`${name}: unknown value: ${cls}`);
      numFields.forEach((fname, i) => {
        const v = nums[i];
        if (!(Number.isFinite(Number(v)) && Number(v) >= 0)) bad(`${name}: bad ${fname}: ${v}`);
      });
    }
  };
  monthlyCheck(data.cpu_monthly, 'cpu_monthly', NODE_CLASSES, monthsCpu, CPU_NUM_FIELDS);
  monthlyCheck(data.gpu_monthly, 'gpu_monthly', CARDS, monthsGpu, GPU_NUM_FIELDS);

  // ---- community: [window_key, pool, users, groups] ----
  // window_key vocab mirrors build_cluster_page.R's own windows: "M:<month>" for
  // each month in meta.months_cpu/months_gpu, plus "P3"/"P6"/"ALL".
  const COMMUNITY_KEYS = new Set([
    ...[...monthsCpu, ...monthsGpu].map((m) => `M:${m}`),
    'P3', 'P6', 'ALL',
  ]);
  const commByKeyPool = new Map();
  const commCount = new Map();
  for (const row of data.community || []) {
    if (row.length !== 4) { bad(`community: row length ${row.length} != 4`); continue; }
    const [key, pool, users, groups] = row;
    if (!COMMUNITY_KEYS.has(key)) bad(`community: unknown window key: ${key}`);
    if (!POOLS.has(pool)) bad(`community: unknown pool: ${pool}`);
    for (const [fname, v] of [['users', users], ['groups', groups]])
      if (!(Number.isInteger(Number(v)) && Number(v) >= 0)) bad(`community: bad ${fname}: ${v}`);
    const mapKey = `${key}|${pool}`;
    commByKeyPool.set(mapKey, { users: Number(users), groups: Number(groups) });
    commCount.set(mapKey, (commCount.get(mapKey) || 0) + 1);
  }
  // completeness: every whitelisted window key x pool pair must appear exactly
  // once -- an empty/partial `community` (or one missing just P6, say) passes
  // the checks above silently otherwise, and severs the monotone chain below
  // without a trace.
  for (const key of COMMUNITY_KEYS) for (const pool of POOLS) {
    const cnt = commCount.get(`${key}|${pool}`) || 0;
    if (cnt !== 1) bad(`community: expected exactly 1 row for window ${key} / pool ${pool}, found ${cnt}`);
  }
  // monotone per pool: P3 <= P6 <= ALL, checked as three direct pairs (not just
  // adjacent) so a single broken/missing link can't hide a P3 > ALL violation.
  for (const pool of POOLS) {
    const p3 = commByKeyPool.get(`P3|${pool}`), p6 = commByKeyPool.get(`P6|${pool}`), all = commByKeyPool.get(`ALL|${pool}`);
    if (p3 && p6 && !(p3.users <= p6.users && p3.groups <= p6.groups)) bad(`community: P3 > P6 for pool ${pool}`);
    if (p6 && all && !(p6.users <= all.users && p6.groups <= all.groups)) bad(`community: P6 > ALL for pool ${pool}`);
    if (p3 && all && !(p3.users <= all.users && p3.groups <= all.groups)) bad(`community: P3 > ALL for pool ${pool}`);
    if (all) {
      for (const [mapKey, v] of commByKeyPool) {
        if (!mapKey.startsWith('M:') || !mapKey.endsWith(`|${pool}`)) continue;
        if (!(v.users <= all.users && v.groups <= all.groups)) bad(`community: ${mapKey.split('|')[0]} > ALL for pool ${pool}`);
      }
    }
  }

  // ---- capacity_monthly: [month, pool, cap_h] ----
  // month whitelisted against that pool's OWN published month list (matches
  // cpu_monthly/gpu_monthly's own coverage, not the wider community union).
  const capMonthlyCount = new Map();
  for (const row of data.capacity_monthly || []) {
    if (row.length !== 3) { bad(`capacity_monthly: row length ${row.length} != 3`); continue; }
    const [m, pool, cap_h] = row;
    if (!POOLS.has(pool)) bad(`capacity_monthly: unknown pool: ${pool}`);
    if (!PERIOD.test(m)) bad(`capacity_monthly: bad period: ${m}`);
    else if (pool === 'cpu' && !monthsCpu.has(m)) bad(`capacity_monthly: period out of meta's cpu month list: ${m}`);
    else if (pool === 'gpu' && !monthsGpu.has(m)) bad(`capacity_monthly: period out of meta's gpu month list: ${m}`);
    if (!(Number.isFinite(Number(cap_h)) && Number(cap_h) > 0)) bad(`capacity_monthly: bad cap_h: ${cap_h}`);
    capMonthlyCount.set(`${m}|${pool}`, (capMonthlyCount.get(`${m}|${pool}`) || 0) + 1);
  }
  // completeness: exactly one capacity_monthly row per pool per month of that
  // pool's own monthly (hour) table -- an empty/partial capacity_monthly
  // otherwise passes silently.
  for (const m of monthsCpu) {
    const cnt = capMonthlyCount.get(`${m}|cpu`) || 0;
    if (cnt !== 1) bad(`capacity_monthly: expected exactly 1 row for month ${m} / pool cpu, found ${cnt}`);
  }
  for (const m of monthsGpu) {
    const cnt = capMonthlyCount.get(`${m}|gpu`) || 0;
    if (cnt !== 1) bad(`capacity_monthly: expected exactly 1 row for month ${m} / pool gpu, found ${cnt}`);
  }

  // ---- weekly: [monday, pool, held_h] (contract v4, R6.3/R6.4) ----
  // The expected Monday list per pool is derived from that pool's OWN published
  // months: first Monday >= first day of its first month .. last Monday whose
  // Sunday <= last day of its last month, every 7 days. Dense and bounded: each
  // expected week exactly once, nothing outside. All arithmetic in UTC.
  const DAY = 86400000;
  const utcDate = (s) => Date.parse(s + 'T00:00:00Z');
  const ymd = (t) => new Date(t).toISOString().slice(0, 10);
  const expectedMondays = (months) => {
    const ms = [...months].sort();
    if (!ms.length) return [];
    const [y0, m0] = ms[0].split('-').map(Number), [y1, m1] = ms[ms.length - 1].split('-').map(Number);
    let first = Date.UTC(y0, m0 - 1, 1);
    const last = Date.UTC(y1, m1, 0);                              // day 0 of the following month = last day of m1
    while (new Date(first).getUTCDay() !== 1) first += DAY;
    let lastMon = last - 6 * DAY;
    while (new Date(lastMon).getUTCDay() !== 1) lastMon -= DAY;
    const out = [];
    for (let t = first; t <= lastMon; t += 7 * DAY) out.push(ymd(t));
    return out;
  };
  const weeklySeen = new Map();
  const weeklyHeld = { cpu: 0, gpu: 0 };
  for (const row of data.weekly || []) {
    if (row.length !== 3) { bad(`weekly: row length ${row.length} != 3`); continue; }
    const [monday, pool, held_h] = row;
    if (!POOLS.has(pool)) bad(`weekly: unknown pool: ${pool}`);
    if (!DATE.test(monday) || !Number.isFinite(utcDate(monday))) bad(`weekly: bad date: ${monday}`);
    else if (new Date(utcDate(monday)).getUTCDay() !== 1) bad(`weekly: not a Monday: ${monday}`);
    if (!(Number.isFinite(Number(held_h)) && Number(held_h) >= 0)) bad(`weekly: bad held_h: ${held_h}`);
    else if (POOLS.has(pool)) weeklyHeld[pool] += Number(held_h);
    weeklySeen.set(`${monday}|${pool}`, (weeklySeen.get(`${monday}|${pool}`) || 0) + 1);
  }
  for (const [pool, months] of [['cpu', meta.months_cpu || []], ['gpu', meta.months_gpu || []]]) {
    const expected = new Set(expectedMondays(months));
    for (const mon of expected) {
      const cnt = weeklySeen.get(`${mon}|${pool}`) || 0;
      if (cnt !== 1) bad(`weekly: expected exactly 1 row for week ${mon} / pool ${pool}, found ${cnt}`);
    }
    for (const key of weeklySeen.keys()) {
      const [mon, p] = key.split('|');
      if (p === pool && !expected.has(mon)) bad(`weekly: week ${mon} / pool ${pool} lies outside that pool's published months`);
    }
  }
  // sanity: per pool, Σ weekly held_h within 5% of Σ monthly held_h. The dropped
  // edge days (a partial first/last week) are <= 2% of a year-plus record; a
  // wrong column or grain is far off.
  const monthlyHeld = (rows) => (rows || []).reduce((s, r) => s + Number(r[2]), 0);
  for (const [pool, rows] of [['cpu', data.cpu_monthly], ['gpu', data.gpu_monthly]]) {
    const m = monthlyHeld(rows);
    if (m > 0 && Math.abs(weeklyHeld[pool] - m) / m > 0.05)
      bad(`weekly: ${pool} Σheld_h ${weeklyHeld[pool]} is more than 5% off the monthly Σheld_h ${m}`);
  }

  // ---- headline ----
  const HEADLINE_KEYS = ['cpu_core_h', 'gpu_h', 'jobs'];
  for (const k of Object.keys(data.headline || {})) if (!HEADLINE_KEYS.includes(k)) bad(`unexpected headline key: ${k}`);
  for (const k of HEADLINE_KEYS) if (!(k in (data.headline || {}))) bad(`missing headline.${k}`);

  // ---- 3. conservation: headline must equal window3's slice of the monthly tables --
  const TOL = 0.1;   // per-class rounding in cpu_monthly/gpu_monthly vs the direct headline sum
  // held_h always sits at index 2 (contract v2: [month, class, held_h, ...]); njobs'
  // index depends on the row's width (it isn't last in cpu_monthly's field order).
  const sumWindow = (rows, njobsIdx) => {
    let held = 0, njobs = 0;
    for (const row of rows || []) {
      if (window3.has(row[0])) { held += Number(row[2]); njobs += Number(row[njobsIdx]); }
    }
    return { held, njobs };
  };
  const cpuSum = sumWindow(data.cpu_monthly, 2 + CPU_NUM_FIELDS.indexOf('njobs'));
  const gpuSum = sumWindow(data.gpu_monthly, 2 + GPU_NUM_FIELDS.indexOf('njobs'));
  const h = data.headline || {};
  // Number.isFinite guard first: Number(NaN-ish) > TOL is false, so an unguarded
  // Math.abs(...) > TOL would silently pass a non-numeric headline value instead
  // of flagging it (matches the finite check monthlyCheck already does above).
  const closeEnough = (recomputed, val) => Number.isFinite(Number(val)) && Math.abs(recomputed - Number(val)) <= TOL;
  if (!closeEnough(cpuSum.held, h.cpu_core_h))
    bad(`conservation: cpu_core_h: recomputed ${cpuSum.held} != headline ${h.cpu_core_h}`);
  if (!closeEnough(gpuSum.held, h.gpu_h))
    bad(`conservation: gpu_h: recomputed ${gpuSum.held} != headline ${h.gpu_h}`);
  if (cpuSum.njobs + gpuSum.njobs !== Number(h.jobs))
    bad(`conservation: jobs: recomputed ${cpuSum.njobs + gpuSum.njobs} != headline ${h.jobs}`);
}

// ---- 2. blocklist scan (json text + optional built html) ----------------
const texts = [['cluster_data.json', rawText ?? '']];
if (htmlPath) {
  if (!existsSync(htmlPath)) bad(`html not found: ${htmlPath}`);
  else texts.push(['html', readFileSync(htmlPath, 'utf8')]);
}
const esc = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
// single-pass HTML entity decode (named + numeric/hex) so a value present only
// as e.g. "fixture &amp; co" isn't invisible to the leak scan below. Single
// pass avoids double-decoding an already-escaped ampersand.
const ENTITY_MAP = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'" };
const decodeEntities = (s) => s.replace(/&(#x[0-9a-fA-F]+|#[0-9]+|[a-zA-Z]+);/g, (m, ent) => {
  if (ent[0] === '#') {
    const code = (ent[1] === 'x' || ent[1] === 'X') ? parseInt(ent.slice(2), 16) : parseInt(ent.slice(1), 10);
    return Number.isFinite(code) ? String.fromCodePoint(code) : m;
  }
  const key = ent.toLowerCase();
  return key in ENTITY_MAP ? ENTITY_MAP[key] : m;
});
// a leak hit never echoes the matched value, but appends a short local
// reference (first 6 hex chars of its sha1) an operator can grep their own
// copy of the internal emits for.
const ref = (s) => createHash('sha1').update(s).digest('hex').slice(0, 6);
const leakScan = (list, label, category, ...texts2) => {
  for (const val of list) {
    if (texts2.some((t) => new RegExp(`\\b${esc(val)}\\b`, 'i').test(t))) {
      bad(`${label}: leaked ${category} (internal-emit leak check, ref ${ref(val)})`);
      return;
    }
  }
};
for (const [label, text] of texts) {
  const uCode = text.match(/\bu-\d+\b/);
  if (uCode) bad(`${label}: registry code pattern found: ${uCode[0]}`);
  const sccCode = text.match(/\bscc-[a-z0-9]+\b/i);
  if (sccCode) bad(`${label}: scc host pattern found: ${sccCode[0]}`);
  for (const hst of HOSTNAMES)
    if (new RegExp(`\\b${esc(hst)}\\b`, 'i').test(text)) bad(`${label}: real hostname found: ${hst}`);
  // contract v3: every user code / project name from both internal emits, never
  // echoed; scans the raw text and an entity-decoded copy so an HTML-escaped
  // occurrence (e.g. a project name containing "&" rendered as "&amp;") can't hide.
  const decoded = decodeEntities(text);
  leakScan(LEAK_USER_CODES, label, 'user code', text, decoded);
  leakScan(LEAK_PROJECT_NAMES, label, 'project name', text, decoded);
}

if (errs.length) {
  for (const e of errs) console.error('gate_cluster: FAIL ' + e);
  process.exit(1);
}
console.log(`gate_cluster: PASS — cpu_monthly ${data.cpu_monthly.length} / gpu_monthly ${data.gpu_monthly.length} rows, community ${data.community.length} / capacity_monthly ${data.capacity_monthly.length} rows, weekly ${data.weekly.length} rows${htmlPath ? ', html scanned' : ''}`);
