# pub-cds-scc

Public dashboard of the CDS GPU pool at Boston University's Shared Computing
Cluster: what hardware the pool has, how it is used, and how much capacity is
free. Data updates monthly and covers the trailing six complete months.

View it: https://pub.cds.bu.edu/gpu/

`data/public_data.json` holds the aggregated figures behind the page. No user
or project identifiers appear anywhere in this repository, by construction:
the private build pipeline aggregates them away and a gate refuses any publish
that carries one. Build code is private by design.
