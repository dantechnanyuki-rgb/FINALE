DANTECH CYBER POS V8 — MODERN LOGIN + LIVE MISC UI

DANTECH CYBER SOLUTIONS - UPDATED ONLINE POS
================================================

This package is based on your uploaded BRANCH2_FIXED system and includes the requested business changes.

NEW FEATURES
------------
1. Admin can delete products from inventory.
2. Branch 1 and Branch 2 stay separate.
3. Admin Reports Centre:
   - Daily
   - Weekly
   - Monthly
   - Yearly
   - All Branches / Branch 1 / Branch 2
   - Sales/Earnings, Expenses, Purchases, Transfers and Services reports
   - Branch comparison and printable reports
4. Staff only see today's sales in the Sales/POS area.
5. Staff can add a new service and manually type its price.
6. Service sales are included in that day's earnings.
7. Staff have an Expenses tab and can record expenses for their own branch.
8. Staff cannot edit or delete expense records.
9. Product sales deduct stock automatically.
10. Lively red/blue Dantech interface improvements.
11. Admin Users page for assigning existing Auth users to Branch 1/Branch 2 and Staff/Admin.

IMPORTANT - FIRST TIME UPDATE
-----------------------------
Your existing Supabase database already has the Dantech tables. DO NOT run the original
supabase_schema.sql again. The upgrade file is safe to rerun and removes the existing expense policies before recreating them.

Instead:
1. Open your Supabase project.
2. Go to SQL Editor.
3. Open DANTECH_EXISTING_DB_UPGRADE.sql from this package.
4. Run the whole file once.
5. Go to Authentication > Users and create the staff accounts.
6. Log in as your administrator.
7. Open Users in the Dantech system and assign each account its correct Branch and Role.

The browser uses the publishable Supabase key only. Never put a Supabase service-role/secret
key into index.html.

STARTING THE SYSTEM
-------------------
Double-click START_DANTECH.bat, or double-click index.html.
An internet connection is required because the system uses Supabase online.

If Windows blocks the .bat file, right-click it > More options > Run anyway.

BRANCH RULE
-----------
Branch 1 and Branch 2 are intentionally independent for stock, sales and expenses.
The administrator can view both from the Reports Centre.

AUTH USER RULE
--------------
A new Supabase Auth user starts as Staff / Branch 1 by design.
Use the Dantech Users page to change the user to Staff/Admin and Branch 1/Branch 2.
