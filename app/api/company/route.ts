import {handleCompanyLookup} from '../../../lib/company-lookup';
export const dynamic='force-dynamic';
export async function POST(request:Request){
 return handleCompanyLookup(request,{token:process.env.CHECKO_API_KEY,base:process.env.NEXT_PUBLIC_SUPABASE_URL,key:process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY});
}
