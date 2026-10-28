export type ExportManifest={trip_id:string;version:string;customer:string;site:string;service:string;date:string;plate:string;files:{id:string;file_name:string;mime_type:string;storage_path:string}[]};
type Settings={accessToken?:string;clientId:string;clientSecret:string;refreshToken:string;rootFolder:string};
const quote=(s:string)=>s.replace(/\\/g,'\\\\').replace(/'/g,"\\'");
export function archiveSegments(m:ExportManifest){const segments=[m.customer,m.site,m.service,m.date,m.plate];if(segments.some(v=>typeof v!=='string'||!v.trim()))throw Error('Заполните заказчика, объект, услугу, дату и госномер рейса');return segments.map(v=>v.trim().slice(0,200))}
export async function exportTripFiles(manifest:ExportManifest,settings:Settings,download:(path:string)=>Promise<Uint8Array>,transport:typeof fetch=fetch){
 const segments=archiveSegments(manifest);if(!manifest.files?.length)throw Error('Нет документов');
 let token:{access_token:string};
 if(settings.accessToken)token={access_token:settings.accessToken};else{
 const tokenResponse=await transport('https://oauth2.googleapis.com/token',{method:'POST',body:new URLSearchParams({client_id:settings.clientId,client_secret:settings.clientSecret,refresh_token:settings.refreshToken,grant_type:'refresh_token'}),signal:AbortSignal.timeout(15000)});
 if(!tokenResponse.ok)throw Error('Google authorization failed');token=await tokenResponse.json();
 }
 async function api(path:string,init:RequestInit={}){const headers=new Headers(init.headers);headers.set('Authorization','Bearer '+token.access_token);const r=await transport('https://www.googleapis.com/'+path,{...init,headers,signal:AbortSignal.timeout(25000)});if(!r.ok)throw Error('Google Drive request failed');return r.json()}
 let parent=settings.rootFolder;
 for(const name of segments){
  const q="trashed=false and mimeType='application/vnd.google-apps.folder' and name='"+quote(name)+"' and '"+quote(parent)+"' in parents";
  const found=await api('drive/v3/files?'+new URLSearchParams({q,fields:'files(id)',supportsAllDrives:'true',includeItemsFromAllDrives:'true',pageSize:'1000'}));
  if(found.files?.length)parent=found.files[0].id;
  else {const created=await api('drive/v3/files?supportsAllDrives=true',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({name,mimeType:'application/vnd.google-apps.folder',parents:[parent]})});parent=created.id}
 }
 for(const file of manifest.files){
  const q="trashed=false and '"+quote(parent)+"' in parents and appProperties has { key='respectlogistic_file' and value='"+quote(file.id)+"' }";
  const existing=await api('drive/v3/files?'+new URLSearchParams({q,fields:'files(id)',supportsAllDrives:'true',includeItemsFromAllDrives:'true'}));if(existing.files?.length)continue;
  const bytes=await download(file.storage_path),boundary='respectlogistic_'+file.id.replace(/-/g,'');
  const metadata={name:file.file_name,parents:[parent],appProperties:{respectlogistic_file:file.id,respectlogistic_trip:manifest.trip_id}};
  const body=new Blob(['--'+boundary+'\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n'+JSON.stringify(metadata)+'\r\n--'+boundary+'\r\nContent-Type: '+file.mime_type+'\r\n\r\n',new Uint8Array(bytes).buffer,'\r\n--'+boundary+'--']);
  await api('upload/drive/v3/files?uploadType=multipart&supportsAllDrives=true',{method:'POST',headers:{'Content-Type':'multipart/related; boundary='+boundary},body});
 }
 return 'https://drive.google.com/drive/folders/'+parent;
}
