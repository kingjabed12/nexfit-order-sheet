# NEXFIT Telegram Daily Backup

The Vercel Cron job calls `/api/backup` daily at 18:00 UTC (00:00 Asia/Dhaka).

## Required Vercel environment variables

Set these for **Production** (and Preview only if you intend to test Preview):

- `TELEGRAM_BOT_TOKEN`: the token from BotFather. Keep it secret.
- `TELEGRAM_CHAT_ID`: the destination Telegram chat ID.
- `SUPABASE_SERVICE_ROLE_KEY`: the Supabase service-role/secret key. This is server-only and must never use a `VITE_` prefix.
- `CRON_SECRET`: a long, random secret used to authorize the scheduled endpoint.
- `SUPABASE_URL`: `https://bsukrmlyrqlzqyjnrcjo.supabase.co` (or keep the existing `VITE_SUPABASE_URL` variable).

Do not put secret values in source code, GitHub, or browser-visible variables.

## What is included

The compressed JSON archive contains rows from:
- `customers`
- `moderators`
- `activity_logs`
- `nexfit_user_profiles`
- `moderator_balance_transactions`

Each table is paginated in batches of 1,000 rows. A backup is not sent if any table export fails.

## First-time Telegram setup

Open the bot chat in Telegram and press **Start** before the first delivery. Telegram bots cannot initiate a private conversation that the user has never started.

## Manual test

After deploying, call `https://nexfit-order-sheet.vercel.app/api/backup` using a GET request with this header:

`Authorization: Bearer YOUR_CRON_SECRET`

Never share the secret or bot token in chat or a URL.

## Important limitations

- This is an application-data export, not a complete physical PostgreSQL backup.
- Supabase Auth password hashes/sessions and Storage object bytes are not included. User profile rows are included, but users may need password resets after a full rebuild.
- Telegram chat history is not guaranteed permanent storage. Keep an independent copy in another storage provider for disaster recovery.
- Restore is not automated by this first backup release. Preserve the original archive unchanged and use a reviewed restore procedure.
