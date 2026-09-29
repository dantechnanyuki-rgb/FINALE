# DANTECH Cyber POS V9 – Charts & Notifications

## Added
- Dashboard sales trend chart for the last 7 days.
- Dashboard payment-method doughnut chart for today's collections.
- Notification bell with unread badge and notification panel.
- Low-stock alerts in notifications.
- Overdue credit alerts in notifications.
- New sales and miscellaneous transactions appear as live notifications.
- Supabase realtime INSERT listeners for sales and miscellaneous transactions.
- Mark-all-read support stored locally in the browser.

## Notes
- Charts use Chart.js from jsDelivr, consistent with the application's existing online Supabase dependency.
- Existing POS, inventory, credit, reports, live miscellaneous transaction list and refresh functions remain included.
