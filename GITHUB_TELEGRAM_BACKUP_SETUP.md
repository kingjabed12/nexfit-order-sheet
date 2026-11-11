# NEXFIT Telegram Daily Backup (GitHub Actions)

This workflow exports the NEXFIT Supabase tables to a gzip-compressed JSON file and sends it to the configured Telegram chat every day at 00:00 Asia/Dhaka (18:00 UTC). It can also be run manually from the Actions tab.

## Required GitHub Actions secrets

Open repository Settings → Secrets and variables → Actions → New repository secret. Add these exact names:

- `SUPABASE_URL` — `https://bsukrmlyrqlzqyjnrcjo.supabase.co`
- `SUPABASE_SECRET_KEY` — the Supabase secret key (starts with `sb_secret_`). Keep private.
- `TELEGRAM_BOT_TOKEN` — token from BotFather. Keep private.
- `TELEGRAM_CHAT_ID` — the private chat ID supplied by the owner.

Never commit secrets to source files or send them in chat.

## First Telegram setup

Open the NEXFIT backup bot in Telegram and tap **Start** before the first backup so it can message the account.

## Run a test

After adding all four secrets, open the repository's Actions tab, choose **NEXFIT Telegram Daily Backup**, select **Run workflow**, and confirm. Check the workflow result and Telegram for the backup document.

## Tables included

- moderators
- customers
- activity_logs
- nexfit_user_profiles
- moderator_balance_transactions

This is an export-only backup. Restore tooling is not included yet. Keep another independent copy of important backups; Telegram is not guaranteed permanent archival storage. Telegram Bot API upload limits apply.
