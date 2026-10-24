import assert from 'node:assert/strict';
import test from 'node:test';
import {handleCompanyLookup} from '../lib/company-lookup.ts';
const config={base:'https://auth.example',key:'public-key',token:'server-secret'};
const party={inn:'7707083893',kpp:'773601001',ogrn:'1027700132195',name:{short_with_opf:'ПАО Сбербанк',full_with_opf:'ПАО Сбербанк полное'},address:{unrestricted_value:'Москва'},management:{name:'Руководитель'}};
function req(body,auth=true){return new Request('https://crm.example/api/company',{method:'POST',headers:auth?{Authorization:'Bearer user-token'}:{},body:JSON.stringify(body)})}
function mock(status=200,suggestions=[{data:party}]){const calls=[];return {calls,fetch:async(url,init)=>{calls.push({url,init});if(url.startsWith(config.base)){assert.equal(init.headers.Authorization,'Bearer user-token');return Response.json({id:'user'})}assert.equal(init.headers.Authorization,'Token server-secret');return Response.json({suggestions},{status})}}}
test('verified user can search name, receives only card fields; token stays server side',async()=>{
 const m=mock(),r=await handleCompanyLookup(req({query:'Сбербанк'}),config,m.fetch),body=await r.json();assert.equal(r.status,200);assert.equal(body.suggestions[0].inn,party.inn);assert.equal(body.suggestions[0].legalAddress,'Москва');assert.ok(m.calls[1].url.endsWith('/suggest/party'));assert.equal(JSON.parse(m.calls[1].init.body).type,'LEGAL');assert.ok(!JSON.stringify(body).includes(config.token));assert.equal(r.headers.get('cache-control'),'no-store');
});
test('exact INN maps details and rejects unrelated provider matches',async()=>{
 const m=mock();assert.equal((await (await handleCompanyLookup(req({inn:party.inn}),config,m.fetch)).json()).company.kpp,party.kpp);assert.ok(m.calls[1].url.endsWith('/findById/party'));
 assert.equal((await handleCompanyLookup(req({inn:'7700000009'}),config,m.fetch)).status,404);
});
test('anonymous and invalid sessions never call DaData',async()=>{
 let calls=0;const f=async()=>{calls++;return Response.json({},{status:401})};assert.equal((await handleCompanyLookup(req({},false),config,f)).status,401);assert.equal(calls,0);assert.equal((await handleCompanyLookup(req({query:'Сбербанк'}),config,f)).status,401);assert.equal(calls,1);
});
test('missing token, malformed input, provider limits and empty results are explicit',async()=>{
 assert.equal((await handleCompanyLookup(req({query:'Сбербанк'}),{...config,token:''},mock().fetch)).status,503);
 for(const body of [{query:'аб'},{query:42},{inn:'123'},{query:'a'.repeat(1001)}]){const m=mock();assert.equal((await handleCompanyLookup(req(body),config,m.fetch)).status,400);assert.equal(m.calls.length,1)}
 assert.equal((await handleCompanyLookup(req({query:'Сбербанк'}),config,mock(429).fetch)).status,429);
 assert.equal((await handleCompanyLookup(req({query:'Сбербанк'}),config,mock(403).fetch)).status,502);
 assert.deepEqual(await (await handleCompanyLookup(req({query:'Нет компании'}),config,mock(200,[]).fetch)).json(),{suggestions:[]});
});
