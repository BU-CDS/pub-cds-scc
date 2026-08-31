# Changelog

All notable changes to the public cluster page.

## Unreleased

- **Data layer: strip + combine** (2026-08-31, `scripts/50_cluster_data.R`,
  `scripts/test_cluster_data.R`): reads the two pool dashboards' emitted data read-only,
  keeps month-grain aggregates for complete months only (hours delivered and job counts by
  hardware type), derives pool capacity from the inventory records, and writes
  `output/cluster_data.json`. Refuses identified or stale input. Fixture-tested (11
  assertions) and verified against the real emits (19 CPU months, 6 GPU months; capacity
  totals hand-checked against the inventory records).
