-- DANTECH CYBER SOLUTIONS - EXISTING DATABASE UPGRADE
-- Run this ONCE in Supabase SQL Editor.
-- Do NOT rerun supabase_schema.sql if your tables/types already exist.

create or replace function public.record_sale(
  p_product_id uuid,
  p_service_id uuid,
  p_item_name text,
  p_quantity integer,
  p_unit_price numeric,
  p_discount numeric,
  p_final_total numeric,
  p_cost_total numeric,
  p_payment_method text,
  p_mpesa_reference text,
  p_branch text,
  p_sale_date date,
  p_user_id uuid
)
returns setof public.sales
language plpgsql
security definer
set search_path=public
as $$
declare
  p public.products;
  s public.services;
  new_sale public.sales;
begin
  if auth.uid() is null or auth.uid() <> p_user_id then
    raise exception 'Invalid user';
  end if;

  if public.my_role() not in ('admin','staff') then
    raise exception 'Not authorised';
  end if;

  if p_quantity is null or p_quantity <= 0 then
    raise exception 'Quantity must be greater than zero';
  end if;

  if p_branch <> public.my_branch() and public.my_role() <> 'admin' then
    raise exception 'Wrong branch';
  end if;

  if p_product_id is not null then
    select * into p from public.products where id=p_product_id for update;
    if p.id is null or p.branch <> p_branch then raise exception 'Product not found in selected branch'; end if;
    if p.qty < p_quantity then raise exception 'Insufficient stock'; end if;
    update public.products set qty=qty-p_quantity where id=p.id;
  elsif p_service_id is not null then
    select * into s from public.services where id=p_service_id;
    if s.id is null or s.branch <> p_branch then raise exception 'Service not found in selected branch'; end if;
  else
    raise exception 'Select a product or service';
  end if;

  insert into public.sales(
    user_id,branch,item_name,product_id,service_id,quantity,unit_price,
    subtotal,discount,final_total,cost_total,profit,payment_method,
    mpesa_reference,sale_date
  )
  values(
    p_user_id,p_branch,p_item_name,p_product_id,p_service_id,p_quantity,p_unit_price,
    p_quantity*p_unit_price,coalesce(p_discount,0),p_final_total,coalesce(p_cost_total,0),
    p_final_total-coalesce(p_cost_total,0),p_payment_method,p_mpesa_reference,coalesce(p_sale_date,current_date)
  )
  returning * into new_sale;

  return next new_sale;
end;
$$;

revoke all on function public.record_sale(uuid,uuid,text,integer,numeric,numeric,numeric,numeric,text,text,text,date,uuid) from public;
grant execute on function public.record_sale(uuid,uuid,text,integer,numeric,numeric,numeric,numeric,text,text,text,date,uuid) to authenticated;


-- Staff may record expenses for their own branch.
drop policy if exists "expenses admin" on public.expenses;
drop policy if exists "expenses admin manage" on public.expenses;
drop policy if exists "expenses staff insert" on public.expenses;
drop policy if exists "expenses branch read" on public.expenses;

create policy "expenses branch read"
on public.expenses for select
using (public.my_role()='admin' or branch=public.my_branch());

create policy "expenses admin manage"
on public.expenses for all
using (public.my_role()='admin')
with check (public.my_role()='admin');

create policy "expenses staff insert"
on public.expenses for insert
with check (public.my_role()='staff' and branch=public.my_branch() and created_by=auth.uid());


-- Admin-only safe product deletion.
-- Historical records are preserved; only their foreign-key product reference is cleared.
create or replace function public.delete_product(p_product_id uuid)
returns void
language plpgsql
security definer
set search_path=public
as $$
begin
  if public.my_role() <> 'admin' then raise exception 'Admin only'; end if;

  update public.sales set product_id=null where product_id=p_product_id;
  update public.purchases set product_id=null where product_id=p_product_id;
  update public.transfers set product_id=null where product_id=p_product_id;
  delete from public.products where id=p_product_id;

  if not found then raise exception 'Product not found'; end if;
end;
$$;

revoke all on function public.delete_product(uuid) from public;
grant execute on function public.delete_product(uuid) to authenticated;


