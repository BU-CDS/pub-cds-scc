// test_gate.mjs — fixture test for gate_cluster.mjs.
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

// ---- a clean cluster_data.json fixture, shaped like the real Task-1 output --
const goodData = {
  meta: { updated: '2026-08-31', public: true,
          months_cpu: ['2026-06', '2026-07'], months_gpu: ['2026-06', '2026-07'],
          window6: ['2026-06', '2026-07'] },
  capacity: {
    cpu: { nodes: 2, cores: 52, ram_gb: 1258,
           types: [['Gold-6326', 'PowerEdge R650', 1, 32, 1007], ['E5-2660v3', 'PowerEdge C6320', 1, 20, 251]] },
    gpu: { nodes: 1, gpus: 2, vram_gb: 288,
           types: [['H200', 'PowerEdge R770', 1, 2, 144]] },
  },
  cpu_monthly: [['2026-06', 'standard', 100, 10], ['2026-06', 'm1024', 50, 5],
                ['2026-07', 'standard', 110, 11], ['2026-07', 'm1024', 60, 6]],
  gpu_monthly: [['2026-06', 'H200', 200, 20], ['2026-07', 'H200', 210, 21]],
  headline: { cpu_core_h: 320, gpu_h: 410, jobs: 73 },   // 100+50+110+60=320; 200+210=410; 10+5+11+6+20+21=73
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

bad = clone(goodData); bad.cpu_monthly[0][1] = 'gpuheavy';
assert(run(bad) === 1, 'unknown node_class fails'); pass('unknown node_class fails');

bad = clone(goodData); bad.extra_key = 1;
assert(run(bad) === 1, 'unexpected top-level key fails'); pass('unexpected top-level key fails');

assert(run(goodData, '<html>node scc-fix1 was busy</html>') === 1, 'real hostname in html fails');
pass('real hostname in html fails');

assert(run(goodData, '<html>owned by u-1234</html>') === 1, 'registry code (u-1234) in html fails');
pass('registry code (u-1234) in html fails');

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
