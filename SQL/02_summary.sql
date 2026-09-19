-- ============================================================
-- sandbox / shop  —  02_summary.sql  (STEP 2 of 2: reporting layer)
-- Pre-aggregated "reporting layer" that the dashboard reads from.
-- Run AFTER 01_setup.sql. Safe to re-run any time (drops first).
--
-- CONCEPT: the dashboard asks the same aggregate questions
-- repeatedly. We compute them ONCE here into small tables, so the
-- app reads a few thousand summarized rows instead of scanning
-- 150k orders + 315k items on every load. This is "pre-aggregation"
-- (a.k.a. building a data mart on top of the star schema).
--
-- Revenue convention: we count revenue from orders that were NOT
-- cancelled/returned (i.e. status in shipped/processing/delivered),
-- matching how a real store books realized sales. Adjust if you like.
-- ============================================================

set statement_timeout = '600s';

drop table if exists daily_sales    cascade;
drop table if exists category_sales cascade;
drop table if exists product_sales  cascade;
drop table if exists state_sales    cascade;
drop table if exists customer_stats cascade;

-- ---------- daily_sales: one row per day ----------
-- Powers: revenue trend, order-count trend, AOV, headline KPIs.
create table daily_sales as
select
  o.order_date::date                         as day,
  count(*)                                    as orders,
  count(*) filter (where o.status not in ('cancelled','returned')) as valid_orders,
  round(sum(o.total) filter (where o.status not in ('cancelled','returned')), 2) as revenue,
  count(*) filter (where o.status = 'cancelled') as cancelled,
  count(*) filter (where o.status = 'returned')  as returned
from orders o
group by o.order_date::date;

-- ---------- category_sales: one row per category ----------
-- Powers: category revenue breakdown, category share, profit by category.
create table category_sales as
select
  c.id                        as category_id,
  c.name                      as category,
  count(distinct o.id)        as orders,
  sum(oi.quantity)            as units,
  round(sum(oi.quantity * oi.price), 2)                as revenue,
  round(sum(oi.quantity * (oi.price - p.cost)), 2)     as profit
from order_items oi
join orders   o on o.id = oi.order_id and o.status not in ('cancelled','returned')
join products p on p.id = oi.product_id
join categories c on c.id = p.category_id
group by c.id, c.name;

-- ---------- product_sales: one row per product ----------
-- Powers: best sellers, worst performers, revenue per product, stock view.
create table product_sales as
select
  p.id                        as product_id,
  p.name                      as product,
  c.name                      as category,
  p.price,
  p.rating,
  p.stock,
  -- FILTER keeps only line items whose order actually matched (not cancelled/returned).
  -- Without it, the LEFT JOIN keeps those items and over-counts revenue.
  coalesce(sum(oi.quantity) filter (where o.id is not null), 0)                          as units_sold,
  coalesce(round(sum(oi.quantity * oi.price) filter (where o.id is not null), 2), 0)     as revenue,
  coalesce(round(sum(oi.quantity * (oi.price - p.cost)) filter (where o.id is not null), 2), 0) as profit
from products p
join categories c on c.id = p.category_id
left join order_items oi on oi.product_id = p.id
left join orders o on o.id = oi.order_id and o.status not in ('cancelled','returned')
group by p.id, p.name, c.name, p.price, p.rating, p.stock;

-- ---------- state_sales: one row per state ----------
-- Powers: geographic map / regional performance.
create table state_sales as
select
  o.state,
  count(*)                                             as orders,
  round(sum(o.total) filter (where o.status not in ('cancelled','returned')), 2) as revenue,
  count(distinct o.customer_id)                        as customers
from orders o
group by o.state;

-- ---------- customer_stats: one row per customer ----------
-- Powers: new vs returning, top customers, customer lifetime value (CLV).
create table customer_stats as
select
  cu.id                        as customer_id,
  cu.name,
  cu.city,
  cu.state,
  count(o.id)                                          as orders,
  round(coalesce(sum(o.total) filter (where o.status not in ('cancelled','returned')), 0), 2) as lifetime_value,
  min(o.order_date)::date                              as first_order,
  max(o.order_date)::date                              as last_order
from customers cu
left join orders o on o.customer_id = cu.id
group by cu.id, cu.name, cu.city, cu.state;

