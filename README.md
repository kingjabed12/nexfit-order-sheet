# Nexfit Order Sheet

Mobile-first shared customer manager for Nexfit Fashion.

## Stack
React + TypeScript + Vite, Supabase PostgreSQL, Realtime, RLS, SheetJS XLSX export.

## Setup
1. Create a Supabase project.
2. Run `supabase/migrations/001_initial_schema.sql` in Supabase SQL Editor.
3. Set `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` in hosting environment variables.
4. Never put a `service_role` or secret key in frontend code.
5. Run `npm install`, `npm run build`; deploy `dist/` to Vercel.
6. Open the app and add moderator names from the Moderators tab.

## No-login mode security warning
Anyone with the public URL can view, add, edit, delete records, add/deactivate moderators, and impersonate any moderator by selecting their name. The RLS policies are intentionally public to make anonymous access work. This is not suitable for sensitive customer data or an unrestricted public URL. Add authentication or individual PINs and tighten RLS before production use.

## Duplicate safety
Phone numbers are normalized in PostgreSQL to Bangladesh local format `01XXXXXXXXX`; a database UNIQUE constraint on `normalized_phone` prevents simultaneous duplicate inserts.

## Notes
The header currently uses a temporary N monogram.
