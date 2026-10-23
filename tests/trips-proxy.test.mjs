import assert from 'node:assert/strict';
import {POST} from '../app/supabase/[...path]/route.ts';
process.env.NEXT_PUBLIC_SUPABASE_URL='https://example.supabase.co';
process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY='test-key';
let calls=[];
globalThis.fetch=async(url,options)=>{calls.push({url:String(url),options});return new Response('[]',{status:200,headers:{'content-type':'application/json'}})};
for(const rpc of ['crm_read_trip_workspace','crm_save_trip','crm_delete_trips']){
 const response=await POST(new Request('https://crm.example/supabase/rest/v1/rpc/'+rpc,{method:'POST',headers:{authorization:'Bearer test-user','content-type':'application/json'},body:'{"test":true}'}),{params:Promise.resolve({path:['rest','v1','rpc',rpc]})});
 assert.equal(response.status,200);assert.equal(calls.at(-1).options.headers.get('authorization'),'Bearer test-user');assert.equal(calls.at(-1).url,'https://example.supabase.co/rest/v1/rpc/'+rpc);
}
const count=calls.length;
assert.equal((await POST(new Request('https://crm.example/',{method:'POST',body:'{}'}),{params:Promise.resolve({path:['rest','v1','rpc','unknown_trip_operation']})})).status,404);
assert.equal(calls.length,count);
console.log('PASS: trip read/save/delete RPCs forward user JWT; unknown RPC blocked.');

