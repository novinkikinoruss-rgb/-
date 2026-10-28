import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {googleCookie,googleState,googleAuthorization,googleAccessToken,ownerRpc} from '../lib/google-sync-server.ts';
const a=googleState('Bearer fixture'),b=googleState('Bearer fixture');assert.notEqual(a.state,b.state);assert.notEqual(a.verifier,b.verifier);
const url=new URL(googleAuthorization('client.apps.googleusercontent.com','https://respectlogistic.onrender.com',a));assert.equal(url.origin,'https://accounts.google.com');assert.equal(url.searchParams.get('redirect_uri'),'https://respectlogistic.onrender.com/api/google-sync/callback');assert.equal(url.searchParams.get('code_challenge'),createHash('sha256').update(a.verifier).digest('base64url'));assert.equal(url.searchParams.get('code_challenge_method'),'S256');assert.equal(url.searchParams.get('state'),a.state);assert.ok(!url.href.includes('Bearer'));
assert.match(googleCookie('fixture'),/HttpOnly; Secure; SameSite=Lax/);assert.match(googleCookie('',0),/Max-Age=0/);
let calls=0;globalThis.fetch=async()=>{calls++;return Response.json({error:'invalid_grant'},{status:400})};await assert.rejects(()=>googleAccessToken({}),/Подключите/);assert.equal(calls,0);await assert.rejects(()=>googleAccessToken({clientId:'id',clientSecret:'secret',refreshToken:'refresh'}),/Подключить повторно/);assert.equal(calls,1);
await assert.rejects(()=>ownerRpc('','respectlogistic_google_settings'),/Войдите/);assert.equal(calls,1);
console.log('PASS: OAuth state, S256 PKCE, exact redirect, secure cookie, no credential in authorization URL, refresh failure and missing owner auth.');
const {POST}=await import('../app/api/google-sync/route.ts');const {GET}=await import('../app/api/google-sync/callback/route.ts');
process.env.NEXT_PUBLIC_SUPABASE_URL='https://fixture.supabase.co';process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY='fixture-public';
const cfg={clientId:'fixture.apps.googleusercontent.com',clientSecret:'fixture-secret',refreshToken:'fixture-refresh',rootFolder:'folder',spreadsheetId:'sheet'};let requests=[];
globalThis.fetch=async(url,init={})=>{url=String(url);requests.push({url,init});
 if(url.endsWith('/respectlogistic_google_settings')){const b=JSON.parse(init.body);if(b.p_action==='credentials')return Response.json(cfg);return Response.json({configured:true,hasClient:true})}
 if(url==='https://oauth2.googleapis.com/token')return Response.json({access_token:'access',refresh_token:'new-refresh'});
 if(url.endsWith('/crm_read_trip_workspace'))return Response.json({trips:[{id:'trip',trip_number:'1',trip_date:'2026-10-28',customer_id:'c',site_id:null,vehicle_id:null,service_name:'Work',volume:2,unit:'т',unit_price:122,status:'sent'}],customers:[{id:'c',name:'=UNTRUSTED()'}],sites:[],vehicles:[],drivers:[]});
 if(url.endsWith('/respectlogistic_read_accounting'))return Response.json({documents:[{id:'advance',kind:'advance',number:'АВ-1',customer_id:'c',site_id:null,document_date:'2026-10-28',modified_at:'v1',status:'draft',total:122,vat:22,paid_amount:0,notes:'',snapshot:{seller:{name:'Seller'},customer:{name:'Customer'},items:[],vat_rate:22}}],links:[]});if(url.endsWith('/respectlogistic_driver_extras'))return Response.json({shift_files:[]});if(url.includes('/rl_crm_trip_files?'))return Response.json([]);if(url.includes('/rl_crm_trips?'))return Response.json([]);
 if(url.startsWith('https://www.googleapis.com/drive/v3/files?'))return Response.json({files:new URL(url).searchParams.get('q')?.includes('mimeType')?[{id:'folder'}]:[]});
 if(url.startsWith('https://www.googleapis.com/upload/drive/v3/files?')){assert.ok(init.body instanceof Blob);return Response.json({id:'uploaded-advance'})}
 if(url==='https://sheets.googleapis.com/v4/spreadsheets/sheet?fields=sheets(properties)')return Response.json({sheets:[]});
 if(url==='https://sheets.googleapis.com/v4/spreadsheets/sheet:batchUpdate'){const body=JSON.parse(init.body);const json=JSON.stringify(body);assert.ok(json.includes('=UNTRUSTED()'));assert.ok(!json.includes('formulaValue'));assert.equal(body.requests.filter(r=>r.addSheet).length,3);return Response.json({})}
 throw Error('Unexpected upstream: '+url);
};
const req=(action,auth='Bearer owner-fixture',extra={})=>new Request('https://respectlogistic.onrender.com/api/google-sync',{method:'POST',headers:{Authorization:auth,'Content-Type':'application/json'},body:JSON.stringify({action,...extra})});
assert.equal((await POST(req('sync',''))).status,401);assert.equal(requests.length,0);
const connected=await POST(req('connect','Bearer owner-fixture',{clientId:cfg.clientId,clientSecret:cfg.clientSecret}));assert.equal(connected.status,200);const body=await connected.json();assert.ok(!JSON.stringify(body).includes('fixture-secret'));const stateUrl=new URL(body.url),cookie=connected.headers.get('set-cookie').split(';')[0];
let cb=await GET(new Request('https://respectlogistic.onrender.com/api/google-sync/callback?state=wrong&code=fixture',{headers:{Cookie:cookie}}));assert.ok(cb.headers.get('location').endsWith('google=invalid_state'));
cb=await GET(new Request('https://respectlogistic.onrender.com/api/google-sync/callback?state='+stateUrl.searchParams.get('state')+'&code=fixture',{headers:{Cookie:cookie}}));assert.ok(cb.headers.get('location').endsWith('google=connected'));assert.match(cb.headers.get('set-cookie'),/Max-Age=0/);assert.ok(requests.some(r=>r.url.endsWith('/respectlogistic_google_settings')&&JSON.parse(r.init.body).p_action==='token'));
const synced=await POST(req('sync'));assert.equal(synced.status,200);assert.equal((await synced.json()).trips,1);assert.ok(requests.some(r=>r.url.startsWith('https://sheets.googleapis.com/')));assert.equal(requests.filter(r=>r.url.includes('/upload/drive/')).length,1,'An advance with no trip must also be archived');
console.log('PASS: authenticated connect/callback, state rejection, token save, owner-scoped mirror, canonical Sheets API and RAW formula-safe writes.');

