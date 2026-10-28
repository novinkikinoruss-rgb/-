import test from 'node:test';import assert from 'node:assert/strict';
import {filterRequests,blankRequestFilter} from '../lib/dispatch.ts';
import {defaultTripOrder,restoreTripColumns,moveTripColumn,clampColumnWidth} from '../lib/trip-columns.ts';
const request=(id,changes={})=>({id,number:1,customer_id:'c',site_id:'s',date_from:'2026-10-25',date_to:'2026-10-30',payload:{service_name:'Перевозка',site_name:'Объект'},cancelled_at:null,...changes});
const shift=(id,changes={})=>({id,request_id:'one',vehicle_id:'a',driver_id:'driver-a',driver_name:'Иванов',shift_date:'2026-10-28',status:'accepted',...changes});
test('request filters compose across customer, service, object, period and the SAME driver/vehicle assignment',()=>{
 const rows=[request('one'),request('unassigned'),request('other',{customer_id:'other'}),request('cancelled',{cancelled_at:'now'})],shifts=[shift('one'),shift('two',{vehicle_id:'b',driver_id:'driver-b'})];
 const f={...blankRequestFilter,customer:'c',service:'Перевозка',site:'s',vehicle:'a',driver:'driver-a',from:'2026-10-28',to:'2026-10-28'};
 assert.deepEqual(filterRequests(rows,shifts,f).map(r=>r.id),['one']);assert.equal(filterRequests(rows,shifts,{...f,driver:'driver-b'}).length,0);assert.equal(filterRequests(rows,shifts,{...f,from:'2026-11-01',to:''}).length,0);assert.equal(filterRequests(rows,shifts,blankRequestFilter).length,3);
});
test('cancelled assignments are opt-in; unassigned requests remain visible without vehicle/driver filters',()=>{
 const rows=[request('one')],shifts=[shift('one',{status:'cancelled'})];assert.equal(filterRequests(rows,shifts,{...blankRequestFilter,vehicle:'a'}).length,0);assert.equal(filterRequests(rows,shifts,{...blankRequestFilter,vehicle:'a',cancelled:true}).length,1);assert.equal(filterRequests(rows,[],blankRequestFilter).length,1);
});
test('external driver names and legacy request-number search are usable',()=>{
 const rows=[request('one')],shifts=[shift('one',{driver_id:null,driver_name:'Водитель перевозчика'})];assert.equal(filterRequests(rows,shifts,{...blankRequestFilter,driver:'name:Водитель перевозчика'}).length,1);assert.equal(filterRequests(rows,shifts,{...blankRequestFilter,query:'З1'}).length,1);
});
test('column settings reject corrupt ids and invalid widths while preserving every real column exactly once',()=>{
 const layout=restoreTripColumns({order:['driver','driver','bogus'],widths:{driver:-100,date:100000,total:NaN}});assert.deepEqual(layout.order.slice(0,2),['number','driver']);assert.equal(new Set(layout.order).size,defaultTripOrder.length);assert.equal(layout.widths.driver,75);assert.equal(layout.widths.date,650);assert.equal(layout.widths.total,100);assert.deepEqual(restoreTripColumns(null).order,defaultTripOrder);assert.equal(clampColumnWidth('date',1),90);
});
test('column reorder moves one real field and keeps the pinned trip number in place',()=>{
 const order=moveTripColumn(defaultTripOrder,'date','driver');assert.equal(order.indexOf('date'),defaultTripOrder.indexOf('driver'));assert.equal(order[0],'number');assert.deepEqual(moveTripColumn(order,'bogus','date'),order);assert.deepEqual(moveTripColumn(order,'number','date'),order);
});
