# Build Journal — Sandbox Store Analytics Dashboard

A step-by-step record of how this project was built, in the order it happened,
so it can be recollected and repeated later. Each phase notes **what** we did,
**why**, and the **lessons** learned.

---

## Phase 0 — Goal & decisions

**Goal:** learn how a real data-analytics dashboard works (the "Power BI" concept)
by building an e-commerce store whose *real* activity feeds the dashboard.
The store exists to *generate data*; the dashboard is the real subject.

**Key decisions:**
- **Backend = Supabase** (free hosted PostgreSQL + auto-generated REST API + auth).
  Chosen because it gives a genuinely real database for free, no card needed.
  - Free tier: 500 MB database, 5 GB/month egress, 2 projects, auto-pauses after
    7 days idle (one click to wake; data is safe).
- **A dedicated project named `sandbox`** — kept separate from other projects so
  experiments never touch anything important. Many future apps can live here as
  separate *schemas* (drawers) inside one project.
- **Frontend = one static `index.html`** — no framework, so it's simple, free to
  host (GitHub Pages), and can later be wrapped for the Play Store.
- **Data = big preloaded history** (~4 years) so the dashboard looks like a busy
  real store from day one.

**Mental model of a dashboard** (the foundation):
Every dashboard is **measures × dimensions, filtered, shown as visuals**.
- *Measures* = the numbers (revenue, orders, AOV).
- *Dimensions* = ways to slice them (by time, category, product, region, customer).
- *Filters* = controls that narrow the view (date range, category).
- *Visuals* = the charts that display it.

---

## Phase 1 — Database schema (`sql/01_setup.sql`, first half)

Built 5 core tables in a **star schema** (one central "fact" table + surrounding
"dimension" tables):

- `categories` — 8 product categories
- `products` — 200 products (price **and** cost, so we can compute profit)
- `customers` — 20,000 customers (with city/state for geography)
- `orders` — the central fact table (customer, date, status, payment, total)
- `order_items` — line items (which products, quantity, price per order)

Also added:
- **Indexes** on the columns the dashboard filters/sorts by (fast reads).
- **Row Level Security (RLS)** ON, with a `public read` policy on each table.
  RLS is a lock: with it on, the public API key can only do what a policy allows —
  here, read-only. (Public read is fine because the data is fake sandbox data.)

**Lesson:** RLS on + a read policy is the correct, safe pattern for a dashboard.
If a query returns 0 rows unexpectedly, the usual cause is "no read policy yet."

---

## Phase 2 — Generating realistic data (`sql/01_setup.sql`, second half)

Generated the whole history **inside the database** with SQL (fast, free, no
uploads). Built-in realism: growth trend toward recent years, festival (Diwali)
spikes in Oct/Nov, evening shopping peaks, India-style payment mix (UPI-heavy),
geography, and an order-status funnel (delivered / shipped / cancelled / returned).

**This phase had the hardest bugs — all the same root cause:**

