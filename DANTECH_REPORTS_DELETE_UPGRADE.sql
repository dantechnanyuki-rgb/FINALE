-- DANTECH CYBER SOLUTIONS - REPORTING + SAFE ADMIN DELETIONS UPGRADE
-- Run this ONCE in Supabase SQL Editor after the existing setup/migration.
-- It is designed to be safe to rerun.

-- Helpful indexes for date/branch reporting.
create index if not exists sales_report_date_branch_idx on public.sales(sale_date, branch);
create index if not exists misc_sales_report_date_branch_idx on public.misc_sales(sale_date, branch);
create index if not exists expenses_report_date_branch_idx on public.expenses(expense_date, branch);
create index if not exists purchases_report_date_branch_idx on public.purchases(purchase_date, branch);
create index if not exists transfers_report_date_idx on public.transfers(transfer_date);
create index if not exists services_created_at_branch_idx on public.services(created_at, branch);

-- Admin-only sale deletion.
-- If the sale was a stock product sale, its quantity is returned to inventory.
-- Historical sales are removed only when an administrator explicitly confirms deletion.
create or replace function public.delete_sale(p_sale_id uuid)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  s public.sales;
  p public.products;
begin
  if public.my_role() <> 'admin' then
    raise exception 'Admin only';
  end if;

  select * into s from public.sales where id=p_sale_id for update;
  if s.id is null then
    raise exception 'Sale not found';
  end if;

  if s.product_id is not null then
    select * into p from public.products where id=s.product_id for update;
    if p.id is not null then
      update public.products
      set qty=qty+s.quantity
      where id=p.id;
    end if;
  end if;

  delete from public.sales where id=s.id;

  insert into public.activity(user_id,branch,action)
  values(auth.uid(),s.branch,'Deleted sale: '||coalesce(s.item_name,'Unknown item')||' x'||s.quantity);
end;
$$;

revoke all on function public.delete_sale(uuid) from public;
grant execute on function public.delete_sale(uuid) to authenticated;

-- Admin-only miscellaneous-sale deletion.
create or replace function public.delete_misc_sale(p_sale_id uuid)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  s public.misc_sales;
begin
  if public.my_role() <> 'admin' then
    raise exception 'Admin only';
  end if;

  select * into s from public.misc_sales where id=p_sale_id for update;
  if s.id is null then
    raise exception 'Miscellaneous sale not found';
  end if;

  delete from public.misc_sales where id=s.id;

  insert into public.activity(user_id,branch,action)
  values(auth.uid(),s.branch,'Deleted miscellaneous sale: '||coalesce(s.service_name,'Unknown service')||' x'||s.quantity);
end;
$$;

revoke all on function public.delete_misc_sale(uuid) from public;
grant execute on function public.delete_misc_sale(uuid) to authenticated;

-- Admin-only service deletion.
-- Existing historical sales remain intact; only their service_id reference is cleared.
create or replace function public.delete_service(p_service_id uuid)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  s public.services;
begin
  if public.my_role() <> 'admin' then
    raise exception 'Admin only';
  end if;

  select * into s from public.services where id=p_service_id for update;
  if s.id is null then
    raise exception 'Service not found';
  end if;

  update public.sales set service_id=null where service_id=s.id;
  delete from public.services where id=s.id;

  insert into public.activity(user_id,branch,action)
  values(auth.uid(),s.branch,'Deleted service: '||coalesce(s.name,'Unknown service'));
end;
$$;

revoke all on function public.delete_service(uuid) from public;
grant execute on function public.delete_service(uuid) to authenticated;

-- Optional: explicit admin delete policies are also safe to create because they
-- are dropped first. The application uses the RPC functions above for deletion,
-- which keeps stock restoration and historical references controlled.
drop policy if exists "sales admin delete" on public.sales;
create policy "sales admin delete"
on public.sales for delete
using (public.my_role()='admin');

drop policy if exists "misc sales admin delete" on public.misc_sales;
create policy "misc sales admin delete"
on public.misc_sales for delete
using (public.my_role()='admin');

-- Verify the upgrade:
-- select routine_name from information_schema.routines
-- where routine_schema='public' and routine_name in ('delete_sale','delete_misc_sale','delete_service');
