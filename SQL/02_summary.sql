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
  coalesce(sum(oi.quantity), 0)                          as units_sold,
  coalesce(round(sum(oi.quantity * oi.price), 2), 0)     as revenue,
  coalesce(round(sum(oi.quantity * (oi.price - p.cost)), 2), 0) as profit
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

-- ---------- indexes for fast dashboard reads ----------
create index idx_daily_day        on daily_sales(day);
create index idx_catsales_rev     on category_sales(revenue);
create index idx_prodsales_rev    on product_sales(revenue);
create index idx_statesales_rev   on state_sales(revenue);
create index idx_custstats_ltv    on customer_stats(lifetime_value);

-- ---------- RLS: open these for public read (dashboard) ----------
alter table daily_sales    enable row level security;
alter table category_sales enable row level security;
alter table product_sales  enable row level security;
alter table state_sales    enable row level security;
alter table customer_stats enable row level security;
create policy "public read" on daily_sales    for select using (true);
create policy "public read" on category_sales for select using (true);
create policy "public read" on product_sales  for select using (true);
create policy "public read" on state_sales    for select using (true);
create policy "public read" on customer_stats for select using (true);

-- ---------- VERIFY ----------
select 'daily_sales'    as summary, count(*) as rows from daily_sales
union all select 'category_sales', count(*) from category_sales
union all select 'product_sales',  count(*) from product_sales
union all select 'state_sales',    count(*) from state_sales
union all select 'customer_stats', count(*) from customer_stats;
