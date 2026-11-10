import{createClient}from'@supabase/supabase-js';
export const supabase=createClient(import.meta.env.VITE_SUPABASE_URL||'https://missing.supabase.co',import.meta.env.VITE_SUPABASE_ANON_KEY||'missing-anon-key',{auth:{persistSession:false,autoRefreshToken:false}});
export const STATUSES=['Confirm','Pending','Problem'] as const;
export type Status=typeof STATUSES[number];
export type Moderator={id:string;name:string;active:boolean};
export type Customer={id:string;serial_number:number;phone:string;normalized_phone:string;moderator_id:string|null;moderator_name?:string;created_at:string;status:Status;notes:string;updated_at:string};
export function normalizePhone(v:string):string|null{let n=v.replace(/[^0-9]/g,'');if(n.startsWith('00880'))n=n.slice(2);if(n.startsWith('880'))n='0'+n.slice(3);if(/^1[0-9]{9}$/.test(n))n='0'+n;return n.length?n:null}
export function csvCell(v:unknown){return '"'+String(v??'').replaceAll('"','""')+'"'}
