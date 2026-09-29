# DANTECH CYBER SOLUTIONS — ONLINE POS SETUP

This package is the online/database edition of the Dantech POS. It uses:
- HTML/CSS/JavaScript for the interface
- Supabase Auth for logins/passwords
- Supabase PostgreSQL for the online business database
- Row Level Security (RLS) so staff only access their branch

## 1. Create the online database
1. Create a project at Supabase.
2. Open SQL Editor.
3. For an existing database, do NOT paste `supabase_schema.sql`; run `DANTECH_EXISTING_DB_UPGRADE.sql` only.
4. Run it.

## 2. Create users
In Supabase Dashboard → Authentication → Users, create your admin and staff users using email/password.

IMPORTANT: The automatic profile trigger reads optional user metadata:
- full_name
- role: admin or staff
- branch: Branch 1 or Branch 2

Example metadata for an admin:
{"full_name":"Dantech Admin","role":"admin","branch":"Branch 1"}

Example metadata for Branch 1 staff:
{"full_name":"Branch 1 Staff","role":"staff","branch":"Branch 1"}

Example metadata for Branch 2 staff:
{"full_name":"Branch 2 Staff","role":"staff","branch":"Branch 2"}

For maximum safety, create the first user as admin, then verify their profile in Table Editor.

## 3. Connect the website
In Supabase: Project Settings → API.
Copy:
- Project URL
- Publishable/anon key

Open `index.html` in a text editor and replace:
YOUR_SUPABASE_PROJECT_URL
YOUR_SUPABASE_ANON_KEY

Do NOT put a Supabase service_role/secret key into this HTML file.

## 4. Password changes
Every logged-in user has:
My Account → Change My Password

The system requires at least 8 characters.

An administrator can also reset a user's password from the Supabase Authentication dashboard. Do not put secret/service keys in the browser.

## 5. Staff permissions
Staff can:
- record sales
- select Cash/M-Pesa/Card/Other
- record M-Pesa reference
- apply discounts
- add NEW services with a name and price
- view their branch's stock/services/sales

Staff cannot:
- edit previous sales
- access admin reports
- change products
- record expenses/purchases/transfers
- see the other branch's records

## 6. Discounts
At POS:
- No Discount
- Fixed Amount (KES)
- Percentage (%)

The receipt stores the discount and final amount.

## 7. Put it online
After replacing the Supabase settings, upload this folder to a static host such as Netlify, Vercel, GitHub Pages, or your own web hosting.

The included HTML is already designed to work as a web application.

## 8. Branding and pictures
`assets/dantech-business.svg` and `assets/dantech-mark.svg` are local Dantech-themed artwork. Replace these SVGs with your real Dantech logo/photos whenever you want.

## 9. Your real stock
The SQL contains sample products only. Send your actual stock list (Excel/CSV/PDF/photo/typed list) and it can be converted into an import file for the online database.

## 10. Production notes
Before public launch:
- enable appropriate Supabase Auth email settings
- use strong passwords
- configure backups
- verify RLS policies
- add your real branch names
- add your real business phone/logo
- consider a custom domain and HTTPS
