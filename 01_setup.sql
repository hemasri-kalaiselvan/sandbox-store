-- ============================================================
-- sandbox / shop  —  01_setup.sql   (STEP 1 of 2: build the store)
-- E-commerce analytics learning project.
--
-- WHY v2: v1 had 3 bugs where random() inside an UNCORRELATED
-- lateral / join was evaluated only ONCE, collapsing the data:
--   * order dates all landed in a narrow band (not 4 years)
--   * every order got the same/near-same customer
--   * every order got exactly 1 (or exactly 3) items
-- Fix: every per-row random lives in a lateral that references
-- the outer row (g / o.id / n), forcing per-row evaluation.
-- Validated on PostgreSQL 16 before shipping.
--
-- HOW TO RUN: Supabase -> SQL Editor -> New query ->
-- paste this ENTIRE file -> Run. Safe to re-run (it resets first).
-- ============================================================

set statement_timeout = '600s';

-- ========= 0. RESET (re-runnable) =========
drop table if exists order_items cascade;
drop table if exists orders      cascade;
drop table if exists customers   cascade;
drop table if exists products    cascade;
drop table if exists categories  cascade;

-- ========= 1. SCHEMA =========
create table categories (
  id bigint generated always as identity primary key,
  name text not null,
  created_at timestamptz default now()
);

create table products (
  id bigint generated always as identity primary key,
  name text not null,
  category_id bigint references categories(id),
  price numeric(10,2) not null,
  cost  numeric(10,2) not null,
  rating numeric(2,1) default 0,
  stock int default 0,
  created_at timestamptz default now()
);

create table customers (
  id bigint generated always as identity primary key,
  name text not null,
  email text,
  city text,
  state text,
  signup_date timestamptz default now()
);

create table orders (
  id bigint generated always as identity primary key,
  customer_id bigint references customers(id),
  order_date timestamptz not null,
  status text not null,
  payment_method text,
  city text,
  state text,
  total numeric(12,2) not null
);

create table order_items (
  id bigint generated always as identity primary key,
  order_id bigint references orders(id),
  product_id bigint references products(id),
  quantity int not null,
  price numeric(10,2) not null
);

-- ========= indexes =========
create index idx_orders_date     on orders(order_date);
create index idx_orders_status   on orders(status);
create index idx_orders_customer on orders(customer_id);
create index idx_orders_state    on orders(state);
create index idx_items_order     on order_items(order_id);
create index idx_items_product   on order_items(product_id);
create index idx_products_cat    on products(category_id);

-- ========= RLS (read-only for dashboard; sandbox data only) =========
alter table categories  enable row level security;
alter table products    enable row level security;
alter table customers   enable row level security;
alter table orders      enable row level security;
alter table order_items enable row level security;
create policy "public read" on categories  for select using (true);
create policy "public read" on products    for select using (true);
create policy "public read" on customers   for select using (true);
create policy "public read" on orders      for select using (true);
create policy "public read" on order_items for select using (true);

-- ============================================================
-- 2. SEED  (~4 years of realistic history)
-- ============================================================

-- ---------- STEP 1: categories (8) ----------
insert into categories(name) values
('Electronics'),('Fashion'),('Home & Kitchen'),('Beauty & Personal Care'),
('Sports & Fitness'),('Books'),('Grocery'),('Toys & Baby');

-- ---------- STEP 2: products (200) ----------
insert into products(name, category_id, price, cost, rating, stock)
select
  cat.name || ' ' ||
    (array['Pro','Max','Lite','Plus','Air','Ultra','Neo','Prime','Go','Edge',
           'One','Studio','Active','Smart','Classic'])[1+floor(random()*15)::int]
    || ' ' || g,
  cat.id, pr.price,
  round((pr.price * (0.55 + random()*0.25))::numeric, 2),
  round((3.2 + random()*1.8)::numeric, 1),
  floor(random()*500)::int
from generate_series(1,200) g
join lateral (select (1+floor(random()*8))::int as cid, g as gref) c on true
join categories cat on cat.id = c.cid
join lateral (
  select round((
    case cat.id
      when 1 then 1500 + random()*60000
      when 2 then 400  + random()*4000
      when 3 then 300  + random()*8000
      when 4 then 150  + random()*2500
      when 5 then 300  + random()*6000
      when 6 then 120  + random()*900
      when 7 then 40   + random()*1500
      else        200  + random()*3000
    end)::numeric, 2) as price
) pr on true;

