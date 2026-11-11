import { gzipSync } from 'node:zlib';

const required = ['SUPABASE_URL', 'SUPABASE_SECRET_KEY', 'TELEGRAM_BOT_TOKEN', 'TELEGRAM_CHAT_ID'];
for (const key of required) {
  if (!process.env[key]) throw new Error(`Missing required environment variable: ${key}`);
}

const supabaseUrl = process.env.SUPABASE_URL.replace(/\/$/, '');
const secretKey = process.env.SUPABASE_SECRET_KEY;
const tables = [
  'moderators',
  'customers',
  'activity_logs',
  'nexfit_user_profiles',
  'moderator_balance_transactions',
];
const pageSize = 1000;

function dhakaDate() {
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Dhaka',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(new Date());
}

async function readTable(table) {
  const rows = [];
  for (let offset = 0; ; offset += pageSize) {
    const response = await fetch(`${supabaseUrl}/rest/v1/${table}?select=*`, {
      headers: {
        apikey: secretKey,
        Authorization: `Bearer ${secretKey}`,
        Range: `${offset}-${offset + pageSize - 1}`,
        'Range-Unit': 'items',
      },
    });
    if (!response.ok) {
      const detail = (await response.text()).slice(0, 500);
      throw new Error(`Table ${table}: HTTP ${response.status}: ${detail}`);
    }
    const page = await response.json();
    if (!Array.isArray(page)) throw new Error(`Unexpected response for table ${table}`);
    rows.push(...page);
    if (page.length < pageSize) break;
  }
  return rows;
}

const date = dhakaDate();
const backup = {
  product: 'NEXFIT Order Sheet',
  format_version: 1,
  created_at: new Date().toISOString(),
  timezone: 'Asia/Dhaka',
  backup_date: date,
  tables: {},
};

for (const table of tables) {
  backup.tables[table] = await readTable(table);
  console.log(`Backed up ${table}: ${backup.tables[table].length} rows`);
}

const compressed = gzipSync(Buffer.from(JSON.stringify(backup), 'utf8'));
const filename = `NEXFIT-Backup-${date}.json.gz`;
const form = new FormData();
form.append('chat_id', process.env.TELEGRAM_CHAT_ID);
form.append('caption', `NEXFIT Daily Backup · ${date} (Bangladesh time)\nCustomers, moderators, balances and activity records.`);
form.append('document', new Blob([new Uint8Array(compressed)], { type: 'application/gzip' }), filename);

const telegramResponse = await fetch(
  `https://api.telegram.org/bot${process.env.TELEGRAM_BOT_TOKEN}/sendDocument`,
  { method: 'POST', body: form },
);
const telegramResult = await telegramResponse.json();
if (!telegramResponse.ok || !telegramResult.ok) {
  throw new Error(`Telegram delivery failed: ${telegramResult.description || telegramResponse.statusText}`);
}
console.log(`Backup delivered to Telegram. Message ID: ${telegramResult.result?.message_id ?? 'unknown'}`);
