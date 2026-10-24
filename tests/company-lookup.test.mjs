import assert from 'node:assert/strict';
import test from 'node:test';
import {handleCompanyLookup} from '../lib/company-lookup.ts';
const config={base:'https://auth.example',key:'public-key',token:'server-secret'};
const party={'ИНН':'7707083893','КПП':'773601001','ОГРН':'1027700132195','НаимСокр':'ПАО Сбербанк','НаимПолн':'ПАО Сбербанк полное','ЮрАдрес':{'АдресРФ':'Москва'},'Руковод':[{'ФИО':'Первый руководитель'},{'ФИО':'Второй руководитель'}]};
function req(body,auth=true){return new Request('https://crm.example/api/company',{method:'POST',headers:auth?{Authorization:'Bearer user-token'}:{},body:JSON.stringify(body)})}
function mock(status=200,data=party,meta={status:'ok'}){const calls=[];return {calls,fetch:async(url,init)=>{calls.push({url,init});if(url.startsWith(config.base)){assert.equal(init.headers.Authorization,'Bearer user-token');return Response.json({id:'user'})}const u=new URL(url);assert.equal(u.origin,'https://api.checko.ru');assert.equal(u.searchParams.get('key'),config.token);assert.equal(u.searchParams.get('inn'),party['ИНН']);assert.equal(init.redirect,'error');return Response.json({meta,data},{status})}}}
test('verified user gets Checko details; credentials and unrelated data never leave server',async()=>{
 const m=mock(),r=await handleCompanyLookup(req({query:party['ИНН']}),config,m.fetch),body=await r.json();assert.equal(r.status,200);assert.equal(body.suggestions[0].inn,party['ИНН']);assert.equal(body.suggestions[0].legalAddress,'Москва');assert.equal(body.suggestions[0].director,'Первый руководитель; Второй руководитель');assert.ok(m.calls[1].url.includes('/v2/company?'));assert.ok(!JSON.stringify(body).includes(config.token));assert.equal(r.headers.get('cache-control'),'no-store');
});
test('exact INN returns company and rejects unrelated provider matches',async()=>{
 const m=mock();assert.equal((await (await handleCompanyLookup(req({inn:party['ИНН']}),config,m.fetch)).json()).company.kpp,party['КПП']);
 assert.equal((await handleCompanyLookup(req({inn:party['ИНН']}),config,mock(200,{...party,'ИНН':'7700000009'}).fetch)).status,502);
});
test('anonymous and invalid sessions never call Checko',async()=>{
 let calls=0;const f=async()=>{calls++;return Response.json({},{status:401})};assert.equal((await handleCompanyLookup(req({},false),config,f)).status,401);assert.equal(calls,0);assert.equal((await handleCompanyLookup(req({inn:party['ИНН']}),config,f)).status,401);assert.equal(calls,1);
});
test('missing token, invalid INN, provider limits, empty results and errors are explicit',async()=>{
 assert.equal((await handleCompanyLookup(req({inn:party['ИНН']}),{...config,token:''},mock().fetch)).status,503);
 for(const body of [{query:'Название'},{query:42},{inn:'123'},{inn:'7700000000'},{query:'a'.repeat(1001)}]){const m=mock();assert.equal((await handleCompanyLookup(req(body),config,m.fetch)).status,400);assert.equal(m.calls.length,1)}
 for(const status of [429,402])assert.equal((await handleCompanyLookup(req({inn:party['ИНН']}),config,mock(status).fetch)).status,429);
 assert.equal((await handleCompanyLookup(req({inn:party['ИНН']}),config,mock(403).fetch)).status,503);
 assert.equal((await handleCompanyLookup(req({inn:party['ИНН']}),config,mock(200,{}).fetch)).status,404);
 const r=await handleCompanyLookup(req({inn:party['ИНН']}),config,mock(200,party,{status:'error',message:'secret server-secret'}).fetch);assert.equal(r.status,502);assert.ok(!(await r.text()).includes('server-secret'));
});
test('provider transport exceptions never expose a credential-bearing URL',async()=>{
 let calls=0;const r=await handleCompanyLookup(req({inn:party['ИНН']}),config,async()=>{if(++calls===1)return Response.json({id:'user'});throw Error('https://api.checko.ru/?key=server-secret')});assert.equal(r.status,502);assert.ok(!(await r.text()).includes('server-secret'));
});
