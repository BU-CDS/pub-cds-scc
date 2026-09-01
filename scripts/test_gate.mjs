// test_gate.mjs — fixture test for gate_cluster.mjs.
//
// Contract v2 (spec Revision R1): cpu_monthly rows widen to
// [month,node_class,held_h,utilized_h,fail_h,wkill_h,njobs,wa_used_h,wa_req_h];
// gpu_monthly rows widen to
// [month,card,held_h,real_h,residle_h,kwh,vram_h,fail_h,wkill_h,njobs];
// meta.window3 (trailing <=3 complete months common to both pools) replaces
// window6; conservation recomputes held_h/njobs over window3.
//
// Run: module load nodejs/20.12.2 && node scripts/test_gate.mjs
import { mkdtempSync, writeFileSync, mkdirSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const SDIR = dirname(fileURLToPath(import.meta.url));
const GATE = join(SDIR, 'gate_cluster.mjs');
const dir = mkdtempSync(join(tmpdir(), 'gate-cluster-'));

// ---- fixture sibling config CSVs (small, disjoint from the real inventories) --
const cpuDir = join(dir, 'cpu-clone'); const gpuDir = join(dir, 'gpu-clone');
mkdirSync(join(cpuDir, 'config'), { recursive: true });
mkdirSync(join(gpuDir, 'config'), { recursive: true });
writeFileSync(join(cpuDir, 'config', 'cds_cpu_inventory.csv'),
  'host,server_model,cpu_type,ncpu,mem_gb,first_seen,install_date,purchase_date,retired,source,note\n' +
  'scc-fix1,PowerEdge R650,Gold-6326,32,1007,2022-01-01,2022-01-01,,,accounting+dmi,\n' +
  'scc-fix2,PowerEdge C6320,E5-2660v3,20,251,2016-01-01,2016-01-01,,,accounting+dmi,\n');
writeFileSync(join(cpuDir, 'config', 'cds_cpu_hosts.csv'),
  'host,node_class,cores,mem_gb\nscc-fix1,standard,32,1007\nscc-fix2,m1024,20,251\n');
writeFileSync(join(gpuDir, 'config', 'gpu_inventory_history.csv'),
  'host,server_model,cpu_type,ncpu,mem_gb,gpu_type,gpus,gpu_mem_gb,first_seen,install_date,purchase_date,retired,source,gpu_compute_capability,note\n' +
  'scc-gfix1,PowerEdge R770,6517P,32,503,H200,2,144,2025-01-01,2025-01-01,,,gpustats+dmi,9.0,\n');
writeFileSync(join(gpuDir, 'config', 'cds_gpu_hosts.csv'),
  'host,gpu_type,gpus,gpu_mem_gb\nscc-gfix1,H200,2,144\n');

// ---- a clean cluster_data.json fixture, shaped like the real contract v2 output --
// cpu_monthly row: [month,node_class,held_h,utilized_h,fail_h,wkill_h,njobs,wa_used_h,wa_req_h]
// gpu_monthly row: [month,card,held_h,real_h,residle_h,kwh,vram_h,fail_h,wkill_h,njobs]
const goodData = {
  meta: { updated: '2026-08-31', public: true,
          months_cpu: ['2026-06', '2026-07'], months_gpu: ['2026-06', '2026-07'],
          window3: ['2026-06', '2026-07'] },
  capacity: {
    cpu: { nodes: 2, cores: 52, ram_gb: 1258,
           types: [['Gold-6326', 'PowerEdge R650', 1, 32, 1007], ['E5-2660v3', 'PowerEdge C6320', 1, 20, 251]] },
    gpu: { nodes: 1, gpus: 2, vram_gb: 288,
           types: [['H200', 'PowerEdge R770', 1, 2, 144]] },
  },
  cpu_monthly: [
    ['2026-06', 'standard', 100, 90, 3, 1, 10, 95, 98],
    ['2026-06', 'm1024',     50, 40, 2, 1,  5, 45, 48],
    ['2026-07', 'standard', 110,100, 4, 2, 11,105,108],
    ['2026-07', 'm1024',     60, 50, 2, 1,  6, 55, 58],
  ],
  gpu_monthly: [
    ['2026-06', 'H200', 200, 150, 8, 300, 180, 3, 1, 20],
    ['2026-07', 'H200', 210, 160, 9, 310, 190, 4, 1, 21],
  ],
  // held_h: cpu 100+50+110+60=320, gpu 200+210=410; jobs: cpu 10+5+11+6=32, gpu 20+21=41 -> 73
  headline: { cpu_core_h: 320, gpu_h: 410, jobs: 73 },
};

const write = (name, obj) => { const p = join(dir, name); writeFileSync(p, JSON.stringify(obj)); return p; };
const run = (dataObj, html) => {
  const args = [GATE, write('cluster_data.json', dataObj)];
  if (html !== undefined) { writeFileSync(join(dir, 'page.html'), html); args.push(join(dir, 'page.html')); }
  const env = { ...process.env, PUB_CPU_CLONE: cpuDir, PUB_GPU_CLONE: gpuDir };
  try { execFileSync('node', args, { env }); return 0; }
  catch (e) { return e.status; }
};
const clone = o => JSON.parse(JSON.stringify(o));
const assert = (cond, msg) => { if (!cond) { console.error('FAIL: ' + msg); process.exit(1); } };
const pass = (msg) => console.log('PASS: ' + msg);

assert(run(goodData) === 0, 'clean json (no html arg) passes'); pass('clean json (no html arg) passes');
assert(run(goodData, '<html>410 gpu-h delivered</html>') === 0, 'clean json + clean html passes'); pass('clean json + clean html passes');

// hostname-shaped placeholder, not a real inventory host (this repo is world-readable;
// a real hostname must never land in it, even as a rejected/bad-path fixture)
let bad = clone(goodData); bad.capacity.cpu.types[0][0] = 'scc-notarealhost';
assert(run(bad) === 1, 'unknown string (hostname-shaped) in json fails'); pass('unknown string (hostname-shaped) in json fails');

bad = clone(goodData); bad.capacity.gpu.types[0][0] = 'RTX4090Ti';
assert(run(bad) === 1, 'unknown gpu card model fails'); pass('unknown model in json fails');

bad = clone(goodData); bad.cpu_monthly[0][0] = '2026-6';
assert(run(bad) === 1, 'non-YYYY-MM period fails'); pass('non-YYYY-MM period fails');

bad = clone(goodData); bad.headline.cpu_core_h = 999;
assert(run(bad) === 1, 'broken conservation sum fails'); pass('broken conservation sum (cpu_core_h) fails');

bad = clone(goodData); bad.headline.jobs = 1;
assert(run(bad) === 1, 'broken conservation sum (jobs) fails'); pass('broken conservation sum (jobs) fails');

bad = clone(goodData); bad.headline.cpu_core_h = 'not-a-number';
assert(run(bad) === 1, 'non-numeric conservation value fails'); pass('non-numeric headline.cpu_core_h fails (not silently NaN-passed)');

bad = clone(goodData); bad.cpu_monthly[0][1] = 'gpuheavy';
assert(run(bad) === 1, 'unknown node_class fails'); pass('unknown node_class fails');

bad = clone(goodData); bad.extra_key = 1;
assert(run(bad) === 1, 'unexpected top-level key fails'); pass('unexpected top-level key fails');

assert(run(goodData, '<html>node scc-fix1 was busy</html>') === 1, 'real hostname in html fails');
pass('real hostname in html fails');

assert(run(goodData, '<html>owned by u-1234</html>') === 1, 'registry code (u-1234) in html fails');
pass('registry code (u-1234) in html fails');

// ---- contract v2: widened-row shape checks ----
bad = clone(goodData); bad.cpu_monthly[0] = bad.cpu_monthly[0].slice(0, 7);
assert(run(bad) === 1, 'cpu_monthly row narrower than 9 elements fails'); pass('cpu_monthly row narrower than 9 elements fails');

bad = clone(goodData); bad.gpu_monthly[0] = bad.gpu_monthly[0].slice(0, 8);
assert(run(bad) === 1, 'gpu_monthly row narrower than 10 elements fails'); pass('gpu_monthly row narrower than 10 elements fails');

bad = clone(goodData); bad.cpu_monthly[0] = [...bad.cpu_monthly[0], 0];
assert(run(bad) === 1, 'cpu_monthly row wider than 9 elements fails'); pass('cpu_monthly row wider than 9 elements fails');

// ---- contract v2: non-numeric detection per new column ----
bad = clone(goodData); bad.cpu_monthly[0][3] = 'nope';   // utilized_h
assert(run(bad) === 1, 'non-numeric cpu_monthly utilized_h fails'); pass('non-numeric cpu_monthly utilized_h fails');

bad = clone(goodData); bad.cpu_monthly[0][7] = 'nope';   // wa_used_h
assert(run(bad) === 1, 'non-numeric cpu_monthly wa_used_h fails'); pass('non-numeric cpu_monthly wa_used_h fails');

bad = clone(goodData); bad.gpu_monthly[0][5] = 'nope';   // kwh
assert(run(bad) === 1, 'non-numeric gpu_monthly kwh fails'); pass('non-numeric gpu_monthly kwh fails');

bad = clone(goodData); bad.gpu_monthly[0][4] = -1;   // residle_h negative
assert(run(bad) === 1, 'negative gpu_monthly residle_h fails'); pass('negative gpu_monthly residle_h fails');

// ---- contract v2: meta.window3 replaces window6 ----
bad = clone(goodData); bad.meta.window6 = bad.meta.window3; delete bad.meta.window3;
assert(run(bad) === 1, 'meta.window6 (old v1 key) fails: window3 required'); pass('meta.window6 (old v1 key) fails: window3 required');

bad = clone(goodData); bad.meta.window3 = ['2026-01', '2026-02', '2026-03', '2026-04'];
assert(run(bad) === 1, 'meta.window3 with more than 3 months fails'); pass('meta.window3 with more than 3 months fails');

// ---- contract v2: conservation recomputed over window3 from the widened rows ----
bad = clone(goodData); bad.gpu_monthly[0][2] = 999;   // held_h tampered -> breaks conservation
assert(run(bad) === 1, 'tampered gpu_monthly held_h breaks conservation'); pass('tampered gpu_monthly held_h breaks conservation');

bad = clone(goodData); bad.cpu_monthly[0][6] = 999;   // njobs tampered -> breaks conservation
assert(run(bad) === 1, 'tampered cpu_monthly njobs breaks conservation'); pass('tampered cpu_monthly njobs breaks conservation');

// fail-closed on unreadable json input
{
  const args = [GATE, join(dir, 'does-not-exist.json')];
  const env = { ...process.env, PUB_CPU_CLONE: cpuDir, PUB_GPU_CLONE: gpuDir };
  let status = 0;
  try { execFileSync('node', args, { env }); } catch (e) { status = e.status; }
  assert(status === 1, 'unreadable json input fails closed (exit 1, not a crash)');
  pass('unreadable json input fails closed');
}

console.log('ALL PASS');
