-- ============================================================
-- 07_privilege.sql — region-based access (managers see only their region)
-- Uses Supabase Auth (auth.uid()) + Row Level Security.
-- Run AFTER 01/02. Enable Email auth in Supabase first (Authentication -> Providers).
-- ============================================================

-- who can see what: one row per logged-in user
create table if not exists app_users (
  user_id uuid primary key,            -- = the Supabase Auth user id
  email   text,
  role    text not null default 'manager',   -- 'admin' (all) or 'manager' (one region)
  region  text                                -- state name for a manager; NULL for admin
);
alter table app_users enable row level security;
drop policy if exists "self read" on app_users;
create policy "self read" on app_users for select using (user_id = auth.uid());

-- helpers: the current user's role / region
create or replace function my_role()   returns text language sql stable
  as $$ select role   from app_users where user_id = auth.uid() $$;
create or replace function my_region() returns text language sql stable
  as $$ select region from app_users where user_id = auth.uid() $$;

-- replace public-read with region-scoped read on the state-bearing tables
do $$
declare t text;
begin
  foreach t in array array['orders','customers','state_sales','state_month'] loop
    execute format('drop policy if exists "public read" on %I', t);
    execute format('drop policy if exists "scoped read" on %I', t);
    execute format($f$
      create policy "scoped read" on %I for select
      using ( coalesce(my_role(),'') = 'admin' or state = my_region() )
    $f$, t);
  end loop;
end $$;

-- order_items has no state column -> scope it through its order
drop policy if exists "public read" on order_items;
drop policy if exists "scoped read" on order_items;
create policy "scoped read" on order_items for select using (
  coalesce(my_role(),'') = 'admin'
  or exists (select 1 from orders o where o.id = order_items.order_id and o.state = my_region())
);

-- NOTE: tables without a state (daily_sales, category_sales, product_sales, rfm_segments,
-- cat_month, product_month, status_month, payment_month, hour_dow, cust_acq_month,
-- cohort_retention) stay public-read here. For full per-region coverage a manager
-- dashboard should aggregate from the (now region-scoped) raw `orders` table, or you
-- add region-grained summaries. Admins are unaffected and see everything.

-- ---- after creating a manager in Supabase Auth, map them to a region, e.g.: ----
-- insert into app_users(user_id, email, role, region) values
--   ('<AUTH-USER-UUID>', 'priya@example.com', 'manager', 'Tamil Nadu');
-- insert into app_users(user_id, email, role, region) values
--   ('<YOUR-UUID>', 'you@example.com', 'admin', null);