-- ============================================================
-- MONTH-GRAIN summaries — power the GLOBAL DATE FILTER.
-- These keep the DATE (month) dimension so the dashboard can
-- re-aggregate any period in the browser. Tiny (a few hundred rows).
-- ============================================================
drop table if exists cat_month    cascade;
drop table if exists state_month  cascade;
drop table if exists status_month cascade;

-- revenue per (month, category)  -> drives Category chart when filtered
create table cat_month as
select date_trunc('month', o.order_date)::date as month,
       c.name                                  as category,
       count(distinct o.id)                    as orders,
       sum(oi.quantity)                        as units,
       round(sum(oi.quantity * oi.price), 2)   as revenue
from order_items oi
join orders   o on o.id = oi.order_id and o.status not in ('cancelled','returned')
join products p on p.id = oi.product_id
join categories c on c.id = p.category_id
group by 1, 2;

-- revenue per (month, state)  -> drives Geographic chart when filtered
create table state_month as
select date_trunc('month', order_date)::date as month,
       state,
       count(*) filter (where status not in ('cancelled','returned')) as orders,
       round(sum(total) filter (where status not in ('cancelled','returned')), 2) as revenue
from orders
group by 1, 2;

-- order count per (month, status)  -> drives Funnel/status when filtered
create table status_month as
select date_trunc('month', order_date)::date as month,
       status,
       count(*) as orders
from orders
group by 1, 2;

-- revenue per (month, product)  -> drives period-filtered "top products"
drop table if exists product_month cascade;
create table product_month as
select date_trunc('month', o.order_date)::date as month,
       p.id                                     as product_id,
       p.name                                   as product,
       c.name                                   as category,
       sum(oi.quantity)                         as units,
       round(sum(oi.quantity * oi.price), 2)    as revenue
from order_items oi
join orders   o on o.id = oi.order_id and o.status not in ('cancelled','returned')
join products p on p.id = oi.product_id
join categories c on c.id = p.category_id
group by 1, 2, 3, 4;

-- new customers per month (acquisition)  -> a PERIOD metric for the customer view
-- (each customer is "new" in exactly one month: the month of their first order)
drop table if exists cust_acq_month cascade;
create table cust_acq_month as
select date_trunc('month', first_order)::date as month,
       count(*) as new_customers
from customer_stats
where first_order is not null
group by 1;

-- ---------- indexes for fast dashboard reads ----------
create index idx_daily_day        on daily_sales(day);
create index idx_catsales_rev     on category_sales(revenue);
create index idx_prodsales_rev    on product_sales(revenue);
create index idx_statesales_rev   on state_sales(revenue);
create index idx_custstats_ltv    on customer_stats(lifetime_value);
create index idx_catmonth         on cat_month(month);
create index idx_statemonth       on state_month(month);
create index idx_statusmonth      on status_month(month);
create index idx_prodmonth        on product_month(month);
create index idx_acqmonth         on cust_acq_month(month);

-- ---------- RLS: open these for public read (dashboard) ----------
alter table daily_sales    enable row level security;
alter table category_sales enable row level security;
alter table product_sales  enable row level security;
alter table state_sales    enable row level security;
alter table customer_stats enable row level security;
alter table cat_month      enable row level security;
alter table state_month    enable row level security;
alter table status_month   enable row level security;
alter table product_month  enable row level security;
alter table cust_acq_month enable row level security;
create policy "public read" on daily_sales    for select using (true);
create policy "public read" on category_sales for select using (true);
create policy "public read" on product_sales  for select using (true);
create policy "public read" on state_sales    for select using (true);
create policy "public read" on customer_stats for select using (true);
create policy "public read" on cat_month      for select using (true);
create policy "public read" on state_month    for select using (true);
create policy "public read" on status_month   for select using (true);
create policy "public read" on product_month  for select using (true);
create policy "public read" on cust_acq_month for select using (true);

-- ---------- VERIFY ----------
select 'daily_sales'    as summary, count(*) as rows from daily_sales
union all select 'category_sales', count(*) from category_sales
union all select 'product_sales',  count(*) from product_sales
union all select 'state_sales',    count(*) from state_sales
union all select 'customer_stats', count(*) from customer_stats
union all select 'cat_month',      count(*) from cat_month
union all select 'state_month',    count(*) from state_month
union all select 'status_month',   count(*) from status_month
union all select 'product_month',  count(*) from product_month
union all select 'cust_acq_month', count(*) from cust_acq_month;
