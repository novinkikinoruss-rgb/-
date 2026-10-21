import {createClient} from '@supabase/supabase-js';
// Один клиент на приложение: общая сессия для разделов и запросов.
const origin=typeof window==='undefined'?'https://transport-crm-ij9v.onrender.com':window.location.origin;
export const db=createClient(process.env.NEXT_PUBLIC_SUPABASE_URL||origin+'/supabase',process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY||process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY||'sb_publishable_qnb1bLiXSsB-9VuwFMtCiQ_07nL4hyQ');
