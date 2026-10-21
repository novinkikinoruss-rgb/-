import {createClient} from '@supabase/supabase-js';
import {validInn} from '../../../lib/domain';
export const dynamic='force-dynamic';
export async function POST(request:Request){
  const key=process.env.DADATA_API_KEY,url=process.env.NEXT_PUBLIC_SUPABASE_URL,publishable=process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
  if(!key||!url||!publishable)return Response.json({error:'Автозаполнение по ИНН ещё не подключено. Можно заполнить реквизиты вручную.'},{status:503});
  const authorization=request.headers.get('Authorization')||'';
  if(!authorization.startsWith('Bearer '))return Response.json({error:'Для поиска реквизитов войдите в CRM'},{status:401});
  const db=createClient(url,publishable,{auth:{persistSession:false,autoRefreshToken:false}});
  const {data,error}=await db.auth.getUser(authorization.slice(7));
  if(error||!data.user)return Response.json({error:'Сессия истекла. Войдите снова'},{status:401});
  let inn:string;
  try{const body=await request.text();if(body.length>200)throw new Error();inn=JSON.parse(body).inn;if(!validInn(inn))throw new Error();}catch{return Response.json({error:'Проверьте ИНН организации'},{status:400});}
  try{
    const response=await fetch('https://suggestions.dadata.ru/suggestions/api/4_1/rs/findById/party',{method:'POST',headers:{'Content-Type':'application/json',Authorization:`Token ${key}`},body:JSON.stringify({query:inn,branch_type:'MAIN',count:1}),signal:AbortSignal.timeout(10000),cache:'no-store'});
    if(!response.ok)throw new Error();
    const result=await response.json(),party=result.suggestions?.[0]?.data;
    if(!party||party.inn!==inn)return Response.json({error:'Организация не найдена. Проверьте ИНН или заполните данные вручную.'},{status:404});
    return Response.json({company:{name:party.name?.short_with_opf||'',fullName:party.name?.full_with_opf||'',inn:party.inn,kpp:party.kpp||'',ogrn:party.ogrn||'',legalAddress:party.address?.unrestricted_value||party.address?.value||'',director:party.management?.name||''}},{headers:{'Cache-Control':'no-store'}});
  }catch{return Response.json({error:'Сервис реквизитов временно недоступен. Попробуйте позже или заполните вручную.'},{status:502});}
}