-- Admin user management.
create or replace function public.admin_list_users()
returns table(id uuid, full_name text, email text, role public.app_role, branch text, created_at timestamptz)
language sql
security definer
set search_path=public
as $$
  select p.id,p.full_name,u.email,p.role,p.branch,p.created_at
  from public.profiles p
  join auth.users u on u.id=p.id
  where public.my_role()='admin'
  order by p.created_at desc;
$$;

revoke all on function public.admin_list_users() from public;
grant execute on function public.admin_list_users() to authenticated;

create or replace function public.admin_set_user_profile(
  p_email text,
  p_full_name text,
  p_role public.app_role,
  p_branch text
)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare uid uuid;
begin
  if public.my_role() <> 'admin' then raise exception 'Admin only'; end if;
  if p_branch not in ('Branch 1','Branch 2') then raise exception 'Invalid branch'; end if;

  select id into uid from auth.users where lower(email)=lower(trim(p_email)) limit 1;
  if uid is null then raise exception 'Auth user not found. Create the user in Supabase Authentication first.'; end if;

  update public.profiles
  set full_name=coalesce(p_full_name,''), role=p_role, branch=p_branch
  where id=uid;

  if not found then
    insert into public.profiles(id,full_name,role,branch)
    values(uid,coalesce(p_full_name,''),p_role,p_branch);
  end if;
end;
$$;

revoke all on function public.admin_set_user_profile(text,text,public.app_role,text) from public;
grant execute on function public.admin_set_user_profile(text,text,public.app_role,text) to authenticated;


-- Keep new Auth accounts safe: never trust metadata for admin promotion.
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path=public as $$
begin
 insert into public.profiles(id,full_name,role,branch)
 values(
   new.id,
   coalesce(new.raw_user_meta_data->>'full_name',''),
   'staff',
   case
     when new.raw_user_meta_data->>'branch' in ('Branch 1','Branch 2')
       then new.raw_user_meta_data->>'branch'
     else 'Branch 1'
   end
 )
 on conflict (id) do nothing;
 return new;
end; $$;

-- Verify after running:
-- select id,full_name,role,branch from public.profiles order by created_at;


-- ============================================================
-- DANTECH: MISCELLANEOUS SALES & SERVICES
-- Quick services/one-off sales that do not require inventory.
-- ============================================================

create table if not exists public.misc_sales(
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id),
  branch text not null check(branch in ('Branch 1','Branch 2')),
  service_name text not null,
  quantity integer not null default 1 check(quantity>0),
  unit_price numeric(12,2) not null check(unit_price>=0),
  subtotal numeric(12,2) not null,
  discount numeric(12,2) not null default 0 check(discount>=0),
  final_total numeric(12,2) not null,
  payment_method text not null check(payment_method in ('Cash','M-Pesa','Card','Other')),
  mpesa_reference text,
  sale_date date not null default current_date,
  created_at timestamptz not null default now()
);

alter table public.misc_sales enable row level security;

drop policy if exists "misc sales branch read" on public.misc_sales;
drop policy if exists "misc sales branch insert" on public.misc_sales;

create policy "misc sales branch read"
on public.misc_sales for select
using (public.my_role()='admin' or branch=public.my_branch());

create policy "misc sales branch insert"
on public.misc_sales for insert
with check (
  (public.my_role() in ('admin','staff'))
  and branch=public.my_branch()
  and user_id=auth.uid()
);

create or replace function public.record_misc_sale(
  p_service_name text,
  p_quantity integer,
  p_unit_price numeric,
  p_discount numeric,
  p_final_total numeric,
  p_payment_method text,
  p_mpesa_reference text,
  p_branch text,
  p_sale_date date,
  p_user_id uuid
)
returns setof public.misc_sales
language plpgsql
security definer
set search_path=public
as $$
declare
  new_sale public.misc_sales;
