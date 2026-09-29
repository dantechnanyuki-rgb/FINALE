# DANTECH BRANCH 2 USER SETUP

The previous version forced every new Auth user to Branch 1. This version fixes that.

## For a NEW Branch 2 staff account

In Supabase → Authentication → Users → Add user, create the user and set User Metadata to:

```json
{"full_name":"Branch 2 Staff","branch":"Branch 2"}
```

Do not put `role:"admin"` in user metadata. New Auth users are deliberately created as **staff** for security.

The database trigger will create the user's profile as:
- Role: staff
- Branch: Branch 2

## For an EXISTING user

Open `BRANCH2_FIX.sql` and use the example UPDATE statement. Replace the example email with the user's actual email, then run it in Supabase SQL Editor.

## To check the result

Run the final SELECT in `BRANCH2_FIX.sql`. You should see the user with:

`staff | Branch 2`

Then have that user log out and log in again.

## Important

Do NOT place your Supabase service-role/secret key in `index.html`.
