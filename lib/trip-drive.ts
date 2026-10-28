export type ExportManifest={trip_id:string;trip_number?:string;archive_kind?:'trip'|'accounting';version:string;customer:string;site:string;service:string;date:string;plate:string;files:{id:string;file_name:string;mime_type:string;storage_path:string}[]};
type Settings={accessToken?:string;clientId:string;clientSecret:string;refreshToken:string;rootFolder:string};
const quote=(s:string)=>s.replace(/\\/g,'\\\\').replace(/'/g,"\\'");
export function archiveSegments(m:ExportManifest){const segments=[m.customer,m.site,m.service,m.date,m.plate];if(segments.some(v=>typeof v!=='string'||!v.trim()))throw Error('Заполните заказчика, объект, услугу, дату и госномер рейса');return [...segments,...(m.archive_kind==='accounting'?[]:['Рейс №'+(m.trip_number?.trim()||m.trip_id)])].map(v=>v.trim().slice(0,200))}
export async function exportTripFiles(manifest:ExportManifest,settings:Settings,download:(path:string)=>Promise<Uint8Array>,transport:typeof fetch=fetch){
 const segments=archiveSegments(manifest);if(!manifest.files?.length)throw Error('Нет документов');
 let token:{access_token:string};
 if(settings.accessToken)token={access_token:settings.accessToken};else{
 const tokenResponse=await transport('https://oauth2.googleapis.com/token',{method:'POST',body:new URLSearchParams({client_id:settings.clientId,client_secret:settings.clientSecret,refresh_token:settings.refreshToken,grant_type:'refresh_token'}),signal:AbortSignal.timeout(15000)});
 if(!tokenResponse.ok)throw Error('Google authorization failed');token=await tokenResponse.json();
 }
 async function api(path:string,init:RequestInit={}){const headers=new Headers(init.headers);headers.set('Authorization','Bearer '+token.access_token);const r=await transport('https://www.googleapis.com/'+path,{...init,headers,signal:AbortSignal.timeout(25000)});if(!r.ok)throw Error('Google Drive request failed');return r.json()}
 let parent=settings.rootFolder;
 let legacyParent='';
 for(const [index,name] of segments.entries()){
  const leaf=manifest.archive_kind!=='accounting'&&index===segments.length-1;if(leaf)legacyParent=parent;
  const folderQuery="trashed=false and mimeType='application/vnd.google-apps.folder' and name='"+quote(name)+"' and '"+quote(parent)+"' in parents";
  const q=folderQuery+(leaf?" and appProperties has { key='respectlogistic_trip_folder' and value='"+quote(manifest.trip_id)+"' }":'');
  const found=await api('drive/v3/files?'+new URLSearchParams({q,fields:'files(id)',supportsAllDrives:'true',includeItemsFromAllDrives:'true',pageSize:'1000'}));
  if(leaf&&!found.files?.length){
   const candidates=await api('drive/v3/files?'+new URLSearchParams({q:folderQuery,fields:'files(id,appProperties)',supportsAllDrives:'true',includeItemsFromAllDrives:'true'}));
   for(const candidate of candidates.files||[]){
    if(candidate.appProperties?.respectlogistic_trip_folder)continue;
    const contents=await api('drive/v3/files?'+new URLSearchParams({q:"trashed=false and '"+quote(candidate.id)+"' in parents",fields:'files(id,appProperties),nextPageToken',pageSize:'1000',supportsAllDrives:'true',includeItemsFromAllDrives:'true'}));
    if(contents.nextPageToken||(contents.files||[]).some((f:{appProperties?:Record<string,string>})=>f.appProperties?.respectlogistic_trip!==manifest.trip_id))continue;
    await api('drive/v3/files/'+encodeURIComponent(candidate.id)+'?supportsAllDrives=true&fields=id',{method:'PATCH',headers:{'Content-Type':'application/json'},body:JSON.stringify({appProperties:{respectlogistic_trip_folder:manifest.trip_id}})});found.files=[{id:candidate.id}];break;
   }
  }
  if(found.files?.length)parent=found.files[0].id;
  else {const created=await api('drive/v3/files?supportsAllDrives=true',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({name,mimeType:'application/vnd.google-apps.folder',parents:[parent],...(leaf?{appProperties:{respectlogistic_trip_folder:manifest.trip_id}}:{})})});parent=created.id}
 }
 for(const file of manifest.files){
  const q="trashed=false and '"+quote(parent)+"' in parents and appProperties has { key='respectlogistic_file' and value='"+quote(file.id)+"' }";
  const existing=await api('drive/v3/files?'+new URLSearchParams({q,fields:'files(id)',supportsAllDrives:'true',includeItemsFromAllDrives:'true'}));if(existing.files?.length)continue;
  if(legacyParent){
   const oldQuery="trashed=false and '"+quote(legacyParent)+"' in parents and appProperties has { key='respectlogistic_file' and value='"+quote(file.id)+"' } and appProperties has { key='respectlogistic_trip' and value='"+quote(manifest.trip_id)+"' }";
   const previous=await api('drive/v3/files?'+new URLSearchParams({q:oldQuery,fields:'files(id,parents)',supportsAllDrives:'true',includeItemsFromAllDrives:'true'}));
   if(previous.files?.length){for(const old of previous.files){if(!old.parents?.includes(legacyParent))throw Error('Не удалось проверить расположение старого файла');await api('drive/v3/files/'+encodeURIComponent(old.id)+'?'+new URLSearchParams({addParents:parent,removeParents:legacyParent,supportsAllDrives:'true',fields:'id'}),{method:'PATCH',headers:{'Content-Type':'application/json'},body:'{}'})}continue;}
  }
  const bytes=await download(file.storage_path),boundary='respectlogistic_'+file.id.replace(/-/g,'');
  const metadata={name:file.file_name,parents:[parent],appProperties:{respectlogistic_file:file.id,respectlogistic_trip:manifest.trip_id}};
  const body=new Blob(['--'+boundary+'\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n'+JSON.stringify(metadata)+'\r\n--'+boundary+'\r\nContent-Type: '+file.mime_type+'\r\n\r\n',new Uint8Array(bytes).buffer,'\r\n--'+boundary+'--']);
  await api('upload/drive/v3/files?uploadType=multipart&supportsAllDrives=true',{method:'POST',headers:{'Content-Type':'multipart/related; boundary='+boundary},body});
 }
 return 'https://drive.google.com/drive/folders/'+parent;
}

