import assert from 'node:assert/strict';
import test from 'node:test';
import {customerOverview} from '../lib/overview-report.ts';
const filter={from:'2026-10-01',to:'2026-10-31',customer:'',site:'',service:''};
const trip=(id,site='a',unit='т')=>({id,trip_number:id,status:'delivered',trip_date:'2026-10-10',customer_id:'customer',site_id:site,service_name:'Перевозка',vehicle_id:null,driver_id:null,carrier_id:null,volume:1,unit,unit_price:122});
const data={settings:{vat_rate:22,prices_include_vat:true},trips:[trip('one'),trip('two','b','м³')],customers:[{id:'customer',name:'Заказчик'}],sites:[],vehicles:[],carriers:[],expenses:[],invoices:[],accruals:[],payments:[],deductions:[]};
const doc=(id,kind,ids=['one','two'])=>({id,kind,customer_id:'customer',status:'issued',total:244,paid_amount:61,snapshot:{items:ids.map(id=>({trip_id:id,gross:122}))},trip_ids:ids});
test('closed service sums deduplicate UPD and registry; partial payments and advances reduce invoice debt once',()=>{
 const r=customerOverview(data,[doc('upd','upd'),doc('reg','registry'),doc('invoice','invoice')],[{invoice_id:'invoice',amount:61}],filter)[0];
 assert.equal(r.gross,24400);assert.equal(r.closedGross,24400);assert.equal(r.closingCount,2);assert.equal(r.billed,24400);assert.equal(r.paid,6100);assert.equal(r.credited,6100);assert.equal(r.due,12200);assert.equal(r.unbilled,0);assert.equal(r.serviceCount,2);assert.deepEqual(r.services.map(s=>s.unit),['т','м³']);
});
test('object/service/period filters allocate shared invoice amounts without pulling in other services',()=>{
 const docs=[doc('invoice','invoice')],credits=[{invoice_id:'invoice',amount:61}];const r=customerOverview(data,docs,credits,{...filter,site:'a',service:'Перевозка'})[0];assert.equal(r.trips,1);assert.equal(r.gross,12200);assert.equal(r.billed,12200);assert.equal(r.paid,3050);assert.equal(r.credited,3050);assert.equal(r.due,6100);
 assert.deepEqual(customerOverview(data,docs,credits,{...filter,from:'2026-11-01',to:'2026-11-30'}),[]);assert.deepEqual(customerOverview(data,docs,credits,{...filter,service:'Другая услуга'}),[]);
});
test('draft/cancelled invoices and advances are not service revenue or billed services',()=>{
 const docs=[{...doc('draft','invoice'),status:'draft'},{...doc('cancelled','upd'),status:'cancelled'},doc('advance','advance')];const r=customerOverview(data,docs,[],filter)[0];assert.equal(r.gross,24400);assert.equal(r.billed,0);assert.equal(r.closedGross,0);assert.equal(r.paid,0);assert.equal(r.unbilled,24400);
});
test('rounding preserves every kopeck across objects and overpayments fail explicitly',()=>{
 const invoice=doc('invoice','invoice');invoice.paid_amount=0.01;const a=customerOverview(data,[invoice],[],{...filter,site:'a'})[0],b=customerOverview(data,[invoice],[],{...filter,site:'b'})[0];assert.equal(a.paid+b.paid,1);assert.throws(()=>customerOverview(data,[{...invoice,paid_amount:300}],[],filter));
});
