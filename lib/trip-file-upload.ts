type UploadConfig={base:string;key:string};
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const kinds=new Set(['ttn','waybill','ticket','invoice','upd','registry','other']);
export async function handleTripFileUpload(request:Request,config:UploadConfig,transport:typeof fetch=fetch){
 const authorization=request.headers.get('authorization');
 const fail=(message:string,status:number)=>Response.json({message},{status,headers:{'Cache-Control':'no-store'}});
 if(!authorization?.startsWith('Bearer '))return fail('Войдите в CRM повторно',401);
 if(Number(request.headers.get('content-length')||0)>11534336)return fail('Размер документа не должен превышать 10 МБ',413);
 const headers={apikey:config.key,Authorization:authorization};let uploadedPath='';let registered=false;
 async function api(path:string,init:RequestInit={}){const h=new Headers(init.headers);for(const [k,v] of Object.entries(headers))h.set(k,v);return transport(config.base+path,{...init,headers:h,cache:'no-store',signal:AbortSignal.timeout(60000)})}
 try{
  const auth=await api('/auth/v1/user');if(!auth.ok)return fail('Сессия истекла. Войдите в CRM повторно',401);const user=await auth.json();if(!uuid.test(user.id||''))return fail('Войдите в CRM повторно',401);
  const form=await request.formData(),tripId=String(form.get('tripId')||''),uploadId=String(form.get('uploadId')||''),kind=String(form.get('kind')||''),file=form.get('file');
  if(!uuid.test(tripId)||!uuid.test(uploadId)||!kinds.has(kind)||!(file instanceof File))return fail('Выберите рейс, тип документа и файл',400);
  if(file.size<=0||file.size>10485760)return fail('Выберите непустой файл размером до 10 МБ',413);
  const tripResponse=await api('/rest/v1/rl_crm_trips?'+new URLSearchParams({id:'eq.'+tripId,deleted_at:'is.null',select:'id'}));
  if(!tripResponse.ok)return fail('Не удалось проверить доступ к рейсу. Повторите загрузку',502);const trips=await tripResponse.json();if(!trips.length)return fail('Рейс недоступен или удалён',404);
  const bytes=new Uint8Array(await file.arrayBuffer()),extension=file.name.match(/\.([a-z0-9]{1,16})$/i)?.[1].toLowerCase()||'bin';
  const path=user.id+'/'+tripId+'/'+uploadId+'.'+extension;
  const existing=await api('/rest/v1/rl_crm_trip_files?'+new URLSearchParams({storage_path:'eq.'+path,select:'id'}));if(!existing.ok)return fail('Не удалось проверить сохранённые документы',502);const found=await existing.json();if(found.length)return Response.json({id:found[0].id,saved:true});
  // All original file formats are kept as private downloads, never executable same-origin pages.
  const stored=await api('/storage/v1/object/respectlogistic-trip-documents/'+path,{method:'POST',headers:{'Content-Type':'application/octet-stream','x-upsert':'false'},body:bytes});
  if(!stored.ok){if(stored.status!==409)return fail('Хранилище не приняло документ. Повторите загрузку',502)}else uploadedPath=path;
  const result=await api('/rest/v1/rpc/respectlogistic_register_trip_file',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({p_trip_id:tripId,p_path:path,p_name:file.name.slice(0,255),p_type:kind})});
  if(!result.ok)return fail('Файл не удалось прикрепить к рейсу. Повторите загрузку',502);
  registered=true;return Response.json({id:await result.json(),saved:true});
 }catch{return fail('Не удалось завершить загрузку. Проверьте соединение и повторите попытку',502)}
 finally{if(uploadedPath&&!registered)try{await api('/storage/v1/object/respectlogistic-trip-documents',{method:'DELETE',headers:{'Content-Type':'application/json'},body:JSON.stringify({prefixes:[uploadedPath]})})}catch{}}
}
