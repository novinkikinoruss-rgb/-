export const dynamic='force-dynamic';
export const runtime='nodejs';
// A separate driver identity: never forward the CRM owner's JWT from this endpoint.
const actions:Record<string,string>={mobile:'driver_mobile',dispatch:'driver_dispatch',unload:'dispatch_result',trips:'driver_trips',trip_stage:'driver_trip_stage',login:'driver_login',password:'driver_password',logout:'driver_logout',service:'driver_service',extras:'driver_extras',road:'driver_road_data',request:'create_service_request',service_action:'service_action',note:'read_driver_note',shift:'create_shift_report',photo:'driver_upload_photo',shift_action:'shift_action',duty:'duty_action',fine_response:'road_fine_response',file:'driver_file'};
const fields:Record<string,string[]>={mobile:['p_action','p_record','p_base64'],dispatch:['p_action','p_id','p_expected','p_record'],unload:['p_shift','p_record','p_expected'],trips:[],trip_stage:['p_id','p_stage','p_expected'],login:['p_login','p_password'],password:['p_password'],logout:[],service:[],extras:[],road:[],request:['p_record'],service_action:['p_id','p_action','p_expected','p_record'],note:['p_id'],shift:['p_record'],photo:['p_record','p_base64'],shift_action:['p_id','p_action','p_expected','p_record'],duty:['p_vehicle','p_action','p_odometer'],fine_response:['p_id','p_dispute'],file:['p_id']};
const headers={'Cache-Control':'no-store, private','X-Content-Type-Options':'nosniff'};
export async function POST(request:Request){
 const base=process.env.NEXT_PUBLIC_SUPABASE_URL,key=process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
 if(!base||!key||!/^https:\/\/[a-z0-9-]+\.supabase\.co\/?$/.test(base))return Response.json({message:'Сервис не настроен'},{status:503,headers});
 try{
  // Stream with a hard bound even if Content-Length is missing.
  const reader=request.body?.getReader();if(!reader)return Response.json({message:'Пустой запрос'},{status:400,headers});
  const chunks:Uint8Array[]=[];let length=0;for(;;){const {value,done}=await reader.read();if(done)break;length+=value.byteLength;if(length>2900000){await reader.cancel();return Response.json({message:'Слишком большой запрос'},{status:413,headers});}chunks.push(value);}
  const body=JSON.parse(Buffer.concat(chunks).toString('utf8'));if(!body||typeof body!=='object'||Array.isArray(body))return Response.json({message:'Неверный запрос'},{status:400,headers});const action=String(body.action||'');
  if(!Object.hasOwn(actions,action))return Response.json({message:'Действие недоступно'},{status:404,headers});
  const params:Record<string,unknown>={};for(const name of fields[action])if(Object.hasOwn(body,name))params[name]=body[name];
  if(action!=='login'){
   const token=request.headers.get('authorization')?.replace(/^Bearer /,'');
   if(!token||! /^[a-f0-9]{64}$/.test(token))return Response.json({message:'Войдите в приложение'},{status:401,headers});params.p_token=token;
  }
  const response=await fetch(base.replace(/\/$/,'')+'/rest/v1/rpc/respectlogistic_'+actions[action],{method:'POST',headers:{apikey:key,'Content-Type':'application/json'},body:JSON.stringify(params),signal:AbortSignal.timeout(20000),cache:'no-store',redirect:'error'});
  const text=await response.text();const result=text?JSON.parse(text):null;
  if(!response.ok)return Response.json({message:result?.message||'Не удалось выполнить действие'},{status:result?.message==='Сначала смените временный пароль'?409:result?.code==='28000'?401:400,headers});
  if(action==='login'&&result?.error)return Response.json({message:result.error},{status:401,headers});
  if(action==='file')return new Response(Buffer.from(result.base64,'base64'),{headers:{...headers,'Content-Type':'image/jpeg','Content-Disposition':"attachment; filename*=UTF-8''"+encodeURIComponent(result.name)}});
  return Response.json(result,{headers});
 }catch(error){return Response.json({message:error instanceof SyntaxError?'Неверный запрос':'Не удалось связаться с сервером. Повторите попытку'},{status:error instanceof SyntaxError?400:502,headers});}
}
