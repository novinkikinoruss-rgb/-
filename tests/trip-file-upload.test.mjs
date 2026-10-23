import assert from 'node:assert/strict';
import test from 'node:test';
import {handleTripFileUpload} from '../lib/trip-file-upload.ts';
const owner='11111111-1111-4111-8111-111111111111',trip='22222222-2222-4222-8222-222222222222',upload='33333333-3333-4333-8333-333333333333';
const config={base:'https://example.supabase.co',key:'public-test-key'};
function request(content='%PDF-1.4\n',kind='ttn',filename='Накладная.pdf'){
 const body=new FormData();body.set('tripId',trip);body.set('uploadId',upload);body.set('kind',kind);body.set('file',new File([content],filename,{type:''}));
 return new Request('https://crm.example/api/trip-files',{method:'POST',headers:{Authorization:'Bearer user-token'},body});
}
function backend({hasTrip=true,register=true,existing=false,content='%PDF-1.4\n',extension='pdf'}={}){
 const calls=[];return {calls,transport:async(url,init)=>{
  const path=String(url);calls.push({url:path,init});assert.equal(init.headers.get('Authorization'),'Bearer user-token');assert.equal(init.headers.get('apikey'),'public-test-key');
  if(path.endsWith('/auth/v1/user'))return Response.json({id:owner});
  if(path.includes('/rl_crm_trips?'))return Response.json(hasTrip?[{id:trip}]:[]);
  if(path.includes('/rl_crm_trip_files?'))return Response.json(existing?[{id:'saved'}]:[]);
  if(path.includes('/rpc/'))return register?Response.json('saved'):Response.json({message:'failed'},{status:500});
  if(init.method==='POST'){assert.equal(init.headers.get('Content-Type'),'application/octet-stream');assert.equal(new TextDecoder().decode(init.body),content);assert.ok(path.endsWith(owner+'/'+trip+'/'+upload+'.'+extension))}
  return Response.json({});
 }};
}
test('mobile file without MIME type uploads actual bytes and registers against an owned app trip',async()=>{
 const mock=backend();const response=await handleTripFileUpload(request(),config,mock.transport);assert.equal(response.status,200);assert.equal((await response.json()).saved,true);assert.equal(mock.calls.length,5);
 const registration=JSON.parse(mock.calls[4].init.body);assert.equal(registration.p_trip_id,trip);assert.equal(registration.p_type,'ttn');assert.equal(registration.p_name,'Накладная.pdf');
});
test('foreign trip never reaches storage',async()=>{
 const mock=backend({hasTrip:false});assert.equal((await handleTripFileUpload(request(),config,mock.transport)).status,404);assert.equal(mock.calls.length,2);
});
test('all file formats including Office, archives, HEIC and files without an extension retain original bytes and names',async()=>{
 for(const [filename,extension] of [['Смета.docx','docx'],['Реестр.xlsx','xlsx'],['Архив.zip','zip'],['Фото.HEIC','heic'],['Документ.html','html'],['binary.custom','custom'],['Без расширения','bin']]){
  const content='original bytes '+filename,mock=backend({content,extension});
  const response=await handleTripFileUpload(request(content,'other',filename),config,mock.transport);
  assert.equal(response.status,200,filename);assert.equal(JSON.parse(mock.calls[4].init.body).p_name,filename);
 }
});
test('empty file is rejected before storage',async()=>{
 const mock=backend();assert.equal((await handleTripFileUpload(request(''),config,mock.transport)).status,413);assert.equal(mock.calls.length,1);
});
test('failed registration cleans up only the newly uploaded object',async()=>{
 const mock=backend({register:false});assert.equal((await handleTripFileUpload(request(),config,mock.transport)).status,502);assert.equal(mock.calls.at(-1).init.method,'DELETE');assert.deepEqual(JSON.parse(mock.calls.at(-1).init.body),{prefixes:[owner+'/'+trip+'/'+upload+'.pdf']});
});
test('repeat of a registered upload returns success without another storage write',async()=>{
 const mock=backend({existing:true});assert.equal((await handleTripFileUpload(request(),config,mock.transport)).status,200);assert.equal(mock.calls.length,3);
});
test('unauthenticated request cannot read a body or contact the database',async()=>{
 let calls=0;assert.equal((await handleTripFileUpload(new Request('https://crm.example',{method:'POST'}),config,async()=>{calls++;throw Error('unexpected')})).status,401);assert.equal(calls,0);
});
