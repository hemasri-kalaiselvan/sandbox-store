# sandbox / shop — SQL

Database build for the e-commerce analytics learning project.
Backend: Supabase (Postgres). Project: **sandbox**.

## Run order (Supabase → SQL Editor → New query → paste → Run)

| # | File | What it does | Re-runnable? |
|---|------|--------------|--------------|
| 1 | `01_setup.sql` | Drops old tables, builds the 5 core tables (star schema), indexes, RLS read policies, then seeds ~4 years of realistic data (~140k orders, ~296k items). | Yes — it resets first. |
| 2 | `02_summary.sql` | Builds the pre-aggregated reporting layer (13 summary tables) the dashboard reads from. | Yes — it drops those first. |
| 3 | `03_enable_orders.sql` | Adds INSERT policies so the storefront (`shop.html`) can place real orders with the anon key. Run once. | Yes — safe to re-run. |

Always run `01` before `02`. Re-running `01` wipes and rebuilds everything, so run `02` again afterwards.

## Expected result after `01`
`products=200, customers=20000, orders≈140000, order_items≈296000, dates 2022→2026`.
Customer distribution is realistic: ~34% never buy, ~26% one-time, ~40% repeat
(with a few high-volume "whale" customers). ~13,000 customers are paying.

## Expected result after `02`
`daily_sales≈1450, category_sales=8, product_sales=200, state_sales=15, customer_stats=20000,
cat_month≈390, state_month≈725, status_month≈150, product_month≈9500, cust_acq_month=49,
rfm_segments=6, payment_month≈245, hour_dow≈100` (13 tables total).

## Tables

Core (raw "fact" layer):
- `categories` — 8 product categories
- `products` — 200 products (price, cost, rating, stock, category)
- `customers` — 20,000 customers (name, email, city, state, signup)
- `orders` — 150,000 orders (customer, date, status, payment, city/state, total)
- `order_items` — ~315,000 line items (order, product, qty, price)

Reporting (pre-aggregated "mart" layer, built by `02`):
- `daily_sales` — one row per day → trends & KPIs
- `category_sales` — one row per category → category breakdown (all-time)
- `product_sales` — one row per product → best/worst sellers
- `state_sales` — one row per state → geographic map (all-time)
- `customer_stats` — one row per customer → CLV, new vs returning
- `cat_month` — one row per (month, category) incl. profit → Category chart (revenue/profit toggle)
- `state_month` — one row per (month, state) → Geographic chart under the global filter
- `status_month` — one row per (month, status) → Funnel/status under the global filter
- `product_month` — one row per (month, product) → period-filtered top products
- `cust_acq_month` — new customers per month → customer acquisition (a period metric)
- `rfm_segments` — one row per RFM segment → customer segmentation
- `payment_month` — one row per (month, payment method) → payment mix under the filter
- `hour_dow` — orders per (weekday, hour) → "when customers shop" heatmap

## Notes
- RLS is ON; all tables have a `public read` policy (sandbox data only — not real user data).
- DB size settles to ~99 MB after autovacuum (a full run briefly shows ~180 MB of temporary dead rows, which Postgres reclaims automatically).
- Data does not grow on its own; only new real orders add rows.
