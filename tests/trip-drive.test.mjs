import assert from 'node:assert/strict';
import test from 'node:test';
import {archiveSegments,exportTripFiles} from '../lib/trip-drive.ts';
const manifest={trip_id:'trip',version:'version',customer:'ООО Заказчик',site:'Объект',service:'Вывоз грунта',date:'2026-10-23',plate:'А123АА77',files:[{id:'existing',file_name:'ТТН.pdf',mime_type:'application/pdf',storage_path:'owner/trip/existing.pdf'},{id:'new',file_name:'Путевой.pdf',mime_type:'application/pdf',storage_path:'owner/trip/new.pdf'}]};
test('archive requires exactly the requested five levels',()=>{
 assert.deepEqual(archiveSegments(manifest),['ООО Заказчик','Объект','Вывоз грунта','2026-10-23','А123АА77']);
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
  return Response.json({files:q.includes("value='existing'")?[{id:'stored'}]:[]});
 };
 const result=await exportTripFiles(manifest,{clientId:'id',clientSecret:'secret',refreshToken:'refresh',rootFolder:'root'},async path=>{downloads.push(path);return new Uint8Array([1,2,3])},fake);
 assert.equal(folderIndex,5);assert.deepEqual(downloads,['owner/trip/new.pdf']);assert.equal(result,'https://drive.google.com/drive/folders/folder5');assert.equal(requests.filter(r=>r.url.includes('/upload/')).length,1);
 assert.ok(new URL(requests[1].url).searchParams.get('q').includes("'root' in parents"));
});
test('failed Google authorization never reports an archived folder',async()=>{
 await assert.rejects(()=>exportTripFiles(manifest,{clientId:'id',clientSecret:'secret',refreshToken:'refresh',rootFolder:'root'},async()=>{throw Error('must not download')},async()=>new Response('failure',{status:401})),/authorization failed/);
});
