import { createClient } from '@supabase/supabase-js';

declare const process: { env: Record<string, string | undefined> };

const json = (res: any, status: number, body: Record<string, unknown>) =>
  res.status(status).json(body);

// Safe, read-only connection test: calls SteadFast get_balance and never creates a parcel.
export default async function handler(req: any, res: any) {
  if (req.method !== 'GET') return json(res, 405, { error: 'Method not allowed' });

  const token = String(req.headers.authorization || '').replace(/^Bearer\s+/i, '');
  if (!token) return json(res, 401, { error: 'Login required' });

  const url = process.env.VITE_SUPABASE_URL;
  const anonKey = process.env.VITE_SUPABASE_ANON_KEY;
  const apiKey = process.env.STEADFAST_API_KEY;
  const secretKey = process.env.STEADFAST_SECRET_KEY;
  if (!url || !anonKey || !apiKey || !secretKey) {
    return json(res, 500, { error: 'Server configuration incomplete. Check Production environment variables in Vercel.' });
  }

  const db = createClient(url, anonKey, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: `Bearer ${token}` } },
  });
  const { data: auth, error: authError } = await db.auth.getUser(token);
  if (authError || !auth.user) return json(res, 401, { error: 'Invalid or expired login session' });

  const { data: active, error: activeError } = await db.rpc('nexfit_is_active_user');
  if (activeError || active !== true) return json(res, 403, { error: 'Active NEXFIT account required' });

  try {
    const response = await fetch('https://portal.packzy.com/api/v1/get_balance', {
      method: 'GET',
      headers: { 'Api-Key': apiKey, 'Secret-Key': secretKey, Accept: 'application/json' },
      signal: AbortSignal.timeout(15000),
    });
    const result: any = await response.json().catch(() => null);
    if (!response.ok || result?.status !== 200 || result?.current_balance === undefined) {
      const detail = String(result?.message || result?.error || `SteadFast returned HTTP ${response.status}`).slice(0, 240);
      return json(res, 502, { error: detail });
    }
    return json(res, 200, { connected: true, current_balance: Number(result.current_balance) });
  } catch {
    return json(res, 502, { error: 'SteadFast server did not respond. Check the internet connection and try again.' });
  }
}
