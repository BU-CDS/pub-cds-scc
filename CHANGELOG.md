# Changelog

All notable changes to the public cluster page.

## Unreleased

- **Data layer: strip + combine** (2026-08-31, `scripts/50_cluster_data.R`,
  `scripts/test_cluster_data.R`): reads the two pool dashboards' emitted data read-only,
  keeps month-grain aggregates for complete months only (hours delivered and job counts by
  hardware type), derives pool capacity from the inventory records, and writes
  `output/cluster_data.json`. Refuses identified or stale input. The monthly and capacity
  tables serialize as typed rows, so numbers land as JSON numbers rather than quoted
  strings. Fixture-tested (12 assertions) and verified against the real emits (19 CPU
  months, 6 GPU months; capacity totals hand-checked against the inventory records).

- **Gate: whitelist/blocklist/conservation for cluster_data** (2026-08-31,
  `scripts/gate_cluster.mjs`, `scripts/test_gate.mjs`): checks `output/cluster_data.json`
  (and, when given a second argument, the built page's HTML) before the whitelist
  is trusted to publish. Whitelists every hardware model, server model, card, node
  class, and `YYYY-MM` period against the same sibling inventory CSVs the data layer
  reads; blocklist-scans the full text for real hostnames and registry-code patterns;
  recomputes the headline totals from the monthly tables and fails on any mismatch.
  Fails closed on unreadable input. Fixture-tested (12 assertions) and run against the
  real Task-1 output (exit 0).

- **Public page: static zero-JS showcase** (2026-08-31, `build_cluster_page.R`,
  `scripts/test_page.mjs`): assembles `index.html` from `output/cluster_data.json` by
  R string concatenation only -- zero `<script>` anywhere, one light theme (no
  `data-theme`, no `localStorage`, no `prefers-color-scheme`), tooltips are `title=`
  attributes. Renders the header lockup (plate + school name), a headline band
  (cores / GPUs / core-hours / GPU-hours / jobs), one hardware section per pool (one
  card per hardware type with a row of node-count squares; CPU model codes render
  human-readably, e.g. `Gold-6242` -> "Xeon Gold 6242"; GPU cards spell out
  "GB each" since the same VRAM figure is per-node for CPU but per-GPU for GPU),
  and a delivered section with two charts -- one bar per month, summed across
  node-class/card -- and sparse January-plus-first-month axis labels. Assets
  (plate, FCDS signature, both Whitney weights) are read from the sibling clone
  and embedded base64, never copied into the tree. Fixture-tested against the
  real Task-1 output (28 assertions covering structure, containment, the
  per-GPU VRAM qualifier, and the de-id blocklist) and run through
  `gate_cluster.mjs` with the built page (exit 0). `index.html` is 218 KB,
  dominated by the embedded assets.