const internal=await GET(new Request('http://0.0.0.0:10000/api/google-sync/callback?state=bad&code=bad'));assert.equal(new URL(internal.headers.get('location')).origin,'https://respectlogistic.onrender.com','Render internal origin must never enter OAuth redirects');
const internalConnect=await POST(new Request('http://0.0.0.0:10000/api/google-sync',{method:'POST',headers:{Authorization:'Bearer owner-fixture','Content-Type':'application/json'},body:JSON.stringify({action:'connect'})}));assert.equal(new URL((await internalConnect.json()).url).searchParams.get('redirect_uri'),'https://respectlogistic.onrender.com/api/google-sync/callback');
console.log('PASS: Render internal host is excluded from consent, token exchange and callback redirects.');

// A disabled Sheets API must report the precise action while Drive continues independently.
const priorFetch=globalThis.fetch;let driveTouched=false;
globalThis.fetch=async(url,init)=>{if(String(url).startsWith('https://sheets.googleapis.com/'))return Response.json({error:{message:'API disabled',details:[{reason:'SERVICE_DISABLED'}]}},{status:403});if(String(url).startsWith('https://www.googleapis.com/'))driveTouched=true;return priorFetch(url,init)};
const disabled=await POST(req('sync'));assert.equal(disabled.status,400);assert.match((await disabled.json()).message,/Google Sheets API/);assert.equal(driveTouched,true);assert.match((await POST(req('sync'))).status.toString(),/400/);globalThis.fetch=priorFetch;
console.log('PASS: Sheets API failure is actionable without blocking valid Drive exports.');
// A retained accounting history entry for a deleted trip must never reach uploads or the mirror.
let mirrored='';globalThis.fetch=async(url,init={})=>{
 if(String(url).endsWith('/respectlogistic_read_accounting')){const r=await priorFetch(url,init),a=await r.json();a.documents.push({...a.documents[0],id:'orphan26',kind:'invoice',number:'EXCLUDED-26',snapshot:{...a.documents[0].snapshot,items:[{trip_id:'removed-trip'}]}});a.links.push({document_id:'orphan26',trip_id:'removed-trip',active:true});return Response.json(a)}
 if(String(url).endsWith('/sheet:batchUpdate'))mirrored=init.body;
 return priorFetch(url,init);
};
const orphanSync=await POST(req('sync'));assert.equal(orphanSync.status,200);assert.equal((await orphanSync.json()).documents,1);assert.ok(!mirrored.includes('EXCLUDED-26'));globalThis.fetch=priorFetch;
console.log('PASS: orphan accounting history is excluded from real sync payloads.');
