import {createHash} from 'node:crypto';
import {CRM_ORIGIN,googleCookie,googleState,googleAuthorization,ownerRpc,googleAccessToken} from '../../../lib/google-sync-server.ts';
import {registryTabs} from '../../../lib/crm-register.ts';import {accountingHtml} from '../../../lib/accounting.ts';import {exportTripFiles} from '../../../lib/trip-drive.ts';
export const dynamic='force-dynamic';export const runtime='nodejs';
export async function POST(request:Request){const authorization=request.headers.get('authorization')||'';if(!authorization.startsWith('Bearer '))return Response.json({message:'Войдите как администратор'},{status:401});
 try{const body=await request.json();if(body.action==='status')return Response.json(await ownerRpc(authorization,'respectlogistic_google_settings'),{headers:{'Cache-Control':'no-store, private'}});
 if(body.action==='connect'){
  if(body.clientId)await ownerRpc(authorization,'respectlogistic_google_settings',{p_action:'save',p_record:{clientId:body.clientId,clientSecret:body.clientSecret||''}});
  const cfg=await ownerRpc(authorization,'respectlogistic_google_settings',{p_action:'credentials'});if(!cfg.clientId||!cfg.clientSecret)throw Error('Сначала укажите Client ID и Client Secret OAuth-клиента Google');const session=googleState(authorization);
  return Response.json({url:googleAuthorization(cfg.clientId,CRM_ORIGIN,session)},{headers:{'Cache-Control':'no-store','Set-Cookie':googleCookie(Buffer.from(JSON.stringify(session)).toString('base64url'))}});
 }
 if(body.action!=='sync')return Response.json({message:'Действие недоступно'},{status:400});
 const cfg=await ownerRpc(authorization,'respectlogistic_google_settings',{p_action:'credentials'});const accessToken=await googleAccessToken(cfg);
 const api=async(path:string,init:RequestInit={})=>{const headers=new Headers(init.headers);headers.set('Authorization','Bearer '+accessToken);const r=await fetch('https://sheets.googleapis.com/'+path.replace(/^sheets\//,''),{...init,headers,cache:'no-store',signal:AbortSignal.timeout(30000)});const value=await r.json();if(!r.ok)throw Error('Google не разрешил выгрузку. Проверьте доступ к папке, включение Google Drive API и Google Sheets API.');return value};
 const [workspace,accounting,extras]=await Promise.all([ownerRpc(authorization,'crm_read_trip_workspace'),ownerRpc(authorization,'respectlogistic_read_accounting'),ownerRpc(authorization,'respectlogistic_driver_extras')]);
 const base=process.env.NEXT_PUBLIC_SUPABASE_URL!,key=process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!;
 const fileResponse=await fetch(base+'/rest/v1/rl_crm_trip_files?select=*',{headers:{Authorization:authorization,apikey:key},cache:'no-store',signal:AbortSignal.timeout(30000)});if(!fileResponse.ok)throw Error('Не удалось получить документы рейсов');const nativeFiles=await fileResponse.json();
 const files=[...nativeFiles,...(extras.shift_files||[]).filter((f:{trip_id:string})=>f.trip_id).map((f:{id:string})=>({...f,storage_path:'shift:'+f.id,doc_type:'ttn'}))];
 const folders:Record<string,string>={};let exported=0;
 for(const trip of workspace.trips){
  const docs=accounting.documents.filter((d:{id:string})=>accounting.links.some((l:{document_id:string;trip_id:string})=>l.document_id===d.id&&l.trip_id===trip.id));
  const attached=[...files.filter(f=>f.trip_id===trip.id),...docs.map((d:{id:string;number:string})=>({id:d.id+createHash('sha256').update(JSON.stringify(d)).digest('hex').slice(0,12),file_name:d.number+'.html',mime_type:'text/html',storage_path:'accounting:'+d.id}))];
  if(!attached.length)continue;
  const customer=workspace.customers.find((c:{id:string})=>c.id===trip.customer_id),site=workspace.sites.find((s:{id:string})=>s.id===trip.site_id),vehicle=workspace.vehicles.find((v:{id:string})=>v.id===trip.vehicle_id);
  const folder=await exportTripFiles({trip_id:trip.id,version:trip.modified_at,customer:customer?.name||'Заказчик',site:site?.name||'Объект',service:trip.service_name||'Услуга',date:trip.trip_date,plate:vehicle?.plate||'Машина',files:attached},{clientId:cfg.clientId,clientSecret:cfg.clientSecret,refreshToken:cfg.refreshToken,rootFolder:cfg.rootFolder,accessToken},async path=>{
   if(path.startsWith('accounting:')){const d=accounting.documents.find((d:{id:string})=>d.id===path.slice(11));return new TextEncoder().encode(accountingHtml(d))}
   if(path.startsWith('shift:')){const f=await ownerRpc(authorization,'respectlogistic_driver_file',{p_id:path.slice(6)});return new Uint8Array(Buffer.from(f.base64,'base64'))}
   const r=await fetch(base+'/storage/v1/object/authenticated/respectlogistic-trip-documents/'+path,{headers:{Authorization:authorization,apikey:key},signal:AbortSignal.timeout(30000)});if(!r.ok)throw Error('Файл рейса недоступен');return new Uint8Array(await r.arrayBuffer());
  });folders[trip.id]=folder;exported+=attached.length;
 }
 const documentFolders:Record<string,string>={};
 // Standalone accounting archive also covers advances and documents whose source trip was removed.
 for(const d of accounting.documents){const customer=workspace.customers.find((c:{id:string})=>c.id===d.customer_id),site=workspace.sites.find((s:{id:string})=>s.id===d.site_id);const id=d.id+createHash('sha256').update(JSON.stringify(d)).digest('hex').slice(0,12);documentFolders[d.id]=await exportTripFiles({trip_id:d.id,version:d.modified_at,customer:customer?.name||d.snapshot.customer.name||'Заказчик',site:site?.name||'Все объекты',service:'Бухгалтерия',date:d.document_date,plate:d.number,files:[{id,file_name:d.number+'.html',mime_type:'text/html',storage_path:'accounting:'+d.id}]},{clientId:cfg.clientId,clientSecret:cfg.clientSecret,refreshToken:cfg.refreshToken,rootFolder:cfg.rootFolder,accessToken},async()=>new TextEncoder().encode(accountingHtml(d)));}
 const tabs=registryTabs({...workspace,documents:accounting.documents,links:accounting.links,files,folders,documentFolders});
 const info=await api('sheets/v4/spreadsheets/'+cfg.spreadsheetId+'?fields=sheets(properties)');const requests=[];const used=new Set<number>(info.sheets.map((s:{properties:{sheetId:number}})=>s.properties.sheetId));
 for(const tab of tabs){let existing=info.sheets.find((s:{properties:{title:string}})=>s.properties.title===tab.title);if(!existing){let id=1;while(used.has(id))id++;used.add(id);existing={properties:{sheetId:id,title:tab.title}};requests.push({addSheet:{properties:{sheetId:id,title:tab.title,gridProperties:{rowCount:Math.max(1000,tab.rows.length+50),columnCount:tab.rows[0].length,frozenRowCount:1}}}})}const sheetId=existing.properties.sheetId;
  const grid=existing.properties.gridProperties;requests.push({updateSheetProperties:{properties:{sheetId,gridProperties:{rowCount:Math.max(grid?.rowCount||1000,tab.rows.length+50),columnCount:Math.max(grid?.columnCount||tab.rows[0].length,tab.rows[0].length),frozenRowCount:1}},fields:'gridProperties'}});
  requests.push({repeatCell:{range:{sheetId,startRowIndex:0,startColumnIndex:0,endRowIndex:tab.rows.length,endColumnIndex:tab.rows[0].length},cell:{userEnteredFormat:{wrapStrategy:'WRAP',verticalAlignment:'TOP'}},fields:'userEnteredFormat.wrapStrategy,userEnteredFormat.verticalAlignment'}});
  requests.push({setBasicFilter:{filter:{range:{sheetId,startRowIndex:0,endRowIndex:tab.rows.length,startColumnIndex:0,endColumnIndex:tab.rows[0].length}}}});
  requests.push({updateCells:{range:{sheetId,startRowIndex:0,startColumnIndex:0},fields:'userEnteredValue'}});
  requests.push({updateCells:{start:{sheetId,rowIndex:0,columnIndex:0},rows:tab.rows.map(row=>({values:row.map(v=>({userEnteredValue:typeof v==='number'?{numberValue:v}:{stringValue:String(v??'')},...(typeof v==='string'&&/^https:\/\/(respectlogistic\.onrender\.com|drive\.google\.com)\//.test(v)?{textFormatRuns:[{startIndex:0,format:{link:{uri:v}}}]}:{})}))})),fields:'userEnteredValue,textFormatRuns'}});
  requests.push({repeatCell:{range:{sheetId,startRowIndex:0,endRowIndex:1,startColumnIndex:0,endColumnIndex:tab.rows[0].length},cell:{userEnteredFormat:{backgroundColor:{red:.93,green:.94,blue:.94},textFormat:{bold:true,foregroundColor:{red:0,green:0,blue:0}},wrapStrategy:'WRAP'}},fields:'userEnteredFormat'}});
  requests.push({updateDimensionProperties:{range:{sheetId,dimension:'COLUMNS',startIndex:0,endIndex:tab.rows[0].length},properties:{pixelSize:170},fields:'pixelSize'}});
 }
 await api('sheets/v4/spreadsheets/'+cfg.spreadsheetId+':batchUpdate',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({requests})});await ownerRpc(authorization,'respectlogistic_google_settings',{p_action:'synced'});
 return Response.json({ok:true,trips:workspace.trips.length,documents:accounting.documents.length,files:exported,sheetUrl:'https://docs.google.com/spreadsheets/d/'+cfg.spreadsheetId+'/edit'},{headers:{'Cache-Control':'no-store, private'}});
 }catch(e){const message=e instanceof Error?e.message:'Не удалось выполнить синхронизацию';try{await ownerRpc(authorization,'respectlogistic_google_settings',{p_action:'error',p_record:{message}})}catch{}return Response.json({message},{status:400,headers:{'Cache-Control':'no-store'}})}
}
