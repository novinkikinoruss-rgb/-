import assert from 'node:assert/strict';
import test from 'node:test';
import {exportableDocuments} from '../lib/drive-documents.ts';
const doc=(id,changes={})=>({id,kind:'invoice',status:'draft',deleted_at:null,snapshot:{items:[]},...changes});
const trips=[{id:'live',status:'delivered'},{id:'deleted',status:'delivered',deleted_at:'2026-10-28'},{id:'cancelled',status:'cancelled'}];
const link=(document_id,trip_id,active=true)=>({document_id,trip_id,active});
test('deleted, archived, cancelled, orphan and partially stale documents never enter the mirror',()=>{
 const docs=[doc('ok'),doc('orphan26'),doc('missing'),doc('mixed'),doc('cancelTrip'),doc('cancelDoc',{status:'cancelled'}),doc('archived',{deleted_at:'2026-10-28'}),doc('inactive'),doc('advance',{kind:'advance'}),doc('orphanUpd',{kind:'upd',invoice_id:'orphan26'}),doc('okUpd',{kind:'upd',invoice_id:'ok'})];
 const links=[link('ok','live'),link('orphan26','deleted'),link('missing','not-visible'),link('mixed','live'),link('mixed','deleted'),link('cancelTrip','cancelled'),link('cancelDoc','live'),link('archived','live'),link('inactive','live',false),link('orphanUpd','live'),link('okUpd','live')];
 assert.deepEqual(exportableDocuments(docs,links,trips).map(d=>d.id),['ok','advance','okUpd']);
});
test('snapshot of deleted trip is not exported even if a remaining link points to a live trip',()=>{
 assert.equal(exportableDocuments([doc('stale',{snapshot:{items:[{trip_id:'deleted'}]}})],[link('stale','live')],trips).length,0);
});
test('historical inactive links do not contaminate current documents or alter snapshots',()=>{
 const d=doc('ok',{snapshot:{items:[{trip_id:'live',gross:122}]}}),before=structuredClone(d);
 assert.deepEqual(exportableDocuments([d],[link('ok','live'),link('ok','deleted',false)],trips),[d]);assert.deepEqual(d,before);
});

test('a standalone advance tied to a deleted source is also excluded',()=>{
 assert.deepEqual(exportableDocuments([doc('a',{kind:'advance'})],[link('a','deleted')],trips),[]);
});
