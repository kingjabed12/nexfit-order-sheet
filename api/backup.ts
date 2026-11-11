import { gzipSync } from 'node:zlib';

const TABLES = [
  'moderators',
  'customers',
  'activity_logs',
  'nexfit_user_profiles',
  'moderator_balance_transactions',
] as const;

const PAGE_SIZE = 1000;

function dhakaDate() {
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Dhaka',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(new Date());
}

async function readTable(baseUrl: string, serviceKey: string, table: string) {
  const rows: unknown[] = [];
  for (let offset = 0; ; offset += PAGE_SIZE) {
    const response = await fetch(
      `${baseUrl}/rest/v1/${table}?select=*`,
      {
        headers: {
          apikey: serviceKey,
          Authorization: `Bearer ${serviceKey}`,
          Range: `${offset}-${offset + PAGE_SIZE - 1}`,
          'Range-Unit': 'items',
          Prefer: 'count=none',
        },
      },
    );

    if (!response.ok) {
      const detail = (await response.text()).slice(0, 500);
      throw new Error(`Could not back up table "${table}" (HTTP ${response.status}): ${detail}`);
    }

    const page = await response.json();
    if (!Array.isArray(page)) throw new Error(`Unexpected response for table "${table}"`);
    rows.push(...page);
    if (page.length < PAGE_SIZE) break;
  }
  return rows;
}

export default async function handler(req: any, res: any) {
  if (req.method !== 'GET' && req.method !== 'POST') {
    res.setHeader('Allow', 'GET, POST');
    return res.status(405).json({ error: 'Method not allowed' });
  }

  const expected = process.env.CRON_SECRET;
  const authorization = req.headers.authorization || '';
  if (!expected || authorization !== `Bearer ${expected}`) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  const supabaseUrl = process.env.SUPABASE_URL || process.env.VITE_SUPABASE_URL;
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  const botToken = process.env.TELEGRAM_BOT_TOKEN;
  const chatId = process.env.TELEGRAM_CHAT_ID;

  if (!supabaseUrl || !serviceKey || !botToken || !chatId) {
    return res.status(500).json({
      error: 'Backup environment is incomplete. Configure Supabase URL, service role key, Telegram bot token and chat ID.',
    });
  }

  try {
    const backup: Record<string, unknown> = {
      product: 'NEXFIT Order Sheet',
      format_version: 1,
      created_at: new Date().toISOString(),
      timezone: 'Asia/Dhaka',
      backup_date: dhakaDate(),
      tables: {},
    };

    const tableData = backup.tables as Record<string, unknown>;
    for (const table of TABLES) {
      tableData[table] = await readTable(supabaseUrl.replace(/\/$/, ''), serviceKey, table);
    }

    const json = JSON.stringify(backup);
    const compressed = gzipSync(Buffer.from(json, 'utf8'));
    const date = dhakaDate();
    const filename = `NEXFIT-Backup-${date}.json.gz`;

    const form = new FormData();
    form.append('chat_id', chatId);
    form.append('caption', `NEXFIT Daily Backup · ${date} (Bangladesh time)\nCustomers, moderators, balances and activity records.`);
    form.append('document', new Blob([new Uint8Array(compressed)], { type: 'application/gzip' }), filename);

    const telegramResponse = await fetch(
      `https://api.telegram.org/bot${botToken}/sendDocument`,
      { method: 'POST', body: form },
    );
    const telegramResult = await telegramResponse.json();
    if (!telegramResponse.ok || !telegramResult.ok) {
      throw new Error(`Telegram delivery failed: ${telegramResult.description || telegramResponse.statusText}`);
    }

    return res.status(200).json({
      ok: true,
      date,
      filename,
      tables: Object.fromEntries(TABLES.map((table) => [
        table,
        (tableData[table] as unknown[]).length,
      ])),
      telegram_message_id: telegramResult.result?.message_id ?? null,
    });
  } catch (error) {
    console.error('NEXFIT backup failed:', error instanceof Error ? error.message : 'Unknown error');
    return res.status(500).json({
      error: error instanceof Error ? error.message : 'Backup failed',
    });
  }
}