> **The "random runs once" trap.** In PostgreSQL, a `random()` call placed inside
> an **uncorrelated** subquery/lateral (one that doesn't reference the outer row)
> can be evaluated **only once** and reused for every row — collapsing the data.

It bit us in **four** places:
1. All order dates landed in a narrow band instead of spanning 4 years.
2. Every order got assigned the same/near-same customer.
3. Every order got exactly 1 (or exactly 3) items.
4. All 200 products landed in a single category.

**The fix:** make every per-row `random()` live in a lateral that **references the
outer row** (e.g. `g`, `o.id`, `n`), which forces per-row evaluation. Example:
```sql
cross join lateral (
  select (1+floor(random()*10))::int as pick, g as gref   -- 'g' forces per-row
) r
```

**Lessons:**
- Test data-generation SQL on real Postgres before trusting it. (We ran it on a
  local PostgreSQL 16 and inspected the actual distributions.)
- Verify realism, not just row counts: check orders-per-year (growth), a festival
  month (spike), distinct categories, geography spread, and the status mix.

**Also learned — database size "bouncing":** right after a big run the DB showed
~180 MB, then settled to ~100 MB minutes later. Cause: an `UPDATE` rewrites rows
and leaves old "dead" copies (MVCC); Postgres's **autovacuum** reclaims them
automatically. The steady-state size is the real one. Data does **not** grow on
its own afterward — only new real orders add (tiny) rows.

---

## Phase 3 — Pre-aggregation / reporting layer (`sql/02_summary.sql`)

The dashboard asks the same aggregate questions repeatedly ("revenue per day",
"sales per category"). Instead of scanning 140k+ raw rows every load, we compute
those once into small **summary tables** — the "how Flipkart makes it fast" trick.

Built 5 summary tables (the dashboard reads only these):
- `daily_sales` — one row per day → trends & KPIs
- `category_sales` — one row per category → category breakdown
- `product_sales` — one row per product → best/worst sellers
- `state_sales` — one row per state → geographic view
- `customer_stats` — one row per customer → CLV, new vs returning

**Concept:** this is *pre-aggregation* — building a fast "reporting/mart" layer on
top of the raw "fact" layer. It also keeps us far under the free-tier bandwidth
limit, because the app ships tiny summarized rows instead of raw data.

**Bug found here:** `category_sales` returned only 1 row → traced back to the
Phase-2 product-category bug (all products in one category). Fixed the seed and
re-ran. **Lesson:** a summary table is a great correctness check on the raw data.

---

## Phase 4 — Connecting the dashboard to the data

From Supabase **Settings → API**, took two values:
- **Project URL** (`https://<ref>.supabase.co`)
- **anon public key** (safe to embed — public by design, read-only via RLS)

> Never use the `service_role` / secret key in a web page — it bypasses RLS.

The dashboard calls Supabase's **auto-generated REST API** directly with `fetch()`
(e.g. `GET /rest/v1/daily_sales?select=...`). No backend code of our own needed.

**Techniques used:**
- **Pagination** past Supabase's 1000-row response cap (loop with a `Range` header).
- **Count-only requests** (`Prefer: count=exact` + `Range: 0-0`) to get totals
  without downloading rows — used for status counts and customer segments.

---

## Phase 5 — Building the dashboard, one concept at a time (`index.html`)

Mobile-first single-page app (phone-width shell + bottom nav). Charts via Chart.js
(one free CDN script). Built section by section, each teaching one concept:

1. **Overview — measures & time-series.** KPI cards (Revenue, Orders, AOV,
   Customers) + a monthly revenue trend line. *"How's the business, are we growing?"*
2. **Category & Products — dimensional slicing + ranking.** Revenue-by-category bar
   + best-selling products. *Insight:* top sellers are all Electronics because
   they're expensive — revenue leaders ≠ volume leaders.
3. **Time & Trends — filtering + period-over-period comparison.** Date chips
   (30d / 90d / 12m / YTD / All) recompute KPIs and show growth % vs the previous
   period; the trend chart switches daily↔monthly by range. *All computed in the
   browser from `daily_sales` — no extra DB load.*
4. **Order Status — funnel analysis.** Delivery / cancellation / return rates,
   a Placed→Confirmed→Delivered funnel, and a status donut. *"Where do orders leak?"*
5. **Geographic — spatial slicing.** Revenue by state (ranked bars) + top-state
   share. *Chose ranked bars over a map: easier to read exact values on a phone,
   and no heavy map library.*
6. **Customers — segmentation + lifetime value.** Repeat rate, avg CLV, a
   new-vs-returning donut, and top customers by lifetime value.

**Design choices:** started dark, switched to a **light** business-dashboard theme
on request. Categorical colours are assigned by *meaning* (a fixed colour per
category), not a rainbow-by-order.

---

## Phase 6 — Making customer data realistic

The first customer view showed **98% repeat buyers** and ~0 "never purchased" —
unrealistic. Cause: spreading 150k orders randomly across 20k people made almost
everyone a repeat buyer (~7.5 orders each).

**Fix:** decide each customer's **order count** from a realistic heavy-tailed
distribution, *then* generate that many orders — while keeping growth + festival
spikes in the dates. Result (validated on real Postgres):
- ~**34% never buy**, ~**26% one-time**, ~**40% repeat** (incl. a few "whale"
  customers with 100s of orders).
- ~140k orders total, ~13k paying customers, DB ~100 MB.

**Lesson:** per-order random assignment can't produce one-time buyers when order
volume is high; controlling the *count per customer* directly is the right model
(and matches how real retail is heavy-tailed — a few customers drive most orders).

---

## Phase 7 — Global filters (the capstone)

A real dashboard has **one filter that drives every chart at once** — change the
period and revenue, categories, geography, and the funnel all update together.
That's what makes it a *report*, not a pile of separate charts.

**The catch (and the lesson):** the all-time summary tables (`category_sales`,
etc.) have already collapsed the date dimension — you can't ask them "categories
for 2025." To filter by date across sections, the summaries must **keep the date
dimension**. So we added small **month-grain** tables in `02_summary.sql`:
- `cat_month` (month × category), `state_month` (month × state),
  `status_month` (month × status) — a few hundred rows each.

The dashboard fetches these once and **re-aggregates them in the browser** for
whatever period is selected (All time / Last 12 months / This year / Last year).
A global chip bar at the top drives Overview, Category, Geographic, and Funnel
together. Products and Customers stay all-time (they'd each need their own
date-grained table — a good next extension).

**Lesson:** interactive filtering is enabled by aggregating at *the right grain* —
one that still contains the dimensions you want to filter and slice by. This is
the core idea behind a star schema / OLAP cube.

### 7b — Extending the filter to Products & Customers
- Added `product_month` (month × product) so **top sellers re-rank per period**.
- Added `cust_acq_month` (new customers per month) so the customer view gains a
  **period metric: customer acquisition**.
- **Design lesson:** not every metric should be filtered. *Lifetime value* is
  lifetime by definition — filtering it to one month is meaningless. So the
  customer section splits into an **acquisition** block (period-filtered) and a
  **value** block (lifetime, labelled as such).
- **Bug fixed along the way:** `product_sales` over-counted revenue because a
  `LEFT JOIN ... AND status NOT IN (...)` kept cancelled/returned line items in
  the sum. Fixed with `SUM(...) FILTER (WHERE o.id IS NOT NULL)`. Caught by a
  sanity check: its total didn't match `category_sales`; now all product/category
  totals reconcile exactly.

---

## How to rebuild everything from zero

1. Create a Supabase project (any name; we used `sandbox`).
2. SQL Editor → run `sql/01_setup.sql` (schema + ~140k orders). ~30–60s.
3. SQL Editor → run `sql/02_summary.sql` (summary tables).
4. Put the Project URL + anon key into `index.html` (the `CONFIG` block near the
   bottom of the file).
5. Open `index.html` — done.

---

## Data model reference

**Raw (fact) layer**
- `orders(id, customer_id, order_date, status, payment_method, city, state, total)`
- `order_items(id, order_id, product_id, quantity, price)`
- `products(id, name, category_id, price, cost, rating, stock)`
- `customers(id, name, email, city, state, signup_date)`
- `categories(id, name)`

**Reporting (summary) layer** — built by `02_summary.sql`
- `daily_sales(day, orders, valid_orders, revenue, cancelled, returned)`
- `category_sales(category_id, category, orders, units, revenue, profit)`
- `product_sales(product_id, product, category, price, rating, stock, units_sold, revenue, profit)`
- `state_sales(state, orders, revenue, customers)`
- `customer_stats(customer_id, name, city, state, orders, lifetime_value, first_order, last_order)`

Revenue convention: counts orders **not** cancelled/returned (realized sales).

---

## Ideas for next steps

- **Global filters** — one date/category filter that drives *every* section at
  once (true Power BI interactivity).
- **India choropleth map** for the geographic view (optional "wow" factor).
- **A shopping front-end** so real orders flow into the same dashboard.
- **Auto-refresh of summary tables** (a scheduled job) as new orders arrive.
- **Publish to GitHub Pages** for a real phone URL; later, wrap for the Play Store.
