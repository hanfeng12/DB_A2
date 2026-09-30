# NextGen Retail — integrated retail prototype

A working PostgreSQL 15 prototype for UTS 32113 Assignment 2, extending the **NextGen Retail Co.** case in Assignment 1: fragmented POS, e-commerce and outsourced warehouse product, price, inventory and movement data.

## Run in the provided lab

Prerequisites: the existing course Docker environment is running (`student-postgres`, PostgreSQL 15), Docker CLI, and Python 3.10+. No Python packages, npm install or external web services are required by the runner/dashboard.

From this directory:

```bash
python3 scripts/prototype.py all
python3 scripts/prototype.py serve
```

Open **http://127.0.0.1:8765**. Alternatively, open `dashboard/index.html` directly for the last exported snapshot. The dashboard is a local static report; rerun `etl` then reload the page to refresh it.

```bash
python3 scripts/prototype.py build   # create/seed dedicated DBs, define ETL/views, run one batch
python3 scripts/prototype.py test    # execute real integration checks; restore source test changes
python3 scripts/prototype.py etl     # refresh warehouse and exported dashboard/CSV files
python3 scripts/prototype.py export  # export current reporting views without refreshing sources
```

The four dedicated databases are `nextgen_pos`, `nextgen_ecom`, `nextgen_wms` and `nextgen_dw`. Existing `lab` coursework, Neo4j and ClickHouse data are not modified. Database creation and foreign imports use psql commands in `00_databases.sql` and `06_fdw.sql`; the runner handles these. All other SQL files are ordinary PostgreSQL SQL.

The runner defaults to container `student-postgres`, DB user `student`, and initial connection database `lab`. `NEXTGEN_PG_CONTAINER` can select a different container. The FDW setup assumes the course `student` role and reads `POSTGRES_PASSWORD` from inside that PostgreSQL container; no password is stored in the repository. This is a local coursework deployment, not a production access-control setup.

## What is implemented

| Assignment requirement | Implementation |
|---|---|
| At least 3 source systems | Independent POS, e-commerce and WMS databases; normalized tables, PK/FK/CHECK constraints |
| At least 1 integrated warehouse | Conformed product/date/channel/location dimensions, four fact tables and source-ID mapping |
| Synthetic data and commented SQL | Deterministic SQL fixtures: 60 products, 12 stores, 2 warehouses, 1,200 POS sales, 900 online orders, 180 transfers |
| SQL extraction / transformation / loading | `postgres_fdw` extraction; temporary staging; canonical SKU/category transformations; SQL function `etl.run` |
| At least 3 reports/dashboard outputs | Price consistency, inventory alignment, transfer exceptions, plus monthly/channel sales |
| End-to-end testing | `tests/integration.py`, actual results in `evidence/test_results.json`, demo instructions in `docs/demo.md` |
| Connection to Assignment 1 | Bounded product/inventory MDM pilot and integration layer, operational relational model, dimensional analytics and snapshot history |

## Inspect through CloudBeaver

At the existing CloudBeaver installation (normally `http://localhost:8978`), create a PostgreSQL connection for each database above using the same host (`postgres` inside the Docker network), port and lab credentials as your existing `lab` connection. Use the course credentials already configured on your machine. Refreshing only `lab` schemas does not show the other databases.

Connect an SQL editor to `nextgen_dw` and run:

```sql
SELECT * FROM dw.product_xref ORDER BY source_system, source_product_id;
SELECT etl.run(DATE '2026-09-30');
SELECT * FROM etl.batch ORDER BY batch_id DESC;
SELECT * FROM reporting.price_comparison ORDER BY sku;
SELECT * FROM reporting.inventory_comparison ORDER BY sku;
SELECT * FROM reporting.transfer_monitor ORDER BY transfer_id;
SELECT * FROM reporting.sales_by_month ORDER BY month, channel;
```

`sql/09_demo_queries.sql` contains a guided query sequence. An ETL run in CloudBeaver updates the warehouse; subsequently run `python3 scripts/prototype.py export` to refresh the static dashboard files.

## Known fixture checks

- SKU001: POS price AUD 100, online price AUD 95; difference AUD 5.
- SKU001: online availability 30, WMS available 22; difference 8 units.
- SKU060: online stock is NULL; reported as `UNKNOWN_ONLINE`, not zero.
- Transfer 18: completed at WMS but has no store receipt.
- Transfer 15: received quantity is 2 units short.
- Transfer 3: completed and reconciled.
- Pending/cancelled online orders never contribute to sales revenue.

## Data and operational semantics

Synthetic transactions cover July–September 2026. The fixture snapshot is **30 September 2026**; this date is intentionally fixed for repeatable results. The UI labels it explicitly. Inventory compares the *same online fulfilment pool*: WMS on-hand minus reserved stock, not all stores' stock. Price differences are list-price comparisons, not a claim that all promotions are invalid.

A warehouse refresh is one transaction with an advisory lock. It updates product mappings, fully refreshes mutable sales/transfer facts, replaces same-date price/inventory snapshots and preserves prior dates. Business counts and amounts are idempotent; audit batch IDs and internal fact IDs change on refresh. Failed batches roll back warehouse changes. FDW gives a consistent snapshot per source transaction, not a globally synchronized distributed snapshot across all three source DBs.

The prototype detects discrepancies; it does not write corrective prices/stock back to sources. Product descriptions use a documented POS precedence rule, not fuzzy identity matching. Full Data Fabric, Data Mesh, Lakehouse, Graph and Data Vault platforms remain architectural discussion/future scope. This implementation demonstrates an appropriate limited subset of Assignment 1, not those entire enterprise platforms.

## Repository map

- `sql/`: ordered DDL, fixtures, foreign imports, ETL, reporting views and demo queries.
- `scripts/prototype.py`: build, refresh, test and export runner.
- `dashboard/`: standalone, dependency-free interactive reports and exported synthetic data.
- `tests/`: live PostgreSQL integration checks.
- `evidence/`: actual test output, report CSVs and batch metadata.
- `diagrams/`: editable architecture and ER diagrams.
- `docs/`: design rationale, model grains, requirement traceability and demo guide.

This repository contains the prototype. The group report, teacher-signed meeting minutes, individual contribution records and oral presentation are separate assessment deliverables. Do not treat generated code history as evidence of work personally performed by a particular group member.
