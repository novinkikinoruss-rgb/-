import assert from 'node:assert/strict';
import test from 'node:test';
import {prepareTripFile} from '../lib/trip-file-client.ts';
test('picker bytes are copied before the provider is released and keep the original filename',async()=>{
 const bytes=new TextEncoder().encode('original TTN bytes');
 let available=true;
 const file={size:bytes.length,name:'Накладная.pdf',arrayBuffer:async()=>{assert.ok(available);return bytes.buffer}};
 const ready=await prepareTripFile(file);available=false;bytes.fill(0);
 assert.equal(ready.name,'Накладная.pdf');
 assert.equal(await ready.blob.text(),'original TTN bytes');
 const form=new FormData();form.set('file',ready.blob,ready.name);
 assert.equal(form.get('file').name,'Накладная.pdf');
 assert.equal(await form.get('file').text(),'original TTN bytes');
});
test('unreadable provider and truncated files fail before any upload',async()=>{
 await assert.rejects(prepareTripFile({size:10,name:'TTN.pdf',arrayBuffer:async()=>{throw Error('revoked')}}),/Не удалось прочитать/);
 await assert.rejects(prepareTripFile({size:10,name:'TTN.pdf',arrayBuffer:async()=>new ArrayBuffer(5)}),/Файл изменился/);
});
test('empty and oversized files are rejected without reading bytes',async()=>{
 for(const size of [0,10485761])await assert.rejects(prepareTripFile({size,name:'TTN',arrayBuffer:async()=>{throw Error('must not read')}}),/до 10 МБ/);
});
