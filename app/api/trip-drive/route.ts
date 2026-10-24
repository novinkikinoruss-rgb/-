import {exportTripFiles,type ExportManifest} from '../../../lib/trip-drive';
export const runtime='nodejs';
export const dynamic='force-dynamic';
export async function GET(){return Response.json({configured:Boolean(process.env.GOOGLE_DRIVE_CLIENT_ID&&process.env.GOOGLE_DRIVE_CLIENT_SECRET&&process.env.GOOGLE_DRIVE_REFRESH_TOKEN&&process.env.GOOGLE_DRIVE_TRIPS_ROOT_FOLDER_ID)},{headers:{'Cache-Control':'no-store'}})}
export async function POST(request:Request){
 const authorization=request.headers.get('authorization');
 if(!authorization?.startsWith('Bearer '))return Response.json({message:'Войдите в CRM'},{status:401});
 const base=process.env.NEXT_PUBLIC_SUPABASE_URL,key=process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
 if(!base||!key)return Response.json({message:'База не подключена'},{status:503});
 async function rpc(name:string,body:unknown){const r=await fetch(base+'/rest/v1/rpc/'+name,{method:'POST',headers:{apikey:key!,Authorization:authorization!,'Content-Type':'application/json'},body:JSON.stringify(body),signal:AbortSignal.timeout(15000),cache:'no-store'});if(!r.ok)throw Error('Не удалось проверить доступ к документам');return r.json()}
 let manifest:ExportManifest|null=null;
 try{
  const {tripId}=await request.json();if(typeof tripId!=='string'||!/^[-a-f0-9]{36}$/.test(tripId))return Response.json({message:'Некорректный рейс'},{status:400});
  manifest=await rpc('respectlogistic_claim_drive_export',{p_trip_id:tripId});if(!manifest)return Response.json({state:'unchanged'});
  const settings={clientId:process.env.GOOGLE_DRIVE_CLIENT_ID,clientSecret:process.env.GOOGLE_DRIVE_CLIENT_SECRET,refreshToken:process.env.GOOGLE_DRIVE_REFRESH_TOKEN,rootFolder:process.env.GOOGLE_DRIVE_TRIPS_ROOT_FOLDER_ID};
  if(!settings.clientId||!settings.clientSecret||!settings.refreshToken||!settings.rootFolder){await rpc('respectlogistic_finish_drive_export',{p_trip_id:tripId,p_version:manifest.version,p_state:'awaiting_connection',p_error:'Подключите Google Диск к CRM для автоматической отправки документов'});return Response.json({state:'awaiting_connection'})}
  const folder=await exportTripFiles(manifest,{clientId:settings.clientId,clientSecret:settings.clientSecret,refreshToken:settings.refreshToken,rootFolder:settings.rootFolder},async(path)=>{
   if(path.startsWith('shift:')){const file=await rpc('respectlogistic_driver_file',{p_id:path.slice(6)});return new Uint8Array(Buffer.from(file.base64,'base64'));}
   const r=await fetch(base+'/storage/v1/object/authenticated/respectlogistic-trip-documents/'+path,{headers:{apikey:key!,Authorization:authorization!},signal:AbortSignal.timeout(20000),cache:'no-store'});
   if(!r.ok)throw Error('Не удалось прочитать документ из закрытого хранилища');return new Uint8Array(await r.arrayBuffer());
  });
  const saved=await rpc('respectlogistic_finish_drive_export',{p_trip_id:tripId,p_version:manifest.version,p_state:'complete',p_url:folder});
  return Response.json({state:saved?'complete':'changed',url:saved?folder:null});
 }catch{
  if(manifest)try{await rpc('respectlogistic_finish_drive_export',{p_trip_id:manifest.trip_id,p_version:manifest.version,p_state:'error',p_error:'Не удалось отправить документы. Проверьте подключение Диска и повторите отправку.'})}catch{}
  return Response.json({message:'Документы сохранены в CRM. Отправка на Google Диск не выполнена.'},{status:502});
 }
}
