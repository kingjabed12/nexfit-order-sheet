import { createClient } from '@supabase/supabase-js';

declare const process: { env: Record<string, string | undefined> };

const json = (res: any, status: number, body: Record<string, unknown>) =>
  res.status(status).json(body);

export default async function handler(req: any, res: any) {
  if (req.method !== 'POST') return json(res, 405, { error: 'Method not allowed' });

  const token = String(req.headers.authorization || '').replace(/^Bearer\s+/i, '');
  if (!token) return json(res, 401, { error: 'Login required' });

  const url = process.env.VITE_SUPABASE_URL;
  const anonKey = process.env.VITE_SUPABASE_ANON_KEY;
  const apiKey = process.env.STEADFAST_API_KEY;
  const secretKey = process.env.STEADFAST_SECRET_KEY;
  if (!url || !anonKey || !apiKey || !secretKey) {
    return json(res, 500, { error: 'Server configuration incomplete. Check Vercel environment variables.' });
  }

  const db = createClient(url, anonKey, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: `Bearer ${token}` } },
  });
  const { data: auth, error: authError } = await db.auth.getUser(token);
  if (authError || !auth.user) return json(res, 401, { error: 'Invalid or expired login session' });

  const body = req.body || {};
  const customerId = String(body.customer_id || '');
  const name = String(body.recipient_name || '').trim();
  const phone = String(body.recipient_phone || '').replace(/\D/g, '');
  const address = String(body.recipient_address || '').trim();
  const cod = Number(body.cod_amount);
  const deliveryType = Number(body.delivery_type ?? 0);
  const note = String(body.note || '').trim().slice(0, 250);
  if (!/^[0-9a-f-]{36}$/i.test(customerId)) return json(res, 400, { error: 'Invalid customer order' });
  if (!name || name.length > 100) return json(res, 400, { error: 'Recipient name is required (max 100 characters)' });
  if (!/^01[3-9]\d{8}$/.test(phone)) return json(res, 400, { error: 'Recipient phone must be an 11-digit Bangladesh mobile number' });
  if (!address || address.length > 250) return json(res, 400, { error: 'Recipient address is required (max 250 characters)' });
  if (!Number.isFinite(cod) || cod < 0) return json(res, 400, { error: 'COD amount must be zero or greater' });
  if (![0, 1].includes(deliveryType)) return json(res, 400, { error: 'Invalid delivery type' });

  const payload = {
    invoice: `NEXFIT-${customerId}`,
    recipient_name: name,
    recipient_phone: phone,
    recipient_address: address,
    cod_amount: cod,
    note,
    delivery_type: deliveryType,
    ...(body.item_description ? { item_description: String(body.item_description).slice(0, 500) } : {}),
    ...(Number(body.total_lot) > 0 ? { total_lot: Number(body.total_lot) } : {}),
  };

  const { error: claimError } = await db.rpc('nexfit_claim_steadfast_parcel', {
    p_customer_id: customerId,
    p_payload: payload,
  });
  if (claimError) return json(res, 409, { error: claimError.message || 'This order is already being processed or was already sent.' });

  let response: Response;
  try {
    response = await fetch('https://portal.packzy.com/api/v1/create_order', {
      method: 'POST',
      headers: {
        'Api-Key': apiKey,
        'Secret-Key': secretKey,
        'Content-Type': 'application/json',
        Accept: 'application/json',
      },
      body: JSON.stringify(payload),
      signal: AbortSignal.timeout(25000),
    });
  } catch {
    await db.rpc('nexfit_fail_steadfast_parcel', {
      p_customer_id: customerId,
      p_status: 'unknown',
      p_error: 'Courier request timed out or connection failed; verify in SteadFast Merchant before retrying.',
    });
    return json(res, 202, { message: 'Courier response was not confirmed. This order is locked against duplicate submission; check SteadFast Merchant.' });
  }

  let result: any;
  try { result = await response.json(); } catch { result = null; }
  const consignmentId = result?.consignment?.consignment_id;
  if (response.ok && consignmentId !== undefined && consignmentId !== null) {
    const { error: saveError } = await db.rpc('nexfit_complete_steadfast_parcel', {
      p_customer_id: customerId,
      p_consignment_id: String(consignmentId),
    });
    if (saveError) {
      return json(res, 202, {
        consignment_id: String(consignmentId),
        message: 'SteadFast created the parcel, but NEXFIT could not save its CN. Contact Admin before retrying.',
      });
    }
    return json(res, 200, { consignment_id: String(consignmentId), message: 'Parcel created successfully' });
  }

  const definiteFailure = response.status >= 400 && response.status < 500;
  const message = String(result?.message || result?.error || `SteadFast returned HTTP ${response.status}`).slice(0, 350);
  await db.rpc('nexfit_fail_steadfast_parcel', {
    p_customer_id: customerId,
    p_status: definiteFailure ? 'failed' : 'unknown',
    p_error: message,
  });
  return json(res, definiteFailure ? 502 : 202, {
    error: definiteFailure ? message : 'Courier result could not be confirmed. Check SteadFast Merchant before retrying.',
  });
}
