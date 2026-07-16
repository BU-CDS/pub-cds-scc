# CDS GPU Pool

Public dashboard of the CDS buy-in GPU pool on the BU Shared Computing Cluster:
the hardware, its utilization, and free capacity. Self-contained `index.html`,
no server. Updates monthly, trailing six complete months.

## View it

**https://cluster.cds.bu.edu/** (until DNS lands: https://bu-cds.github.io/pub-cds-scc/)

Offline copy:

```
git show origin/page:index.html > page.html
```

## Layout

```
page branch: index.html    the dashboard, data inlined
main branch: data/         monthly public_data.json snapshots
```

## De-identification

No usernames, projects, queues, or hostnames anywhere in this repo, by
construction: aggregated away at build, gated before every publish.
Build code lives in the internal repo.
