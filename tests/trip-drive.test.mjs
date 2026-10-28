import assert from 'node:assert/strict';
import test from 'node:test';
import {archiveSegments,exportTripFiles,removeDeletedDriveExports} from '../lib/trip-drive.ts';
const manifest={trip_id:'trip',trip_number:'15',version:'version',customer:'ООО Заказчик',site:'Объект',service:'Вывоз грунта',date:'2026-10-23',plate:'А123АА77',files:[{id:'existing',file_name:'ТТН.pdf',mime_type:'application/pdf',storage_path:'owner/trip/existing.pdf'},{id:'new',file_name:'Путевой.pdf',mime_type:'application/pdf',storage_path:'owner/trip/new.pdf'}]};
test('trip archive includes a separate numbered sixth level',()=>{
 assert.deepEqual(archiveSegments(manifest),['ООО Заказчик','Объект','Вывоз грунта','2026-10-23','А123АА77','Рейс №15']);
 assert.throws(()=>archiveSegments({...manifest,plate:''}));
});
test('retry reuses folders and skips previously archived files',async()=>{
 const requests=[],downloads=[];let folderIndex=0;
 const fake=async(url,init={})=>{
  requests.push({url:String(url),init});
  if(String(url).includes('/token'))return Response.json({access_token:'test-token'});
  if(String(url).includes('/upload/')){assert.equal(init.headers.get('Authorization'),'Bearer test-token');assert.ok(init.body instanceof Blob);return Response.json({id:'uploaded'})}
  const q=new URL(url).searchParams.get('q');
  if(q?.includes('mimeType'))return Response.json({files:[{id:'folder'+(++folderIndex)}]});
  return Response.json({files:q.includes("value='existing'")&&!q.includes('respectlogistic_trip')?[{id:'stored'}]:[]});
 };
 const result=await exportTripFiles(manifest,{clientId:'id',clientSecret:'secret',refreshToken:'refresh',rootFolder:'root'},async path=>{downloads.push(path);return new Uint8Array([1,2,3])},fake);
 assert.equal(folderIndex,6);assert.deepEqual(downloads,['owner/trip/new.pdf']);assert.equal(result,'https://drive.google.com/drive/folders/folder6');assert.equal(requests.filter(r=>r.url.includes('/upload/')).length,1);
 assert.ok(new URL(requests[1].url).searchParams.get('q').includes("'root' in parents"));
});
test('failed Google authorization never reports an archived folder',async()=>{
 await assert.rejects(()=>exportTripFiles(manifest,{clientId:'id',clientSecret:'secret',refreshToken:'refresh',rootFolder:'root'},async()=>{throw Error('must not download')},async()=>new Response('failure',{status:401})),/authorization failed/);
});
test('accounting archive keeps its document-number folder and has no fictitious trip level',()=>{
 assert.deepEqual(archiveSegments({...manifest,archive_kind:'accounting',plate:'СЧ-1/2026'}),['ООО Заказчик','Объект','Вывоз грунта','2026-10-23','СЧ-1/2026']);
 assert.notDeepEqual(archiveSegments({...manifest,trip_number:undefined}),archiveSegments({...manifest,trip_id:'another',trip_number:undefined}));
});
test('legacy file moves into its own trip folder without uploading another copy',async()=>{
 const operations=[];let folderIndex=0;
 const fake=async(url,init={})=>{
  operations.push({url:String(url),init});
  if(init.method==='PATCH'){const p=new URL(url).searchParams;assert.equal(p.get('addParents'),'folder6');assert.equal(p.get('removeParents'),'folder5');return Response.json({id:'legacy-file'})}
  const q=new URL(url).searchParams.get('q');if(q.includes('mimeType')){if(folderIndex===5)assert.ok(q.includes("respectlogistic_trip_folder' and value='trip'"));return Response.json({files:[{id:'folder'+(++folderIndex)}]})}
  return Response.json({files:q.includes('respectlogistic_trip')?[{id:'legacy-file',parents:['folder5']}]:[]});
 };
 await exportTripFiles({...manifest,files:[manifest.files[0]]},{accessToken:'test',clientId:'',clientSecret:'',refreshToken:'',rootFolder:'root'},async()=>{throw Error('Must not re-upload legacy file')},fake);
 assert.equal(operations.filter(r=>r.init.method==='PATCH').length,1);assert.equal(operations.filter(r=>r.url.includes('/upload/')).length,0);
});
test('cleanup trashes only tagged deleted entities beneath the configured root and follows pagination',async()=>{
 const removed=[];
 const fake=async(url,init={})=>{
  const u=new URL(url);
  if(init.method==='PATCH'){assert.deepEqual(JSON.parse(init.body),{trashed:true});removed.push(u.pathname.split('/').pop());return Response.json({id:removed.at(-1),trashed:true})}
  if(u.pathname.endsWith('/files')){if(u.searchParams.get('q').includes('respectlogistic_trip_folder'))return Response.json({files:[]});assert.ok(u.searchParams.get('q').includes("value='deleted'"));return Response.json(u.searchParams.get('pageToken')?{files:[{id:'owned-two',parents:['inside'],appProperties:{respectlogistic_trip:'deleted',respectlogistic_file:'file-two'}}]}:{files:[{id:'owned',parents:['inside'],appProperties:{respectlogistic_trip:'deleted',respectlogistic_file:'file'}},{id:'outside',parents:['outside'],appProperties:{respectlogistic_trip:'deleted',respectlogistic_file:'file'}},{id:'manual',parents:['inside'],appProperties:{respectlogistic_trip:'deleted'}},{id:'live',parents:['inside'],appProperties:{respectlogistic_trip:'live',respectlogistic_file:'live-file'}}],nextPageToken:'second'})}
  return Response.json({parents:u.pathname.endsWith('/inside')?['root']:[]});
 };
 assert.equal(await removeDeletedDriveExports('root','token',['deleted'],fake),2);assert.deepEqual(removed,['owned','owned-two']);
});
test('empty deletion set makes no Drive request',async()=>assert.equal(await removeDeletedDriveExports('root','token',[],async()=>{throw Error('Unexpected request')}),0));
test('a prepared numbered folder is adopted only when all its files belong to this trip',async()=>{
 let index=0,tagged=false;const fake=async(url,init={})=>{const q=new URL(url).searchParams.get('q');
  if(init.method==='PATCH'){assert.deepEqual(JSON.parse(init.body),{appProperties:{respectlogistic_trip_folder:'trip'}});tagged=true;return Response.json({id:'prepared'})}
  if(q.includes('mimeType')){if(q.includes("name='Рейс №15'"))return Response.json({files:q.includes('respectlogistic_trip_folder')?[]:[{id:'prepared'}]});return Response.json({files:[{id:'parent'+(++index)}]})}
  if(q.includes("'prepared' in parents")&&!q.includes('respectlogistic_file'))return Response.json({files:[{id:'stored',appProperties:{respectlogistic_trip:'trip'}}]});
  return Response.json({files:[{id:'stored'}]});
 };
 assert.equal(await exportTripFiles({...manifest,files:[manifest.files[0]]},{accessToken:'token',clientId:'',clientSecret:'',refreshToken:'',rootFolder:'root'},async()=>{throw Error('Must reuse file')},fake),'https://drive.google.com/drive/folders/prepared');assert.equal(tagged,true);
});
test('a same-name folder containing another trip is never adopted or modified',async()=>{
 let index=0,created=0;const fake=async(url,init={})=>{const q=new URL(url).searchParams.get('q');
  if(init.method==='PATCH')throw Error('Foreign folder must not be modified');
  if(init.method==='POST'){const body=JSON.parse(init.body);assert.equal(body.appProperties.respectlogistic_trip_folder,'trip');created++;return Response.json({id:'separate'})}
  if(q.includes('mimeType')){if(q.includes("name='Рейс №15'"))return Response.json({files:q.includes('respectlogistic_trip_folder')?[]:[{id:'foreign'}]});return Response.json({files:[{id:'parent'+(++index)}]})}
  if(q.includes("'foreign' in parents"))return Response.json({files:[{id:'foreign-photo',appProperties:{respectlogistic_trip:'other'}}]});
  return Response.json({files:[{id:'stored'}]});
 };
 assert.equal(await exportTripFiles({...manifest,files:[manifest.files[0]]},{accessToken:'token',clientId:'',clientSecret:'',refreshToken:'',rootFolder:'root'},async()=>{throw Error('Must reuse file')},fake),'https://drive.google.com/drive/folders/separate');assert.equal(created,1);
});
test('cleanup removes only empty tagged trip folders, including leftovers from earlier syncs',async()=>{
 const trashed=[],checked=[],events=[];
 const folders=[{id:'empty',parents:['inside'],appProperties:{respectlogistic_trip_folder:'deleted'}},{id:'nonempty',parents:['inside'],appProperties:{respectlogistic_trip_folder:'deleted'}},{id:'manual',parents:['inside'],appProperties:{}},{id:'outside',parents:['elsewhere'],appProperties:{respectlogistic_trip_folder:'deleted'}},{id:'live',parents:['inside'],appProperties:{respectlogistic_trip_folder:'live'}},{id:'root',parents:['inside'],appProperties:{respectlogistic_trip_folder:'deleted'}}];
 const fake=async(url,init={})=>{const u=new URL(url),q=u.searchParams.get('q')||'';
  if(init.method==='PATCH'){assert.deepEqual(JSON.parse(init.body),{trashed:true});trashed.push(u.pathname.split('/').pop());events.push('trash:'+trashed.at(-1));return Response.json({id:trashed.at(-1)})}
  if(u.pathname.endsWith('/files')){
   if(q.includes('respectlogistic_trip_folder'))return Response.json(u.searchParams.get('pageToken')?{files:[{id:'older-empty',parents:['inside'],appProperties:{respectlogistic_trip_folder:'deleted'}},{id:'uncertain',parents:['inside'],appProperties:{respectlogistic_trip_folder:'deleted'}}]}:{files:folders,nextPageToken:'second'});
   if(q.includes("mimeType!='"))return Response.json({files:[{id:'photo',parents:['empty'],appProperties:{respectlogistic_trip:'deleted',respectlogistic_file:'photo'}}]});
   const id=q.match(/'([^']+)' in parents/)[1];checked.push(id);events.push('check:'+id);
   if(id==='nonempty')return Response.json({files:[{id:'manual-file'}]});
   if(id==='uncertain')return Response.json({files:[],incompleteSearch:true});
   return Response.json({files:[]});
  }
  return Response.json({parents:u.pathname.endsWith('/empty')?['inside']:u.pathname.endsWith('/inside')?['root']:[]});
 };
 assert.equal(await removeDeletedDriveExports('root','token',['deleted'],fake),1);
 assert.deepEqual(trashed,['photo','empty','older-empty']);assert.deepEqual(checked,['empty','nonempty','older-empty','uncertain']);assert.ok(events.indexOf('trash:photo')<events.indexOf('check:empty'));
});
test('a failed folder-content check never trashes the folder',async()=>{
 let patched=false;
 const fake=async(url,init={})=>{const u=new URL(url),q=u.searchParams.get('q')||'';if(init.method==='PATCH'){patched=true;throw Error('Must not trash')}
  if(q.includes('respectlogistic_trip_folder'))return Response.json({files:[{id:'leaf',parents:['root'],appProperties:{respectlogistic_trip_folder:'deleted'}}]});
  if(q.includes("mimeType!='"))return Response.json({files:[]});
  return new Response('unavailable',{status:503});
 };
 await assert.rejects(()=>removeDeletedDriveExports('root','token',['deleted'],fake),/Не удалось/);assert.equal(patched,false);
});
