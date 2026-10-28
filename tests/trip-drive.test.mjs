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
  if(u.pathname.endsWith('/files')){assert.ok(u.searchParams.get('q').includes("value='deleted'"));return Response.json(u.searchParams.get('pageToken')?{files:[{id:'owned-two',parents:['inside'],appProperties:{respectlogistic_trip:'deleted',respectlogistic_file:'file-two'}}]}:{files:[{id:'owned',parents:['inside'],appProperties:{respectlogistic_trip:'deleted',respectlogistic_file:'file'}},{id:'outside',parents:['outside'],appProperties:{respectlogistic_trip:'deleted',respectlogistic_file:'file'}},{id:'manual',parents:['inside'],appProperties:{respectlogistic_trip:'deleted'}},{id:'live',parents:['inside'],appProperties:{respectlogistic_trip:'live',respectlogistic_file:'live-file'}}],nextPageToken:'second'})}
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
