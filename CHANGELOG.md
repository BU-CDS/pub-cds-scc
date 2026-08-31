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
