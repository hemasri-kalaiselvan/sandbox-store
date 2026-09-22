-- ============================================================
-- sandbox / shop  —  05_schedule_refresh.sql
-- Automatically rebuild the summary tables every day at 3:00 AM IST
-- so new shop orders roll into the historical charts overnight.
--
-- Uses pg_cron (built into Supabase). Run AFTER 01/02/03.
-- Enable the extension first: Supabase -> Database -> Extensions ->
-- search "pg_cron" -> toggle ON. (The line below also tries to enable it.)
-- ============================================================

create extension if not exists pg_cron;

-- ------------------------------------------------------------
-- refresh_summaries(): repopulate all 13 summary tables IN PLACE
-- (truncate + refill inside one transaction, so the dashboard never
-- sees half-built tables and the RLS policies are preserved).
-- ------------------------------------------------------------
create or replace function refresh_summaries() returns void
language plpgsql as $refresh$
begin
  truncate daily_sales, category_sales, product_sales, state_sales, customer_stats,
           cat_month, state_month, status_month, product_month, cust_acq_month,
           rfm_segments, payment_month, hour_dow;

  insert into daily_sales(day,orders,valid_orders,revenue,cancelled,returned)
  select o.order_date::date, count(*),
         count(*) filter (where o.status not in ('cancelled','returned')),
         round(sum(o.total) filter (where o.status not in ('cancelled','returned')),2),
         count(*) filter (where o.status='cancelled'),
         count(*) filter (where o.status='returned')
  from orders o group by o.order_date::date;

  insert into category_sales(category_id,category,orders,units,revenue,profit)
  select c.id,c.name,count(distinct o.id),sum(oi.quantity),
         round(sum(oi.quantity*oi.price),2),
         round(sum(oi.quantity*(oi.price-p.cost)),2)
  from order_items oi
  join orders o on o.id=oi.order_id and o.status not in ('cancelled','returned')
  join products p on p.id=oi.product_id
  join categories c on c.id=p.category_id
  group by c.id,c.name;

  insert into product_sales(product_id,product,category,price,rating,stock,units_sold,revenue,profit)
  select p.id,p.name,c.name,p.price,p.rating,p.stock,
         coalesce(sum(oi.quantity) filter (where o.id is not null),0),
         coalesce(round(sum(oi.quantity*oi.price) filter (where o.id is not null),2),0),
         coalesce(round(sum(oi.quantity*(oi.price-p.cost)) filter (where o.id is not null),2),0)
  from products p
  join categories c on c.id=p.category_id
  left join order_items oi on oi.product_id=p.id
  left join orders o on o.id=oi.order_id and o.status not in ('cancelled','returned')
  group by p.id,p.name,c.name,p.price,p.rating,p.stock;

  insert into state_sales(state,orders,revenue,customers)
  select o.state,count(*),
         round(sum(o.total) filter (where o.status not in ('cancelled','returned')),2),
         count(distinct o.customer_id)
  from orders o group by o.state;

  insert into customer_stats(customer_id,name,city,state,orders,lifetime_value,first_order,last_order)
  select cu.id,cu.name,cu.city,cu.state,count(o.id),
         round(coalesce(sum(o.total) filter (where o.status not in ('cancelled','returned')),0),2),
         min(o.order_date)::date, max(o.order_date)::date
  from customers cu
  left join orders o on o.customer_id=cu.id
  group by cu.id,cu.name,cu.city,cu.state;

  insert into cat_month(month,category,orders,units,revenue,profit)
  select date_trunc('month',o.order_date)::date,c.name,count(distinct o.id),sum(oi.quantity),
         round(sum(oi.quantity*oi.price),2),round(sum(oi.quantity*(oi.price-p.cost)),2)
  from order_items oi
  join orders o on o.id=oi.order_id and o.status not in ('cancelled','returned')
  join products p on p.id=oi.product_id
  join categories c on c.id=p.category_id
  group by 1,2;

  insert into state_month(month,state,orders,revenue)
  select date_trunc('month',order_date)::date,state,
         count(*) filter (where status not in ('cancelled','returned')),
         round(sum(total) filter (where status not in ('cancelled','returned')),2)
  from orders group by 1,2;

  insert into status_month(month,status,orders)
  select date_trunc('month',order_date)::date,status,count(*) from orders group by 1,2;

  insert into product_month(month,product_id,product,category,units,revenue)
  select date_trunc('month',o.order_date)::date,p.id,p.name,c.name,sum(oi.quantity),
         round(sum(oi.quantity*oi.price),2)
  from order_items oi
  join orders o on o.id=oi.order_id and o.status not in ('cancelled','returned')
  join products p on p.id=oi.product_id
  join categories c on c.id=p.category_id
  group by 1,2,3,4;

  insert into cust_acq_month(month,new_customers)
  select date_trunc('month',first_order)::date,count(*)
  from customer_stats where first_order is not null group by 1;

  insert into rfm_segments(segment,customers,revenue,avg_value)
  with scored as (
    select customer_id,lifetime_value,orders,
      ntile(3) over (order by last_order) as r,
      ntile(3) over (order by orders) as f,
      ntile(3) over (order by lifetime_value) as m
    from customer_stats where orders>=1),
  labelled as (
    select *, case
      when r=3 and f=3 then 'Champions' when f=3 then 'Loyal'
      when m=3 then 'Big spenders' when r=3 then 'New / promising'
      when r=1 and f>=2 then 'At risk' else 'Hibernating' end as segment
    from scored)
  select segment,count(*),round(sum(lifetime_value)),round(avg(lifetime_value))
  from labelled group by segment;

  insert into payment_month(month,payment_method,orders,revenue)
  select date_trunc('month',order_date)::date,payment_method,count(*),
         round(sum(total) filter (where status not in ('cancelled','returned')),2)
  from orders group by 1,2;

  insert into hour_dow(dow,hour,orders)
  select extract(dow from order_date)::int,extract(hour from order_date)::int,count(*)
  from orders group by 1,2;
end;
$refresh$;

-- Let the dashboard's "Rebuild history" button call this via the public API.
-- SECURITY DEFINER: the function runs with the owner's rights (so it can
-- truncate/refill), even though the caller is the low-privilege anon role.
alter function refresh_summaries() security definer;
alter function refresh_summaries() set search_path = public;
-- the anon (public API) role has a short statement timeout; the full rebuild
-- needs more, so give THIS function its own generous limit (applies only while
-- it runs). Without this a browser-triggered rebuild fails with error 57014.
alter function refresh_summaries() set statement_timeout to '180s';
grant execute on function refresh_summaries() to anon;

-- ------------------------------------------------------------
-- schedule it: 21:30 UTC daily = 3:00 AM IST
-- (remove any previous job of the same name first, so re-running is safe)
-- ------------------------------------------------------------
do $$ begin perform cron.unschedule('daily-refresh'); exception when others then null; end $$;
select cron.schedule('daily-refresh', '30 21 * * *', 'select refresh_summaries();');

-- see your scheduled job:
select jobid, schedule, command, active from cron.job where jobname='daily-refresh';
