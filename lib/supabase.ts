import {createClient} from '@supabase/supabase-js';
import {boundedFetch} from './network';
const url=process.env.NEXT_PUBLIC_SUPABASE_URL;
const key=process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
export const cloudConfigured=Boolean(url&&key);
// A distinct storage key prevents sharing the old CRM's browser session.
const endpoint=typeof window==='undefined'?url:window.location.origin+'/supabase';
export const db=url&&key&&endpoint?createClient(endpoint,key,{
  global:{fetch:boundedFetch},
  auth:{storageKey:'respectlogistic-auth-v1',lockAcquireTimeout:10000},
}):null;
