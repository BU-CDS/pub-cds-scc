// gate_cluster.mjs — de-id gate for output/cluster_data.json and the built public
// page. Whitelist first, blocklist second, conservation third. ANY violation
// exits 1 and the pipeline stops before deploy can run. Fails safe: a false
// positive blocks a publish; a miss cannot, because the whitelist rejects every
// string outside the enumerated vocabularies (hardware models, server models,
// cards, node classes, YYYY-MM periods) and the blocklist scans the full text
// for real hostnames and registry codes regardless of where they land.
//
// Usage: node gate_cluster.mjs <cluster_data.json> [built_html]
//   - called before build with just the json (data-layer gate)
//   - called after build with the html too (page gate)
// Vocab + blocklist sources: sibling clones' config/ CSVs (env-overridable,
// same PUB_CPU_CLONE / PUB_GPU_CLONE vars 50_cluster_data.R reads).
import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';

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

const PERIOD = /^\d{4}-\d{2}$/;
const DATE = /^\d{4}-\d{2}-\d{2}$/;

// ---- 1. structural + value whitelist -----------------------------------
let data;
let rawText;
try { rawText = readFileSync(dataPath, 'utf8'); data = JSON.parse(rawText); }
catch (e) { bad(`cannot read/parse ${dataPath}: ${e.message}`); }

if (data) {
  const TOP = ['meta', 'capacity', 'cpu_monthly', 'gpu_monthly', 'headline'];
  for (const k of Object.keys(data)) if (!TOP.includes(k)) bad(`unexpected top-level key: ${k}`);
  for (const k of TOP) if (!(k in data)) bad(`missing top-level key: ${k}`);

  const META_KEYS = ['updated', 'public', 'months_cpu', 'months_gpu', 'window3'];
  const meta = data.meta || {};
  for (const k of Object.keys(meta)) if (!META_KEYS.includes(k)) bad(`unexpected meta key: ${k}`);
  if (!DATE.test(meta.updated)) bad(`meta.updated not YYYY-MM-DD: ${meta.updated}`);
  if (meta.public !== true) bad('meta.public is not true');
  for (const listKey of ['months_cpu', 'months_gpu', 'window3']) {
    for (const m of meta[listKey] || []) if (!PERIOD.test(m)) bad(`meta.${listKey}: bad period: ${m}`);
  }
  const monthsCpu = new Set(meta.months_cpu || []);
  const monthsGpu = new Set(meta.months_gpu || []);
  const window3 = new Set(meta.window3 || []);
  if (window3.size < 1 || window3.size > 3) bad(`meta.window3 has ${window3.size} months (want 1..3)`);

  // ---- capacity ----
  const capCheck = (group, keys, modelSet, serverSet) => {
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
  };
  capCheck('cpu', ['nodes', 'cores', 'ram_gb', 'types'], CPU_MODELS, CPU_SERVERS);
  capCheck('gpu', ['nodes', 'gpus', 'vram_gb', 'types'], CARDS, GPU_SERVERS);

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
for (const [label, text] of texts) {
  const uCode = text.match(/\bu-\d+\b/);
  if (uCode) bad(`${label}: registry code pattern found: ${uCode[0]}`);
  const sccCode = text.match(/\bscc-[a-z0-9]+\b/i);
  if (sccCode) bad(`${label}: scc host pattern found: ${sccCode[0]}`);
  for (const hst of HOSTNAMES)
    if (new RegExp(`\\b${esc(hst)}\\b`, 'i').test(text)) bad(`${label}: real hostname found: ${hst}`);
}

if (errs.length) {
  for (const e of errs) console.error('gate_cluster: FAIL ' + e);
  process.exit(1);
}
console.log(`gate_cluster: PASS — cpu_monthly ${data.cpu_monthly.length} / gpu_monthly ${data.gpu_monthly.length} rows${htmlPath ? ', html scanned' : ''}`);
