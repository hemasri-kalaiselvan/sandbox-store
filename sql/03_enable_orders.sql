-- ============================================================
-- sandbox / shop  —  03_enable_orders.sql
-- Lets the storefront (shop.html) WRITE real orders using the
-- public anon key. Run once, AFTER 01_setup.sql + 02_summary.sql.
--
-- SECURITY NOTE: "public insert" is acceptable ONLY because this is
-- a sandbox with fake data. A real store would require the customer
-- to be logged in and check auth.uid() in the policy.
-- ============================================================

-- tag rows by origin so shop-placed data can be told apart / reverted.
-- Existing (preloaded) rows become 'seed'; the shop inserts 'shop'.
alter table orders    add column if not exists source text default 'seed';
alter table customers add column if not exists source text default 'seed';

-- table + sequence privileges for the anon (public API) role
grant insert on customers, orders, order_items to anon;
grant usage, select on all sequences in schema public to anon;

-- allow inserts (reads were already enabled in 01_setup.sql)
drop policy if exists "public insert" on customers;
drop policy if exists "public insert" on orders;
drop policy if exists "public insert" on order_items;
create policy "public insert" on customers   for insert with check (true);
create policy "public insert" on orders       for insert with check (true);
create policy "public insert" on order_items  for insert with check (true);
