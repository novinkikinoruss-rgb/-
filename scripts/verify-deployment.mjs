import assert from 'node:assert/strict';
const origin='https://respectlogistic.onrender.com';
async function get(path,options={}){
 const response=await fetch(new URL(path,origin),{...options,signal:AbortSignal.timeout(20000)});
 return response;
}
let ready=false;
for(let attempt=1;attempt<=30;attempt++){
 try{const response=await get('/api/health');const data=await response.json();assert.equal(response.status,200);assert.equal(data.status,'ok');assert.equal(data.service,'respectlogistic');ready=true;console.log('Public health endpoint: OK');break;}
 catch(error){console.log(`Waiting for Render ${attempt}/30: ${error.message}`);if(attempt<30)await new Promise(resolve=>setTimeout(resolve,10000));}
}
assert.ok(ready,'Render must become available');
const response=await get('/');assert.equal(response.status,200);const html=await response.text();
assert.ok(html.includes('Вход в рабочее пространство'),'Deployed app must require real authentication');
assert.ok(!html.includes('данные сохраняются в этом браузере'),'Production must not show preview data');
console.log('Production login page and cloud mode: OK');
const scripts=[...new Set([...html.matchAll(/<script[^>]+src="([^"]+\.js(?:\?[^"]*)?)"/g)].map(match=>match[1].replaceAll('&amp;','&')))];
const bundles=await Promise.all(scripts.map(async path=>{assert.equal(new URL(path,origin).origin,origin);const r=await get(path);assert.equal(r.status,200);return r.text();}));
for(const marker of ['respectlogistic_customer_action','respectlogistic_read_workspace','yoqejkedmksmvbqagqru.supabase.co'])assert.ok(bundles.some(bundle=>bundle.includes(marker)),`Expected cloud configuration: ${marker}`);
console.log('Customer module and intended Supabase configuration in deployed bundles: OK');
const supabase='https://yoqejkedmksmvbqagqru.supabase.co';
const key='sb_publishable_qnb1bLiXSsB-9VuwFMtCiQ_07nL4hyQ';
const settings=await fetch(supabase+'/auth/v1/settings',{headers:{apikey:key},signal:AbortSignal.timeout(15000)});assert.equal(settings.status,200);
const denied=await fetch(supabase+'/rest/v1/rpc/respectlogistic_read_workspace',{method:'POST',headers:{apikey:key,'Content-Type':'application/json'},body:'{}',signal:AbortSignal.timeout(15000)});
assert.ok([401,403].includes(denied.status),'Anonymous access to customer data must be denied');
console.log('Supabase Auth reachable; customer API rejects anonymous reads: OK');