// Reconcile only positive tombstones from the owner's CRM, and only our tagged files under this root.
// An incomplete list or a manually uploaded neighbour must never be treated as a deletion.
export async function removeDeletedDriveExports(rootFolder:string,accessToken:string,excludedEntityIds:string[],transport:typeof fetch=fetch){
 const excluded=new Set(excludedEntityIds);if(!excluded.size)return 0;
 async function api(path:string,init:RequestInit={}){const headers=new Headers(init.headers);headers.set('Authorization','Bearer '+accessToken);const r=await transport('https://www.googleapis.com/drive/v3/'+path,{...init,headers,signal:AbortSignal.timeout(25000)});if(!r.ok)throw Error('Не удалось обновить удалённые документы на Google Диске');return r.json()}
 const parents=new Map<string,string[]>();
 async function inRoot(ids:string[]){const visited=new Set<string>(),pending=[...ids];while(pending.length){const id=pending.pop()!;if(id===rootFolder)return true;if(visited.has(id))continue;visited.add(id);if(visited.size>100)throw Error('Не удалось проверить папку документа');if(!parents.has(id)){const meta=await api('files/'+encodeURIComponent(id)+'?fields=id,parents&supportsAllDrives=true');parents.set(id,meta.parents||[])}pending.push(...parents.get(id)!)}return false}
 let removed=0;const ids=[...excluded];
 for(let i=0;i<ids.length;i+=20){let pageToken='';do{
  const condition=ids.slice(i,i+20).map(id=>"appProperties has { key='respectlogistic_trip' and value='"+quote(id)+"' }").join(' or ');
  const query=new URLSearchParams({q:"trashed=false and mimeType!='application/vnd.google-apps.folder' and ("+condition+")",fields:'files(id,parents,appProperties),nextPageToken',pageSize:'100',supportsAllDrives:'true',includeItemsFromAllDrives:'true',...(pageToken?{pageToken}:{})});
  const page=await api('files?'+query);for(const f of page.files||[]){if(!f.appProperties?.respectlogistic_file||!excluded.has(f.appProperties.respectlogistic_trip)||!await inRoot(f.parents||[]))continue;await api('files/'+encodeURIComponent(f.id)+'?supportsAllDrives=true&fields=id,trashed',{method:'PATCH',headers:{'Content-Type':'application/json'},body:JSON.stringify({trashed:true})});removed++}pageToken=page.nextPageToken||'';
 }while(pageToken)}return removed;
}
