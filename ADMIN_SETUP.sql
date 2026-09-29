-- DANTECH CYBER SOLUTIONS - FIRST ADMIN SETUP
-- Run this file in Supabase Dashboard -> SQL Editor AFTER creating the user
-- under Authentication -> Users.
--
-- IMPORTANT: Replace the email below with the exact email of the person who
-- should be the main Dantech administrator. Do NOT put a password here.

-- 1) Create or repair the profile for the selected Auth user.
insert into public.profiles (id, full_name, role, branch)
select id, coalesce(raw_user_meta_data->>'full_name','Dantech Administrator'), 'admin'::public.app_role, 'Branch 1'
from auth.users
where lower(email) = lower('YOUR_ADMIN_EMAIL_HERE')
on conflict (id) do update
set role = 'admin'::public.app_role,
    branch = 'Branch 1';

-- 2) Optional: force ALL existing profiles to Branch 1, as requested.
update public.profiles set branch='Branch 1';

-- 3) Check the result.
select p.id, p.full_name, u.email, p.role, p.branch
from public.profiles p
left join auth.users u on u.id=p.id
order by u.email;