-- ---------- STEP 3: customers (20,000) ----------
-- FIX: correlated lateral 'r' (references g) -> per-row names, city, signup
insert into customers(name, email, city, state, signup_date)
select
  (array['Aarav','Vivaan','Aditya','Vihaan','Arjun','Sai','Reyansh','Ayaan','Krishna','Ishaan',
         'Diya','Ananya','Aadhya','Saanvi','Pari','Anika','Navya','Myra','Sara','Kiara'])[r.fn]
    || ' ' ||
  (array['Sharma','Verma','Iyer','Nair','Reddy','Rao','Gupta','Patel','Singh','Khan',
         'Das','Bose','Menon','Pillai','Chopra','Mehta','Joshi','Kulkarni','Naidu','Mishra'])[r.ln],
  'user' || g || '@example.com',
  (array['Mumbai','Delhi','Bengaluru','Hyderabad','Chennai','Kolkata','Pune','Ahmedabad','Jaipur','Lucknow',
         'Kochi','Coimbatore','Chandigarh','Bhopal','Surat','Nagpur','Visakhapatnam','Patna','Indore','Guwahati'])[r.loc],
  (array['Maharashtra','Delhi','Karnataka','Telangana','Tamil Nadu','West Bengal','Maharashtra','Gujarat','Rajasthan','Uttar Pradesh',
         'Kerala','Tamil Nadu','Punjab','Madhya Pradesh','Gujarat','Maharashtra','Andhra Pradesh','Bihar','Madhya Pradesh','Assam'])[r.loc],
  timestamp '2022-09-19' + (1461 * random())::int * interval '1 day'
from generate_series(1,20000) g
cross join lateral (
  select (1+floor(random()*20))::int as fn,
         (1+floor(random()*20))::int as ln,
         (1+floor(random()*20))::int as loc,
         g as gref
) r;

-- ---------- STEP 4: orders (~140k, realistic per-customer counts) ----------
-- Order COUNT per customer follows a realistic heavy-tailed distribution:
--   ~34% never buy, ~26% one-time, ~40% repeat (including a few high-volume
--   "whales"). This is what makes the new-vs-returning analytics meaningful.
-- Order DATES still carry the growth trend + festival (Diwali) spikes:
--   ~20% of orders land in an Oct/Nov festival window, the rest are
--   growth-skewed toward recent years. City/state come from the customer.
-- 'co' = per-customer (random() once per customer -> its order count).
-- 'd'  = per-order (references co.cid + g -> per-order date/status/payment).
insert into orders(customer_id, order_date, status, payment_method, city, state, total)
select
  co.cid, d.ts,
  case
    when d.ts > now() - interval '3 days'  then (array['processing','shipped','processing'])[1+floor(d.sr*3)::int]
    when d.ts > now() - interval '12 days' then (array['shipped','delivered','shipped'])[1+floor(d.sr*3)::int]
    else (array['delivered','delivered','delivered','delivered','delivered',
                'delivered','delivered','delivered','cancelled','returned'])[1+floor(d.sr*10)::int]
  end,
  (array['UPI','UPI','UPI','UPI','Card','Card','COD','COD','Wallet','NetBanking'])[d.pay_i],
  co.city, co.state, 0
from (
  select id as cid, city, state,
    case
      when r < 0.34 then 0                                          -- never buys
      when r < 0.60 then 1                                          -- one-time
      when r < 0.93 then 2 + floor(power(random(),1.8)*10)::int     -- light repeat 2..11
      else 12 + floor(power(random(),2.8)*230)::int                 -- whales 12..241
    end as ncnt
  from (select id, city, state, random() as r from customers) x
) co
cross join lateral generate_series(1, co.ncnt) g
cross join lateral (
  select
    ( case when random() < 0.20
        then (array[date '2022-10-15', date '2023-11-03', date '2024-10-24', date '2025-10-21'])[
               case when random()<0.15 then 1 when random()<0.35 then 2
                    when random()<0.65 then 3 else 4 end]
             + floor(random()*22)::int * interval '1 day'
             + (18+floor(random()*5))::int * interval '1 hour'
             + floor(random()*60)::int * interval '1 minute'
        else timestamp '2022-09-19'
             + (1461 * greatest(random(),random()))::int * interval '1 day'
             + (case when random()<0.5 then 18+floor(random()*5) else 9+floor(random()*9) end)::int * interval '1 hour'
             + floor(random()*60)::int * interval '1 minute'
      end ) as ts,
    (1+floor(random()*10))::int as pay_i,
    random() as sr,
    co.cid, g
) d;

-- ---------- STEP 6: order items (1-3 per order) ----------
-- FIX: correlated lateral 'pk' (references o.id, n) + WHERE filter
insert into order_items(order_id, product_id, quantity, price)
select o.id, pk.pid, pk.qty, p.price
from orders o
cross join generate_series(1,3) n
cross join lateral (
  select (1+floor(random()*200))::int as pid,
         (1+floor(random()*3))::int   as qty,
         random() as keep,
         o.id as oref, n as nref
) pk
join products p on p.id = pk.pid
where n = 1 or pk.keep < 0.55;

-- ---------- STEP 7: compute each order's total from its items ----------
update orders o
set total = s.tot
from (
  select order_id, sum(quantity * price) as tot
  from order_items
  group by order_id
) s
where s.order_id = o.id;

-- ============================================================
-- 3. VERIFY
-- Expect: products=200, orders=150000, order_items ~315000,
--         first_order ~2022-09/10, last_order ~2026-09
-- ============================================================
select
  (select count(*) from categories)  as categories,
  (select count(*) from products)    as products,
  (select count(*) from customers)   as customers,
  (select count(*) from orders)      as orders,
  (select count(*) from order_items) as order_items,
  (select min(order_date)::date from orders) as first_order,
  (select max(order_date)::date from orders) as last_order,
  (select round(sum(total)) from orders where status = 'delivered') as delivered_revenue;

select pg_size_pretty(pg_database_size(current_database())) as db_size;
