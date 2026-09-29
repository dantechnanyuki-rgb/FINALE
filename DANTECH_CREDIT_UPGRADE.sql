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

drop function if exists public.record_credit(text,text,text,uuid,text,integer,numeric,date,text,text,uuid);

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
    -- If the typed product matches stock in the system, use its selling price and deduct stock.
    -- If it does not match, allow a manual amount for a stock item that is not yet in inventory.
    if p_product_id is not null then
      select * into p from public.products where id=p_product_id for update;
      if p.id is null or p.branch<>p_branch then raise exception 'Product not found in selected branch'; end if;
      if p.qty<p_quantity then raise exception 'Insufficient stock'; end if;
      v_unit=p.selling_price;
      v_amount=v_unit*p_quantity;
      update public.products set qty=qty-p_quantity where id=p.id;
    else
      if nullif(trim(p_item_description),'') is null then raise exception 'Type the stock product'; end if;
      if p_amount_owed is null or p_amount_owed<=0 then raise exception 'Enter the amount owed manually for a stock item not in the system'; end if;
      v_unit=p_amount_owed/p_quantity;
      v_amount=p_amount_owed;
    end if;
    insert into public.credits(
      user_id,branch,customer_name,phone,credit_type,product_id,item_description,
      quantity,unit_price,amount_owed,due_date,notes
    ) values(
      p_user_id,p_branch,trim(p_customer_name),nullif(trim(p_phone),''),
      'stock',p.id,coalesce(p.name,trim(p_item_description)),p_quantity,v_unit,v_amount,p_due_date,p_notes
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



-- Allow an existing debtor record to be edited / increased.
-- For stock credits linked to inventory, changing quantity adjusts stock by the difference.
-- For service/manual credits, the amount owed can be changed directly.
drop function if exists public.update_credit(uuid,text,text,numeric,integer,date,text,uuid);
create or replace function public.update_credit(
  p_credit_id uuid,
  p_customer_name text,
  p_phone text,
  p_amount_owed numeric,
  p_quantity integer,
  p_due_date date,
  p_notes text,
  p_user_id uuid
)
returns setof public.credits
language plpgsql
security definer
set search_path=public
as $$
declare
  c public.credits;
  p public.products;
  v_qty integer;
  v_amount numeric(12,2);
  v_diff integer;
begin
  if auth.uid() is null or auth.uid() <> p_user_id then raise exception 'Invalid user'; end if;
  if public.my_role() not in ('admin','staff') then raise exception 'Not authorised'; end if;
  if nullif(trim(p_customer_name),'') is null then raise exception 'Customer name is required'; end if;
  if p_amount_owed is null or p_amount_owed<=0 then raise exception 'Amount owed must be greater than zero'; end if;

  select * into c from public.credits where id=p_credit_id for update;
  if c.id is null then raise exception 'Credit account not found'; end if;
  if c.branch<>public.my_branch() then raise exception 'Wrong branch'; end if;
  if p_amount_owed<c.amount_paid then raise exception 'Amount owed cannot be less than amount already paid'; end if;

  if c.product_id is not null then
    select * into p from public.products where id=c.product_id for update;
    if p.id is null then raise exception 'Linked product is no longer in inventory'; end if;
    v_qty=coalesce(p_quantity,c.quantity);
    if v_qty<=0 then raise exception 'Quantity must be greater than zero'; end if;
    v_diff=v_qty-c.quantity;
    if v_diff>0 and p.qty<v_diff then raise exception 'Insufficient stock for the additional quantity'; end if;
    if v_diff<>0 then
      update public.products set qty=qty-v_diff where id=p.id;
    end if;
    v_amount=p.selling_price*v_qty;
    update public.credits set
      customer_name=trim(p_customer_name), phone=nullif(trim(p_phone),''),
      quantity=v_qty, unit_price=p.selling_price, amount_owed=v_amount,
      due_date=p_due_date, notes=p_notes
    where id=c.id;
  else
    update public.credits set
      customer_name=trim(p_customer_name), phone=nullif(trim(p_phone),''),
      amount_owed=p_amount_owed, item_description=coalesce(nullif(trim(item_description),''),item_description),
      due_date=p_due_date, notes=p_notes
    where id=c.id;
  end if;

  return query select * from public.credits where id=c.id;
end;
$$;

revoke all on function public.update_credit(uuid,text,text,numeric,integer,date,text,uuid) from public;
grant execute on function public.update_credit(uuid,text,text,numeric,integer,date,text,uuid) to authenticated;

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

-- ============================================================
-- CREDIT COLLECTIONS IN DAILY EARNINGS + MAIN INVENTORY LINK
-- Safe to run after the earlier credit upgrade.
-- ============================================================

create index if not exists credit_payments_branch_date_idx
  on public.credit_payments(branch, payment_date desc);

-- Existing stock-credit rows remain linked to products through product_id.
-- New stock credits already deduct the linked product quantity atomically in record_credit().
-- This function can be used to verify the current inventory link for a credit.
create or replace function public.get_credit_inventory_status(p_credit_id uuid)
returns table(
  credit_id uuid,
  product_id uuid,
  product_name text,
  current_stock integer,
  credit_quantity integer,
  selling_price numeric
)
language sql
security definer
set search_path=public
as $$
  select c.id, c.product_id, p.name, p.qty, c.quantity, p.selling_price
  from public.credits c
  left join public.products p on p.id=c.product_id
  where c.id=p_credit_id
    and (public.my_role()='admin' or c.branch=public.my_branch());
$$;
revoke all on function public.get_credit_inventory_status(uuid) from public;
grant execute on function public.get_credit_inventory_status(uuid) to authenticated;
