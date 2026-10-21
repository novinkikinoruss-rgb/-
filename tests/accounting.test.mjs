import test from 'node:test';
import assert from 'node:assert/strict';
import {completedTrips,invoiceTotal,reconciliation,payrollSummary,escapeHtml,csvCell,validPeriod} from '../lib/accounting.ts';
const trip={id:'t',customer_id:'a',order_id:null,site_id:'s',status:'delivered',trip_number:'Р-1',trip_date:'2026-10-15',service_name:'Щебень',volume:2.5,unit_price:1200,driver_id:'d'};
const f={customerId:'a',siteId:'s',from:'2026-10-01',to:'2026-10-31'};
test('Счёт содержит только выполненные рейсы заказчика, объекта и периода',()=>{
 const trips=[trip,{...trip,id:'other-customer',customer_id:'b'},{...trip,id:'other-site',site_id:'x'},{...trip,id:'unfinished',status:'sent'},{...trip,id:'last-month',trip_date:'2026-09-30'},{...trip,id:'no-date',trip_date:null}];
 assert.deepEqual(completedTrips(trips,[],f).map(t=>t.id),['t']);
});
test('Старый рейс получает заказчика и объект из заявки',()=>{
 const old={...trip,customer_id:null,site_id:null,order_id:'o'};
 assert.equal(completedTrips([old],[{id:'o',customer_id:'a',site_id:'s'}],f).length,1);
});
test('Обратный диапазон дат не возвращает услуги',()=>{
 assert.equal(validPeriod('2026-11-01','2026-10-01'),false);
 assert.equal(completedTrips([trip],[],{...f,from:'2026-11-01'}).length,0);
});
test('Объём × цена и округление каждой строки счёта',()=>{
 assert.equal(invoiceTotal([trip]),3000);
 assert.equal(invoiceTotal([{volume:1,unit_price:0.105},{volume:1,unit_price:0.105}]),0.22);
});
const invoices=[{id:'old',invoice_number:'1',invoice_date:'2026-09-10',amount:1000},{id:'new',invoice_number:'2',invoice_date:'2026-10-15',amount:500}];
const payments=[{id:'pre',invoice_id:'old',payment_date:'2026-09-20',amount:200},{id:'current',invoice_id:'old',payment_date:'2026-10-10',amount:300},{id:'future',invoice_id:'new',payment_date:'2026-11-01',amount:500},{id:'unrelated',invoice_id:'another-customer',payment_date:'2026-10-15',amount:9000}];
test('Акт сверки: начальное сальдо, оплата старого счёта, обороты и конечное сальдо',()=>{
 const act=reconciliation(invoices,payments,'2026-10-01','2026-10-31');
 assert.equal(act.opening,800);assert.equal(act.debit,500);assert.equal(act.credit,300);assert.equal(act.closing,1000);assert.equal(act.rows.length,2);
 assert.equal(act.rows[0].label,'Оплата счёта № 1');
});
test('Акт сверки включает граничные даты и пустой период',()=>{
 assert.equal(reconciliation(invoices,payments,'2026-10-10','2026-10-15').rows.length,2);
 const empty=reconciliation(invoices,payments,'2026-10-20','2026-10-21');assert.equal(empty.rows.length,0);assert.equal(empty.opening,1000);assert.equal(empty.closing,1000);
});
const accrual={id:'a',active:true,base:7000,bonus:700,tax:2310};
test('Зарплата: премия, частичная выплата и отдельная оплата налогов',()=>{
 const result=payrollSummary([accrual],[{accrual_id:'a',kind:'salary',amount:3000},{accrual_id:'a',kind:'tax',amount:1000},{accrual_id:'other',kind:'salary',amount:99999}]);
 assert.deepEqual(result,{base:7000,bonus:700,tax:2310,deducted:0,paid:3000,taxPaid:1000,accrued:7700,due:4700,taxDue:1310});
});
test('Отменённые начисления и их оплаты не попадают в итоги',()=>{
 assert.equal(payrollSummary([{...accrual,active:false}],[{accrual_id:'a',kind:'salary',amount:3000}]).accrued,0);
 assert.equal(payrollSummary([{...accrual,active:false}],[{accrual_id:'a',kind:'salary',amount:3000}]).paid,0);
});
test('Печать и CSV экранируют введённый текст',()=>{
 assert.equal(escapeHtml('<script>"&'), '&lt;script&gt;&quot;&amp;');
 assert.equal(csvCell('=1+2'), '"\'=1+2"');assert.equal(csvCell(-100),'"-100"');
});

test('Удержание штрафа уменьшает остаток один раз и не меняет налог',()=>{
 const payments=[{accrual_id:'a',kind:'salary',amount:3000}];
 const deductions=[{accrual_id:'a',fine_id:'fine',amount:500}];
 const summary=payrollSummary([accrual],payments,deductions);
 assert.equal(summary.deducted,500);assert.equal(summary.due,4200);assert.equal(summary.tax,2310);
 assert.equal(payrollSummary([{...accrual,active:false}],payments,deductions).deducted,0);
});
