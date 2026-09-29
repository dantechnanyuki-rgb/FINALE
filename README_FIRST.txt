DANTECH CYBER POS V8 — MODERN LOGIN + LIVE MISC UI

DANTECH CYBER SOLUTIONS — BRANCH 2 FIXED VERSION

This version fixes the issue where every new Auth user was forced into Branch 1.

1. IMPORTANT: For an existing Dantech database, do NOT run supabase_schema.sql. Run DANTECH_EXISTING_DB_UPGRADE.sql only.
2. For a new Branch 2 user, create the Auth user with metadata:
   {"full_name":"Branch 2 Staff","branch":"Branch 2"}
3. New users are automatically STAFF. Admin is assigned separately for security.
4. For existing users, use BRANCH2_FIX.sql.
5. Open index.html to use the system.

See SETUP_BRANCH2.md for details.

CREDIT / DEBTORS MODULE:
The POS now includes Credit / Debtors for stock and services. Run DANTECH_CREDIT_UPGRADE.sql once in Supabase SQL Editor if your database already exists. (The same credit SQL is also appended to DANTECH_EXISTING_DB_UPGRADE.sql and supabase_schema.sql.)
