import {handleTripFileUpload} from '../../../lib/trip-file-upload';
export const runtime='nodejs';
export const dynamic='force-dynamic';
export async function POST(request:Request){
 const base=process.env.NEXT_PUBLIC_SUPABASE_URL,key=process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
 if(!base||!key)return Response.json({message:'Хранилище документов не подключено'},{status:503});
 return handleTripFileUpload(request,{base,key});
}
