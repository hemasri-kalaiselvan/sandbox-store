-- ============================================================
-- sandbox / shop  —  04_reset_shop_orders.sql
-- REVERT the store: delete ONLY orders placed through shop.html
-- (source = 'shop'). Preloaded seed data (source = 'seed') is untouched.
-- Run in the Supabase SQL Editor whenever you want a clean slate.
-- ============================================================

-- how many will be removed (run alone first if you want to preview)
select
  (select count(*) from orders    where source='shop') as shop_orders,
  (select count(*) from customers where source='shop') as shop_customers;

-- delete children first (order_items), then orders, then the shop customers
delete from order_items
  where order_id in (select id from orders where source='shop');
delete from orders    where source='shop';
delete from customers where source='shop';

-- confirm nothing shop-placed remains
select
  (select count(*) from orders    where source='shop') as shop_orders_left,
  (select count(*) from customers where source='shop') as shop_customers_left;
