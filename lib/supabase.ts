import {createClient} from '@supabase/supabase-js';
const url=process.env.NEXT_PUBLIC_SUPABASE_URL;
const key=process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
export const cloudConfigured=Boolean(url&&key);
// A distinct storage key prevents sharing the old CRM's browser session.
export const db=url&&key?createClient(url,key,{auth:{storageKey:'respectlogistic-auth-v1'}}):null;
