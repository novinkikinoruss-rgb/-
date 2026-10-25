import {test} from 'node:test';import assert from 'node:assert/strict';import {processDriverPhoto} from '../lib/driver-photo-client.ts';
test('photo deadline terminates a stuck worker and makes a retry possible; abort also releases it',async()=>{
 const previous=globalThis.Worker;const workers=[];globalThis.Worker=class{constructor(){this.terminated=false;workers.push(this)}postMessage(){}terminate(){this.terminated=true}};
 try{const file=new File(['HEIC DATA'],'document.heic',{type:'application/octet-stream'});await assert.rejects(processDriverPhoto(file,0,true,new AbortController().signal,()=>{},20),/слишком много времени/);assert.equal(workers[0].terminated,true);
 const controller=new AbortController();const processing=processDriverPhoto(file,0,true,controller.signal,()=>{},1000);controller.abort();await assert.rejects(processing,{name:'AbortError'});assert.equal(workers[1].terminated,true);
 const success=processDriverPhoto(file,0,true,new AbortController().signal,()=>{},1000);workers[2].onmessage({data:{result:'jpeg'}});assert.equal(await success,'jpeg');assert.equal(workers[2].terminated,true);
 }finally{globalThis.Worker=previous}
});

import {driverErrorMessage} from '../lib/driver-errors.ts';
test('timeouts from reading the response body also have an actionable Russian message',()=>{assert.match(driverErrorMessage(new DOMException('signal timed out','TimeoutError')),/повторите действие/);assert.match(driverErrorMessage(Error('signal timed out')),/данные остаются/);assert.equal(driverErrorMessage(Error('Примите заявку')),'Примите заявку')});
