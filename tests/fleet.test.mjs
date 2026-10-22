import test from 'node:test';
import assert from 'node:assert/strict';
import {fleetCalculation,accrualBalance,maintenanceState} from '../lib/fleet.ts';
test('one route leg; company tax never reduces driver salary',()=>{
 const c=fleetCalculation(70,120,10,13,1000);
 assert.deepEqual(c,{base:8400,bonus:840,gross:9240,tax:1201.2,toDriver:8240,companyCost:10441.2});
 assert.equal(fleetCalculation(80,120,10,13).base,9600);
});
test('money rounding and invalid inputs',()=>{
 assert.equal(fleetCalculation(70,0.333,10,13).base,23.31);
 for(const args of [[-1,120,10,13],[70,NaN,10,13],[70,120,Infinity,13]])assert.throws(()=>fleetCalculation(...args));
});
test('saved accrual, salary, tax payments and fine deductions are separate',()=>{
 const a={id:'a',trip_id:'t',driver_id:'d',site_id:'s',accrual_date:'2026-10-23',distance_km:120,rate:70,bonus_pct:10,tax_pct:13,base:8400,bonus:840,tax:1201.2,active:true};
 const p=[{id:'p',accrual_id:'a',kind:'salary',amount:4000,payment_date:'2026-10-23'},{id:'q',accrual_id:'a',kind:'tax',amount:500,payment_date:'2026-10-23'}];
 const d=[{id:'f',accrual_id:'a',fine_id:'fine',amount:1000,deduction_date:'2026-10-23'}];
 const b=accrualBalance(a,p,d);
 assert.equal(b.gross,9240);assert.equal(b.held,1000);assert.equal(b.due,4240);assert.equal(b.taxDue,701.2);assert.equal(b.companyCost,10441.2);
 assert.equal(accrualBalance(a,[...p,{id:'other',accrual_id:'other',kind:'salary',amount:999,payment_date:'2026-10-23'}],d).due,4240);
});
test('maintenance thresholds including exact boundary',()=>{
 assert.equal(maintenanceState(184500,187000,1000).status,'ok');
 assert.equal(maintenanceState(186000,187000,1000).status,'soon');
 assert.equal(maintenanceState(187000,187000,1000).status,'overdue');
 assert.equal(maintenanceState(187001,187000,1000).remaining,-1);
 assert.equal(maintenanceState(184500,null,1000).status,'unset');
});
