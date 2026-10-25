import assert from 'node:assert/strict';
import {GET,POST,PATCH} from '../app/supabase/[...path]/route.ts';
process.env.NEXT_PUBLIC_SUPABASE_URL='https://example.supabase.co';
process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY='test-key';
let calls=[];
globalThis.fetch=async(url,options)=>{calls.push({url:String(url),options});return new Response('[]',{status:200,headers:{'content-type':'application/json'}})};
const tables=['crm_carriers','crm_drivers','crm_vehicles','crm_trips','crm_sites','crm_documents','crm_driver_fines','crm_payroll_accruals','crm_payroll_payments','crm_payroll_deductions','crm_fleet_maintenance','crm_trip_files','crm_drive_exports'];
const writable=['crm_carriers','crm_drivers','crm_vehicles','crm_driver_fines'];
for(const table of tables)for(const [method,handler] of [['GET',GET],['POST',POST],['PATCH',PATCH]]){
 const count=calls.length;
 const result=await handler(new Request('https://crm.example/supabase/rest/v1/'+table+'?select=id',{method,headers:{authorization:'Bearer test-user',prefer:'return=representation','content-type':'application/json'},...(method==='GET'?{}:{body:'{}'})}),{params:Promise.resolve({path:['rest','v1',table]})});
 if(method!=='GET'&&!writable.includes(table)){assert.equal(result.status,404);assert.equal(calls.length,count);continue}
 assert.equal(result.status,200);assert.equal(calls.at(-1).options.headers.get('authorization'),'Bearer test-user');assert.equal(calls.at(-1).url,'https://example.supabase.co/rest/v1/rl_'+table+'?select=id');
}
for(const rpc of ['crm_prepare_payroll','crm_pay_driver_accruals','crm_apply_driver_fines','crm_complete_fleet_maintenance']){
 const response=await POST(new Request('https://crm.example/',{method:'POST',headers:{authorization:'Bearer test-user','content-type':'application/json'},body:'{}'}),{params:Promise.resolve({path:['rest','v1','rpc',rpc]})});
 assert.equal(response.status,200);assert.equal(calls.at(-1).url,'https://example.supabase.co/rest/v1/rpc/rl_'+rpc);
}
const mobile=await POST(new Request('https://crm.example/',{method:'POST',headers:{authorization:'Bearer test-user','content-type':'application/json'},body:'{}'}),{params:Promise.resolve({path:['rest','v1','rpc','respectlogistic_driver_mobile']})});
assert.equal(mobile.status,200);assert.equal(calls.at(-1).url,'https://example.supabase.co/rest/v1/rpc/respectlogistic_driver_mobile');
const count=calls.length;
for(const path of [['rest','v1','secrets'],['rest','v1','rpc','respectlogistic_finish_drive_export'],['rest','v1','rl_crm_drivers'],['rest','v1','crm_drivers','extra'],['storage','v1','object','crm-documents','file.pdf'],['storage','v1','object','respectlogistic-trip-documents','..','file.pdf']])assert.equal((await GET(new Request('https://crm.example/'),{params:Promise.resolve({path})})).status,404);
assert.equal(calls.length,count);
const path=['storage','v1','object','respectlogistic-trip-documents','owner','trip','file.pdf'];
assert.equal((await POST(new Request('https://crm.example/',{method:'POST',headers:{authorization:'Bearer test-user','content-type':'application/pdf'},body:'PDF'}),{params:Promise.resolve({path})})).status,200);
assert.equal(calls.at(-1).url,'https://example.supabase.co/'+path.join('/'));
console.log('PASS: app-scoped views; protected financial writes; private document bucket; service export RPCs blocked.');
