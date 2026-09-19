# Sandbox Store — E-commerce Analytics Dashboard

A mobile-first, Power BI–style **data-analytics dashboard** built on a realistic
e-commerce dataset. Made as a learning project to explore how analytics
dashboards (like Amazon's / Flipkart's seller dashboards) actually work.

- **Frontend:** a single, self-contained `index.html` (HTML + CSS + vanilla JS + Chart.js)
- **Backend:** [Supabase](https://supabase.com) (hosted PostgreSQL + auto REST API) — free tier
- **Data:** ~140,000 orders across 4 years (2022–2026), generated in SQL — realistic
  growth, festival spikes, order-status funnel, geography, and customer behaviour
- **Hosting:** works offline by double-clicking `index.html`, or live on GitHub Pages

## What it shows

Six analytics sections, each a core "Power BI" concept:

| Section | Concept | Answers |
|---------|---------|---------|
| Overview | Measures / KPIs + time-series | "How's the business, and are we growing?" |
| Category & Products | Dimensional slicing & ranking | "What sells?" |
| Time & Trends | Date filters + period-over-period growth | "Better or worse than before?" |
| Order Status | Funnel analysis | "Where do orders leak?" |
| Geographic | Spatial slicing | "Where are our customers?" |
| Customers | Segmentation + lifetime value | "Who's valuable — new vs returning?" |

## Run it locally

1. Download the repo.
2. Double-click `index.html` — it opens in your browser and connects to the
   Supabase database over the internet.

> The Supabase URL and **anon (public, read-only)** key are embedded in
> `index.html`. That is safe: the anon key is designed to be public, and
> Row Level Security (RLS) allows only reads. All data is generated/fake.

## Rebuild the database from scratch

In the Supabase SQL Editor, run in order:

1. `sql/01_setup.sql` — builds tables + generates ~140k orders of realistic history
2. `sql/02_summary.sql` — builds the pre-aggregated tables the dashboard reads

See `sql/README.md` for details and expected row counts.

## How it was built

A full, step-by-step build journal — every decision, every concept, and the
bugs fixed along the way — is in **[`docs/BUILD_JOURNAL.md`](docs/BUILD_JOURNAL.md)**.

## Project structure

```
sandbox-analytics/
├── index.html              # the whole dashboard (frontend)
├── README.md               # this file
├── docs/
│   └── BUILD_JOURNAL.md    # step-by-step "how I built it"
├── shop.html               # storefront: browse → cart → checkout → place order
└── sql/
    ├── 01_setup.sql        # schema + realistic data generation
    ├── 02_summary.sql      # pre-aggregated reporting tables (13)
    ├── 03_enable_orders.sql# INSERT policies + source tag so shop.html can write
    ├── 04_reset_shop_orders.sql  # revert: delete only shop-placed orders
    └── README.md           # SQL run order + table reference
```

## Store & live data

`shop.html` places **real orders** into `orders` / `order_items`, tagged
`source = 'shop'` (preloaded seed data is `source = 'seed'`). The dashboard's
**"Live · store orders"** card reads those straight from the raw table, so a
purchase shows up immediately. To wipe shop orders and return to pure seed data,
run `sql/04_reset_shop_orders.sql` — it deletes only `source = 'shop'` rows.

## Tech notes

- **Pre-aggregation:** the dashboard reads small summary tables
  (`daily_sales`, `category_sales`, …) instead of scanning 140k+ raw rows on
  every load. This keeps it fast and well under Supabase's free-tier bandwidth.
- **Count-only queries:** status counts and customer segments are fetched with
  `count=exact` + `Range: 0-0`, returning just the number — zero rows downloaded.
- **No build step, no framework:** one HTML file, one CDN script (Chart.js).
