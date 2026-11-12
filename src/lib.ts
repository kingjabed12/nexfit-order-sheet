import {createClient} from '@supabase/supabase-js';
const url=import.meta.env.VITE_SUPABASE_URL||'https://missing.supabase.co';
const key=import.meta.env.VITE_SUPABASE_ANON_KEY||'missing-anon-key';
export const supabase=createClient(url,key,{auth:{persistSession:true,autoRefreshToken:true,detectSessionInUrl:false}});
export const createSignupClient=()=>createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false}});
export const STATUSES=['Confirm','Pending','Problem','Delivered'] as const;
export type Status=typeof STATUSES[number];
export type Moderator={id:string;name:string;active:boolean;balance?:number;username?:string;login_active?:boolean};
export type Customer={id:string;serial_number:number;customer_name:string;customer_details:string;customer_contact_phone:string;customer_address:string;product_images:{id:string;image_path:string}[];phone:string;normalized_phone:string;moderator_id:string|null;moderator_name?:string;created_at:string;status:Status;notes:string;updated_at:string};
export type NexfitProduct={id:string;image_path:string;active:boolean;created_at:string};
export type UserProfile={user_id:string;username:string;role:'admin'|'moderator';moderator_id:string|null;active:boolean};
export function normalizePhone(v:string):string|null{let n=v.replace(/[০-৯]/g,d=>String('০১২৩৪৫৬৭৮৯'.indexOf(d))).replace(/[^0-9]/g,'');if(n.startsWith('00880'))n=n.slice(2);if(n.startsWith('880'))n='0'+n.slice(3);if(/^1[0-9]{9}$/.test(n))n='0'+n;return n.length?n:null}
export function csvCell(v:unknown){return '"'+String(v??'').replaceAll('"','""')+'"'}
