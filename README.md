# CDS on the BU SCC — public cluster page

Public, self-contained page for the CDS buy-in pools on the BU Shared
Computing Cluster: the CPU pool and the GPU pool side by side — the hardware
in each (every node and card, drawn at capacity), and usage totals for a
selectable period (default: the trailing three complete months). One
`index.html`, one inline script, no server, no tracking. Updates quarterly.

## View it

**https://cluster.cds.bu.edu/**

Offline copy:

```
git show origin/page:index.html > page.html
```

## Pipeline

`refresh_public.sh` runs the whole thing under a lock and publishes only if
every step is green:

1. `scripts/50_cluster_data.R` — reads the two pool dashboards' already
   de-identified emitted data (read-only; locations via `PUB_CPU_CLONE` /
   `PUB_GPU_CLONE`), keeps month-grain aggregates for complete months, derives
   pool capacity from the inventory records, writes `output/cluster_data.json`.
2. `scripts/gate_cluster.mjs` — whitelist / blocklist / conservation gate over
   that JSON: every model, card, class and period must be on the allow-list,
   no host names or registry codes anywhere, totals must reconcile.
3. `build_cluster_page.R` — renders `index.html` (panels, period selector,
   totals) with the assets embedded.
4. `scripts/test_page.mjs` + `validate.mjs` — structure/containment tests and
   a run of the page's inline script under a DOM shim; the gate runs a second
   time over the built HTML.
5. `deploy.sh` — publishes `index.html` (+ `.nojekyll`, `CNAME`) to the `page`
   branch GitHub Pages serves; refuses any page that reaches outside itself
   or lacks the "updated quarterly" stamp.

## Tests

```
Rscript scripts/test_cluster_data.R
node scripts/test_gate.mjs
node scripts/test_page.mjs
bash scripts/test_deploy.sh
DEPLOY_PUSH=0 ./refresh_public.sh      # full pipeline, nothing pushed
```

Failure alerts go to the address in `config/alert_email` (untracked); with no
such file the pipeline stays silent.
