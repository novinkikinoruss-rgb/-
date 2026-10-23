export const expenseCategories:Record<string,string>={contractor:'Контрагенты',salary:'Зарплата и премии',payroll_tax:'Налоги на зарплату',fuel:'Топливо',maintenance:'ТО и ремонт',leasing:'Лизинг / аренда',insurance:'Страхование',tolls:'Платные дороги',tax:'Налоги компании',other:'Прочие расходы'};
export type ProfitFilter={from:string;to:string;customer:string;site:string;service:string};
export type ProfitTrip={id:string;trip_number:string;trip_date:string|null;status:string;customer_id:string|null;site_id:string|null;service_name:string|null;vehicle_id:string|null;driver_id:string|null;carrier_id:string|null;volume:number;unit:string;unit_price:number;distance_km_snapshot?:number|null};
export type ProfitExpense={id:string;expense_date:string;category:string;amount:number;paid_amount:number;customer_id:string|null;site_id:string|null;service_name:string|null;trip_id:string|null;vehicle_id:string|null;invoice_id:string|null;notes:string;modified_at:string;vat_rate?:number|null;input_vat_confirmed?:boolean};
export type FinancePlan={id:string;customer_id:string;site_id:string|null;service_name:string|null;date_from:string;date_to:string;revenue:number;cost:number;notes:string;modified_at:string};
export type FinanceEvent={id:string;title:string;kind:'incoming'|'outgoing'|'tax';due_date:string;amount:number;paid_amount:number;customer_id:string|null;site_id:string|null;service_name:string|null;notes:string;modified_at:string};
export type FinanceDueDate={source_kind:string;source_id:string;due_date:string};
export type ProfitInvoice={id:string;counterparty_id:string;invoice_number:string;invoice_date:string;amount:number;paid_amount:number;due_date?:string|null};
export type ProfitData={accounting_invoices?:{id:string;kind:string;number:string;customer_id:string;site_id:string|null;service_name:string|null;due_date:string|null;total:number;paid_amount:number;credited:number;snapshot:{items:{gross:number;site_id?:string;service:string}[]}}[];plans?:FinancePlan[];events?:FinanceEvent[];due_dates?:FinanceDueDate[];settings?:{tax_regime:string;vat_rate:number;prices_include_vat:boolean|null};invoice_vat?:{invoice_id:string;vat_rate:number|null;input_vat_confirmed:boolean;modified_at:string}[];trips:ProfitTrip[];customers:{id:string;name:string}[];sites:{id:string;customer_id:string;name:string;service_name:string|null;route_km?:number|string|null}[];vehicles:{id:string;plate:string}[];carriers:{id:string;name:string}[];expenses:ProfitExpense[];invoices:ProfitInvoice[];accruals:{id:string;trip_id:string;accrual_date:string;base:number;bonus:number;tax:number;active:boolean;distance_km?:number}[];payments:{accrual_id:string;kind:string;amount:number}[];deductions:{accrual_id:string;amount:number}[]};
export type CostRow={id:string;expenseId:string|null;date:string;category:string;amount:number;vat:number;pendingVat:number;paid:number;held:number;customer:string;site:string;service:string;trip:string;vehicle:string;invoice:string;notes:string;unallocated:boolean};
export const cents=(v:number|string)=>{const n=Number(v),result=Math.round((n+Number.EPSILON)*100);if(!Number.isFinite(n)||!Number.isSafeInteger(result))throw Error('Некорректная или слишком большая сумма');return result};
export const rubles=(v:number)=>v/100;
const sum=(rows:number[])=>rows.reduce((a,b)=>a+b,0);
const inDates=(date:string,f:ProfitFilter)=>(!f.from||date>=f.from)&&(!f.to||date<=f.to);
const inContext=(customer:string|null,site:string|null,service:string|null,f:ProfitFilter)=>(!f.customer||customer===f.customer)&&(!f.site||site===f.site)&&(!f.service||(service||'').trim()===f.service);
// Largest remainders keep allocated payments equal to the invoice payment down to one kopeck.
export function allocatePaid(total:number,weights:number[]){
 const weight=sum(weights);if(!Number.isSafeInteger(total)||!Number.isSafeInteger(weight)||total<0||weights.some(v=>!Number.isSafeInteger(v)||v<0)||total>weight)throw Error('Оплата превышает сумму расходов или сумма некорректна');if(!weight)return weights.map(()=>0);
 const denominator=BigInt(weight),scaled=weights.map(v=>BigInt(total)*BigInt(v)),result=scaled.map(v=>Number(v/denominator));let left=total-sum(result);
 for(const i of scaled.map((v,i)=>({i,remainder:v%denominator})).sort((a,b)=>a.remainder>b.remainder?-1:a.remainder<b.remainder?1:a.i-b.i)){if(left--<=0)break;result[i.i]++}return result;
}
export function vatFromGross(gross:number,rate:number){if(!Number.isFinite(rate)||rate<0||rate>100)throw Error('Некорректная ставка НДС');return Math.round(gross*rate/(100+rate))}
export function tripEarnings(trip:ProfitTrip,settings:ProfitData['settings']){
 const amount=cents(Number(trip.volume)*Number(trip.unit_price)),rate=Number(settings?.vat_rate??22),configured=settings?.prices_include_vat!==null&&settings?.prices_include_vat!==undefined;
 if(!configured)return {net:amount,gross:amount,vat:0};
 if(settings!.prices_include_vat){const vat=vatFromGross(amount,rate);return {net:amount-vat,gross:amount,vat}}
 const vat=Math.round(amount*rate/100);return {net:amount,gross:amount+vat,vat};
}
export function profitCosts(data:ProfitData){
 const rows:CostRow[]=data.expenses.filter(e=>!e.invoice_id).map(e=>({id:e.id,expenseId:e.id,date:e.expense_date,category:e.category,amount:cents(e.amount),vat:e.input_vat_confirmed?vatFromGross(cents(e.amount),Number(e.vat_rate||0)):0,pendingVat:!e.input_vat_confirmed&&e.vat_rate!==null&&e.vat_rate!==undefined?vatFromGross(cents(e.amount),Number(e.vat_rate)):0,paid:cents(e.paid_amount),held:0,customer:e.customer_id||'',site:e.site_id||'',service:e.service_name||'',trip:e.trip_id||'',vehicle:e.vehicle_id||'',invoice:'',notes:e.notes,unallocated:!e.customer_id&&!e.site_id&&!e.trip_id}));
 for(const invoice of data.invoices){
  const allocations=data.expenses.filter(e=>e.invoice_id===invoice.id).sort((a,b)=>a.id.localeCompare(b.id));const total=cents(invoice.amount),remaining=total-sum(allocations.map(e=>cents(e.amount)));
  if(remaining<0)throw Error('Распределение счёта '+invoice.invoice_number+' превышает его сумму');
  const weights=[...allocations.map(e=>cents(e.amount)),remaining],paid=allocatePaid(cents(invoice.paid_amount),weights);
  const vatProfile=data.invoice_vat?.find(v=>v.invoice_id===invoice.id),vatParts=allocatePaid(vatProfile?.vat_rate===null||vatProfile?.vat_rate===undefined?0:vatFromGross(total,Number(vatProfile.vat_rate)),weights);
  allocations.forEach((e,i)=>rows.push({id:e.id,expenseId:e.id,date:e.expense_date,category:'contractor',amount:weights[i],vat:vatProfile?.input_vat_confirmed?vatParts[i]:0,pendingVat:vatProfile?.input_vat_confirmed?0:vatParts[i],paid:paid[i],held:0,customer:e.customer_id||'',site:e.site_id||'',service:e.service_name||'',trip:e.trip_id||'',vehicle:e.vehicle_id||'',invoice:invoice.id,notes:e.notes||'Счёт '+invoice.invoice_number,unallocated:!e.customer_id&&!e.site_id&&!e.trip_id}));
  if(remaining>0)rows.push({id:'invoice-'+invoice.id,expenseId:null,date:invoice.invoice_date,category:'contractor',amount:remaining,vat:vatProfile?.input_vat_confirmed?vatParts.at(-1)!:0,pendingVat:vatProfile?.input_vat_confirmed?0:vatParts.at(-1)!,paid:paid.at(-1)!,held:0,customer:'',site:'',service:'',trip:'',vehicle:'',invoice:invoice.id,notes:'Не распределён счёт '+invoice.invoice_number,unallocated:true});
 }
 for(const a of data.accruals.filter(a=>a.active)){
  const t=data.trips.find(t=>t.id===a.trip_id&&t.status==='delivered');if(!t)continue;
  const shared={expenseId:null,date:a.accrual_date,customer:t.customer_id||'',site:t.site_id||'',service:t.service_name||'',trip:t.id,vehicle:t.vehicle_id||'',invoice:'',vat:0,pendingVat:0,unallocated:false};
  rows.push({...shared,id:'salary-'+a.id,category:'salary',amount:cents(a.base)+cents(a.bonus),paid:sum(data.payments.filter(p=>p.accrual_id===a.id&&p.kind==='salary').map(p=>cents(p.amount))),held:sum(data.deductions.filter(d=>d.accrual_id===a.id).map(d=>cents(d.amount))),notes:'Зарплата по рейсу '+t.trip_number});
  rows.push({...shared,id:'tax-'+a.id,category:'payroll_tax',amount:cents(a.tax),paid:sum(data.payments.filter(p=>p.accrual_id===a.id&&p.kind==='tax').map(p=>cents(p.amount))),held:0,notes:'Налог компании по рейсу '+t.trip_number});
 }
 return rows;
}
export function profitReport(data:ProfitData,filter:ProfitFilter){
 const completed=data.trips.filter(t=>t.status==='delivered'&&t.trip_date&&inDates(t.trip_date,filter)&&inContext(t.customer_id,t.site_id,t.service_name,filter));
 const allCosts=profitCosts(data),costs=allCosts.filter(e=>inDates(e.date,filter)&&inContext(e.customer,e.site,e.service,filter));
 const revenue=sum(completed.map(t=>tripEarnings(t,data.settings).net)),expense=sum(costs.map(e=>e.amount-e.vat)),profit=revenue-expense,margin=revenue?profit/revenue*100:null;
 const categories=Object.entries(expenseCategories).map(([id,name])=>({id,name,amount:sum(costs.filter(e=>e.category===id).map(e=>e.amount-e.vat))})).filter(c=>c.amount!==0);
 const contractor=costs.filter(e=>e.category==='contractor'),taxes=costs.filter(e=>e.category==='tax'||e.category==='payroll_tax');
 const serviceMap=new Map<string,{customer:string;site:string;service:string;unit:string;volume:number;revenue:number;gross:number;vat:number;trips:number}>();
 for(const t of completed){const key=JSON.stringify([t.customer_id,t.site_id,t.service_name,t.unit]);const row=serviceMap.get(key)||{customer:t.customer_id||'',site:t.site_id||'',service:t.service_name||'Без названия',unit:t.unit||'м³',volume:0,revenue:0,gross:0,vat:0,trips:0};row.volume+=Number(t.volume);const earned=tripEarnings(t,data.settings);row.revenue+=earned.net;row.gross+=earned.gross;row.vat+=earned.vat;row.trips++;serviceMap.set(key,row)}
 const objectIds=new Set([...completed.map(t=>t.site_id||''),...costs.map(e=>e.site)].filter(Boolean));
 const objects=Array.from(objectIds).map(id=>{const earned=sum(completed.filter(t=>t.site_id===id).map(t=>tripEarnings(t,data.settings).net)),spent=sum(costs.filter(c=>c.site===id).map(c=>c.amount-c.vat));return {id,revenue:earned,expense:spent,profit:earned-spent,margin:earned?(earned-spent)/earned*100:null}});
 const missingPayroll=completed.filter(t=>!t.carrier_id&&!data.accruals.some(a=>a.active&&a.trip_id===t.id));
 const missingContractor=completed.filter(t=>t.carrier_id&&!data.expenses.some(e=>e.category==='contractor'&&e.trip_id===t.id));
 const unallocated=allCosts.filter(e=>e.unallocated&&inDates(e.date,filter));
 const vatConfigured=data.settings?.prices_include_vat!==null&&data.settings?.prices_include_vat!==undefined,outputVat=vatConfigured?sum(completed.map(t=>tripEarnings(t,data.settings).vat)):null,inputVat=sum(costs.map(c=>c.vat)),pendingInputVat=sum(costs.map(c=>c.pendingVat));
 return {vatConfigured,outputVat,inputVat,pendingInputVat,vatPayable:outputVat===null?null:Math.max(0,outputVat-inputVat),vatExcess:outputVat===null?null:Math.max(0,inputVat-outputVat),revenueGross:sum(completed.map(t=>tripEarnings(t,data.settings).gross)),grossExpense:sum(costs.map(c=>c.amount)),completed,costs,categories,services:Array.from(serviceMap.values()),objects,revenue,expense,profit,margin,unallocated,unallocatedTotal:sum(unallocated.map(e=>e.amount-e.vat)),missingPayroll,missingContractor,contractorCost:sum(contractor.map(e=>e.amount)),contractorPaid:sum(contractor.map(e=>e.paid)),contractorDue:sum(contractor.map(e=>e.amount-e.paid)),tax:sum(taxes.map(e=>e.amount)),taxPaid:sum(taxes.map(e=>e.paid)),taxDue:sum(taxes.map(e=>e.amount-e.paid)),unassignedToObjects:sum(costs.filter(e=>!e.site).map(e=>e.amount-e.vat)),warnings:missingPayroll.length+missingContractor.length+unallocated.length+(vatConfigured?0:1)+(pendingInputVat?1:0)};
}
