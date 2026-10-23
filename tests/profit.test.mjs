import test from 'node:test';
import assert from 'node:assert/strict';
import {profitReport,profitCosts,allocatePaid,vatFromGross,tripEarnings} from '../lib/profit.ts';
const filter={from:'2026-10-01',to:'2026-10-31',customer:'',site:'',service:''};
const trip=(id,changes={})=>({id,trip_number:id,trip_date:'2026-10-10',status:'delivered',customer_id:'customer',site_id:'site',service_name:'Перевозка',vehicle_id:'vehicle',driver_id:'driver',carrier_id:null,volume:10,unit:'м³',unit_price:122,...changes});
const expense=(id,changes={})=>({id,expense_date:'2026-10-10',category:'fuel',amount:122,paid_amount:122,customer_id:'customer',site_id:'site',service_name:'Перевозка',trip_id:'own',vehicle_id:'vehicle',invoice_id:null,notes:'',modified_at:'v',vat_rate:22,input_vat_confirmed:true,...changes});
function fixture(){return {settings:{tax_regime:'osno',vat_rate:22,prices_include_vat:true},trips:[trip('own'),trip('contractor',{carrier_id:'carrier',service_name:'Вывоз',volume:5,unit_price:244,unit:'т'}),trip('planned',{status:'assigned',volume:1000}),trip('cancelled',{status:'cancelled'})],customers:[],sites:[],vehicles:[],carriers:[],expenses:[expense('fuel'),expense('allocation',{category:'contractor',amount:366,paid_amount:0,invoice_id:'invoice',trip_id:'contractor',service_name:'Вывоз',vat_rate:null,input_vat_confirmed:false})],invoices:[{id:'invoice',counterparty_id:'carrier',invoice_number:'1',invoice_date:'2026-10-10',amount:610,paid_amount:305}],invoice_vat:[{invoice_id:'invoice',vat_rate:22,input_vat_confirmed:true}],accruals:[{id:'accrual',trip_id:'own',accrual_date:'2026-10-10',base:200,bonus:20,tax:28.6,active:true}],payments:[{accrual_id:'accrual',kind:'salary',amount:100},{accrual_id:'accrual',kind:'tax',amount:10}],deductions:[{accrual_id:'accrual',amount:20}]}}
test('VAT 22% is extracted from included prices and added only when prices exclude VAT',()=>{
 assert.equal(vatFromGross(122000,22),22000);
 assert.deepEqual(tripEarnings(trip('1'),{vat_rate:22,prices_include_vat:true}),{net:100000,gross:122000,vat:22000});
 assert.deepEqual(tripEarnings(trip('1',{unit_price:100}),{vat_rate:22,prices_include_vat:false}),{net:100000,gross:122000,vat:22000});
});
test('profit is accrued net revenue minus net expenses; unpaid contractor balances are included exactly once',()=>{
 const r=profitReport(fixture(),filter);assert.equal(r.completed.length,2);assert.equal(r.revenue,200000);assert.equal(r.revenueGross,244000);assert.equal(r.expense,84860);assert.equal(r.profit,115140);assert.equal(r.margin,57.57);assert.equal(r.outputVat,44000);assert.equal(r.inputVat,13200);assert.equal(r.vatPayable,30800);assert.equal(r.contractorCost,61000);assert.equal(r.contractorPaid,30500);assert.equal(r.contractorDue,30500);
});
test('customer/object/service/date filters apply to costs and completed work; unallocated costs are visible but never silently spread',()=>{
 const d=fixture(),r=profitReport(d,{...filter,customer:'customer',site:'site'});assert.equal(r.expense,64860);assert.equal(r.unallocatedTotal,20000);assert.equal(r.profit,135140);
 const service=profitReport(d,{...filter,service:'Перевозка'});assert.equal(service.revenue,100000);assert.equal(service.expense,34860);
 assert.equal(profitReport(d,{...filter,from:'2026-10-11'}).revenue,0);assert.equal(profitReport(d,{...filter,customer:'other'}).revenue,0);
});
test('salary, bonus and employer tax stay separate; a fine reduces payout debt, never silently increases profit',()=>{
 const d=fixture(),rows=profitCosts(d),salary=rows.find(c=>c.category==='salary'),tax=rows.find(c=>c.category==='payroll_tax');assert.equal(salary.amount,22000);assert.equal(salary.paid,10000);assert.equal(salary.held,2000);assert.equal(salary.amount-salary.paid-salary.held,10000);assert.equal(tax.amount,2860);assert.equal(tax.vat,0);assert.equal(salary.vat,0);
});
test('invoice allocation and VAT/payment remainders conserve every kopeck',()=>{
 assert.deepEqual(allocatePaid(1,[33,33,34]),[0,0,1]);assert.equal(allocatePaid(100,[41,79,100]).reduce((a,b)=>a+b),100);
 const rows=profitCosts(fixture()).filter(r=>r.invoice==='invoice');assert.equal(rows.reduce((a,b)=>a+b.amount,0),61000);assert.equal(rows.reduce((a,b)=>a+b.vat,0),11000);assert.equal(rows.reduce((a,b)=>a+b.paid,0),30500);
 assert.throws(()=>allocatePaid(101,[100]));
});
test('unconfirmed input VAT is not deducted; unknown output VAT settings are explicitly incomplete',()=>{
 const d=fixture();d.expenses[0].input_vat_confirmed=false;const r=profitReport(d,filter);assert.equal(r.inputVat,11000);assert.equal(r.pendingInputVat,2200);assert.equal(r.expense,87060);
 d.settings.prices_include_vat=null;const pending=profitReport(d,filter);assert.equal(pending.vatConfigured,false);assert.equal(pending.outputVat,null);assert.equal(pending.vatPayable,null);assert.ok(pending.warnings>0);
});
test('zero revenue has no fabricated margin; costs still create a loss; VAT excess is not treated as a refund',()=>{
 const d=fixture();d.trips=[];d.accruals=[];d.invoices=[];d.expenses=[expense('fuel')];const r=profitReport(d,filter);assert.equal(r.profit,-10000);assert.equal(r.margin,null);assert.equal(r.vatPayable,0);assert.equal(r.vatExcess,2200);
});
test('service volumes with different units stay in separate rows',()=>{
 const r=profitReport(fixture(),filter);assert.equal(r.services.length,2);assert.deepEqual(r.services.map(s=>[s.unit,s.volume]),[['м³',10],['т',5]]);
});