begin
  if auth.uid() is null or auth.uid() <> p_user_id then
    raise exception 'Invalid user';
  end if;

  if public.my_role() not in ('admin','staff') then
    raise exception 'Not authorised';
  end if;

  if p_branch <> public.my_branch() then
    raise exception 'Wrong branch';
  end if;

  if nullif(trim(p_service_name),'') is null then
    raise exception 'Service description is required';
  end if;

  if p_quantity is null or p_quantity <= 0 then
    raise exception 'Quantity must be greater than zero';
  end if;

  if p_unit_price is null or p_unit_price <= 0 then
    raise exception 'Unit price must be greater than zero';
  end if;

  if coalesce(p_discount,0) < 0 or coalesce(p_discount,0) > p_quantity*p_unit_price then
    raise exception 'Invalid discount';
  end if;

  if p_final_total is null or p_final_total < 0 then
    raise exception 'Invalid final amount';
  end if;

  insert into public.misc_sales(
    user_id,branch,service_name,quantity,unit_price,subtotal,
    discount,final_total,payment_method,mpesa_reference,sale_date
  )
  values(
    p_user_id,p_branch,trim(p_service_name),p_quantity,p_unit_price,
    p_quantity*p_unit_price,coalesce(p_discount,0),p_final_total,
    p_payment_method,p_mpesa_reference,coalesce(p_sale_date,current_date)
  )
  returning * into new_sale;

  return next new_sale;
end;
$$;

revoke all on function public.record_misc_sale(text,integer,numeric,numeric,numeric,text,text,text,date,uuid) from public;
grant execute on function public.record_misc_sale(text,integer,numeric,numeric,numeric,text,text,text,date,uuid) to authenticated;


-- ============================================================
-- DANTECH: CREDIT / DEBTORS MODULE
-- Stock credit uses the product's current system selling price.
-- Service/other credit allows the amount owed to be entered manually.
-- ============================================================

create table if not exists public.credits(
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id),
  branch text not null check(branch in ('Branch 1','Branch 2')),
  customer_name text not null,
  phone text,
  credit_type text not null check(credit_type in ('stock','service')),
  product_id uuid references public.products(id) on delete set null,
  service_id uuid references public.services(id) on delete set null,
  item_description text not null,
  quantity integer not null default 1 check(quantity>0),
  unit_price numeric(12,2),
  amount_owed numeric(12,2) not null check(amount_owed>0),
  amount_paid numeric(12,2) not null default 0 check(amount_paid>=0 and amount_paid<=amount_owed),
  due_date date,
  notes text,
  credit_date date not null default current_date,
  created_at timestamptz not null default now()
);

create table if not exists public.credit_payments(
  id uuid primary key default gen_random_uuid(),
  credit_id uuid not null references public.credits(id) on delete cascade,
  user_id uuid references auth.users(id),
  branch text not null check(branch in ('Branch 1','Branch 2')),
  amount numeric(12,2) not null check(amount>0),
  payment_method text not null check(payment_method in ('Cash','M-Pesa','Card','Other')),
  mpesa_reference text,
  payment_date date not null default current_date,
  created_at timestamptz not null default now()
);

create index if not exists credits_branch_date_idx on public.credits(branch,credit_date desc);
create index if not exists credit_payments_credit_idx on public.credit_payments(credit_id,created_at desc);

alter table public.credits enable row level security;
alter table public.credit_payments enable row level security;

drop policy if exists "credits branch read" on public.credits;
drop policy if exists "credits branch insert" on public.credits;
create policy "credits branch read"
on public.credits for select
using(public.my_role()='admin' or branch=public.my_branch());
create policy "credits branch insert"
on public.credits for insert
with check(public.my_role() in ('admin','staff') and branch=public.my_branch() and user_id=auth.uid());

drop policy if exists "credit payments branch read" on public.credit_payments;
create policy "credit payments branch read"
on public.credit_payments for select
using(public.my_role()='admin' or branch=public.my_branch());

create or replace function public.record_credit(
  p_customer_name text,
  p_phone text,
  p_credit_type text,
  p_product_id uuid,
  p_item_description text,
  p_quantity integer,
  p_amount_owed numeric,
  p_due_date date,
  p_notes text,
  p_branch text,
  p_user_id uuid
)
returns setof public.credits
language plpgsql
security definer
set search_path=public
as $$
declare
  p public.products;
  v_amount numeric(12,2);
  v_unit numeric(12,2);
  new_credit public.credits;
