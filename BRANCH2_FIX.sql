-- DANTECH: FIX EXISTING AUTH USERS AND BRANCH ASSIGNMENTS
-- Run this in Supabase SQL Editor.
-- This safely keeps all users as STAFF unless you explicitly promote an account.

-- 1) Make sure every existing Auth user has a profile.
insert into public.profiles (id, full_name, role, branch)
select
  u.id,
  coalesce(u.raw_user_meta_data->>'full_name', split_part(coalesce(u.email,''),'@',1)),
  'staff',
  case
    when u.raw_user_meta_data->>'branch' in ('Branch 1','Branch 2')
      then u.raw_user_meta_data->>'branch'
    else 'Branch 1'
  end
from auth.users u
left join public.profiles p on p.id=u.id
where p.id is null;

-- 2) EXAMPLE: assign a specific existing user to Branch 2.
-- Replace the email below, then run this statement.
-- UPDATE public.profiles p
-- SET branch='Branch 2', role='staff'
-- FROM auth.users u
-- WHERE p.id=u.id AND lower(u.email)=lower('branch2staff@example.com');

-- 3) Check all users and their branch/role.
select p.id, u.email, p.full_name, p.role, p.branch
from public.profiles p
join auth.users u on u.id=p.id
order by p.branch, u.email;