begin
  if auth.uid() is null or auth.uid() <> p_user_id then raise exception 'Invalid user'; end if;
  if public.my_role() not in ('admin','staff') then raise exception 'Not authorised'; end if;
  if p_branch <> public.my_branch() then raise exception 'Wrong branch'; end if;
  if nullif(trim(p_customer_name),'') is null then raise exception 'Customer name is required'; end if;
  if p_quantity is null or p_quantity<=0 then raise exception 'Quantity must be greater than zero'; end if;

  if p_credit_type='stock' then
    if p_product_id is null then raise exception 'Select a stock product'; end if;
    select * into p from public.products where id=p_product_id for update;
    if p.id is null or p.branch<>p_branch then raise exception 'Product not found in selected branch'; end if;
    if p.qty<p_quantity then raise exception 'Insufficient stock'; end if;
    v_unit=p.selling_price;
    v_amount=v_unit*p_quantity;
    update public.products set qty=qty-p_quantity where id=p.id;
    insert into public.credits(
      user_id,branch,customer_name,phone,credit_type,product_id,item_description,
      quantity,unit_price,amount_owed,due_date,notes
    ) values(
      p_user_id,p_branch,trim(p_customer_name),nullif(trim(p_phone),''),
      'stock',p.id,p.name,p_quantity,v_unit,v_amount,p_due_date,p_notes
    ) returning * into new_credit;
  elsif p_credit_type='service' then
    if nullif(trim(p_item_description),'') is null then raise exception 'Service or description is required'; end if;
    if p_amount_owed is null or p_amount_owed<=0 then raise exception 'Enter a valid amount owed'; end if;
    v_amount=p_amount_owed;
    insert into public.credits(
      user_id,branch,customer_name,phone,credit_type,service_id,item_description,
      quantity,unit_price,amount_owed,due_date,notes
    ) values(
      p_user_id,p_branch,trim(p_customer_name),nullif(trim(p_phone),''),
      'service',null,trim(p_item_description),1,v_amount,v_amount,p_due_date,p_notes
    ) returning * into new_credit;
  else
    raise exception 'Invalid credit type';
  end if;

  return next new_credit;
end;
$$;

revoke all on function public.record_credit(text,text,text,uuid,text,integer,numeric,date,text,text,uuid) from public;
grant execute on function public.record_credit(text,text,text,uuid,text,integer,numeric,date,text,text,uuid) to authenticated;

create or replace function public.record_credit_payment(
  p_credit_id uuid,
  p_amount numeric,
  p_payment_method text,
  p_mpesa_reference text,
  p_user_id uuid
)
returns setof public.credits
language plpgsql
security definer
set search_path=public
as $$
declare
  c public.credits;
  new_paid numeric(12,2);
begin
  if auth.uid() is null or auth.uid() <> p_user_id then raise exception 'Invalid user'; end if;
  if public.my_role() not in ('admin','staff') then raise exception 'Not authorised'; end if;
  if p_amount is null or p_amount<=0 then raise exception 'Payment amount must be greater than zero'; end if;

  select * into c from public.credits where id=p_credit_id for update;
  if c.id is null then raise exception 'Credit account not found'; end if;
  if c.branch<>public.my_branch() then raise exception 'Wrong branch'; end if;
  if p_amount > (c.amount_owed-c.amount_paid) then raise exception 'Payment exceeds outstanding balance'; end if;
  if p_payment_method not in ('Cash','M-Pesa','Card','Other') then raise exception 'Invalid payment method'; end if;

  new_paid=c.amount_paid+p_amount;
  update public.credits set amount_paid=new_paid where id=c.id;
  insert into public.credit_payments(credit_id,user_id,branch,amount,payment_method,mpesa_reference)
  values(c.id,p_user_id,c.branch,p_amount,p_payment_method,nullif(trim(p_mpesa_reference),''));

  return query select * from public.credits where id=c.id;
end;
$$;

revoke all on function public.record_credit_payment(uuid,numeric,text,text,uuid) from public;
grant execute on function public.record_credit_payment(uuid,numeric,text,text,uuid) to authenticated;

-- Keep product deletion safe when a product has historical credit records.
create or replace function public.delete_product(p_product_id uuid)
returns void
language plpgsql
security definer
set search_path=public
as $$
begin
  if public.my_role() <> 'admin' then raise exception 'Admin only'; end if;
  update public.sales set product_id=null where product_id=p_product_id;
  update public.purchases set product_id=null where product_id=p_product_id;
  update public.transfers set product_id=null where product_id=p_product_id;
  update public.credits set product_id=null where product_id=p_product_id;
  delete from public.products where id=p_product_id;
  if not found then raise exception 'Product not found'; end if;
end;
$$;

revoke all on function public.delete_product(uuid) from public;
grant execute on function public.delete_product(uuid) to authenticated;

