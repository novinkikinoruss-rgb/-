import {allocatePaid,cents,profitCosts,profitReport,tripEarnings,type ProfitData,type ProfitFilter,type ProfitTrip} from './profit.ts';
function distribute(total:number,weights:number[]){
 if(!Number.isSafeInteger(total)||total<0||weights.some(w=>!Number.isSafeInteger(w)||w<=0))throw Error('Некорректная сумма распределения');
 const denominator=weights.reduce((a,b)=>a+BigInt(b),BigInt(0));if(!denominator)return [];
 const scaled=weights.map(w=>BigInt(total)*BigInt(w)),parts=scaled.map(v=>Number(v/denominator));let left=total-parts.reduce((a,b)=>a+b,0);
 for(const row of scaled.map((v,i)=>({i,r:v%denominator})).sort((a,b)=>a.r>b.r?-1:a.r<b.r?1:a.i-b.i)){if(left--<=0)break;parts[row.i]++}return parts;
}
const sum=(values:number[])=>values.reduce((a,b)=>a+b,0);
const matches=(customer:string|null,site:string|null,service:string|null,f:ProfitFilter)=>(!f.customer||customer===f.customer)&&(!f.site||site===f.site)&&(!f.service||(service||'').trim()===f.service.trim());
const dates=(date:string,f:ProfitFilter)=>(!f.from||date>=f.from)&&(!f.to||date<=f.to);
export function planComparison(data:ProfitData,filter:ProfitFilter){return (data.plans||[]).filter(p=>matches(p.customer_id,p.site_id,p.service_name,filter)&&(!filter.from||p.date_to>=filter.from)&&(!filter.to||p.date_from<=filter.to)).map(p=>{
 const actual=profitReport(data,{from:p.date_from,to:p.date_to,customer:p.customer_id,site:p.site_id||'',service:p.service_name||''}),revenue=cents(p.revenue),cost=cents(p.cost),profit=revenue-cost,margin=revenue?profit/revenue*100:null;
 return {plan:p,revenue,cost,profit,margin,actual,deltaProfit:actual.vatConfigured?actual.profit-profit:null,deltaMargin:actual.vatConfigured&&actual.margin!==null&&margin!==null?actual.margin-margin:null};
})}
export type CalendarEntry={id:string;sourceKind:string;sourceId:string;manual:boolean;title:string;kind:'incoming'|'outgoing'|'tax';dueDate:string|null;amount:number;paid:number;held:number;remaining:number;status:'paid'|'partial'|'overdue'|'planned';customer:string;site:string;notes:string};
export function paymentCalendar(data:ProfitData,filter:ProfitFilter,today:string,showPaid=false){
 const entries:CalendarEntry[]=[],costs=profitCosts(data),dateFor=(kind:string,id:string,fallback:string|null=null)=>data.due_dates?.find(d=>d.source_kind===kind&&d.source_id===id)?.due_date||fallback;
 function add(row:Omit<CalendarEntry,'remaining'|'status'>){const remaining=row.amount-row.paid-row.held;const status=remaining<=0?'paid':row.dueDate&&row.dueDate<today?'overdue':row.paid+row.held>0?'partial':'planned';if((showPaid||remaining>0)&&(!row.dueDate||dates(row.dueDate,filter)))entries.push({...row,remaining:Math.max(0,remaining),status})}
 for(const e of data.events||[]){if(!matches(e.customer_id,e.site_id,e.service_name,filter))continue;add({id:'manual-'+e.id,sourceKind:'manual',sourceId:e.id,manual:true,title:e.title,kind:e.kind,dueDate:e.due_date,amount:cents(e.amount),paid:cents(e.paid_amount),held:0,customer:e.customer_id||'',site:e.site_id||'',notes:e.notes})}
 for(const d of data.accounting_invoices||[]){
  const weights=d.snapshot.items.map(i=>cents(i.gross)),covered=allocatePaid(cents(d.paid_amount)+cents(d.credited),weights),paid=allocatePaid(cents(d.paid_amount),covered),credits=covered.map((v,i)=>v-paid[i]);
  const selected=d.snapshot.items.map((i,index)=>({i,index})).filter(({i})=>matches(d.customer_id,i.site_id||d.site_id,i.service||d.service_name,filter));
  if(!selected.length)continue;
  add({id:'customer-invoice-'+d.id,sourceKind:'customer_invoice',sourceId:d.id,manual:false,title:(d.kind==='advance'?'Аванс ':'Счёт заказчику ')+d.number,kind:'incoming',dueDate:d.due_date,amount:sum(selected.map(({index})=>weights[index])),paid:sum(selected.map(({index})=>paid[index])),held:sum(selected.map(({index})=>credits[index])),customer:d.customer_id,site:d.site_id||'',notes:'Из Бухгалтерии; зачтённый аванс уменьшает остаток. При фильтре показана доля выбранных услуг.'});
 }
 for(const i of data.invoices){const parts=costs.filter(c=>c.invoice===i.id&&matches(c.customer,c.site,c.service,filter));if(!parts.length)continue;add({id:'invoice-'+i.id,sourceKind:'invoice',sourceId:i.id,manual:false,title:'Счёт '+i.invoice_number+' · '+(data.carriers.find(c=>c.id===i.counterparty_id)?.name||'Контрагент'),kind:'outgoing',dueDate:dateFor('invoice',i.id,i.due_date||null),amount:sum(parts.map(c=>c.amount)),paid:sum(parts.map(c=>c.paid)),held:0,customer:filter.customer,site:filter.site,notes:'Суммы и оплаты из счёта. При фильтре по объекту показана его доля; оплата распределяется пропорционально.'})}
 for(const c of costs.filter(c=>!c.invoice&&c.expenseId)){if(!matches(c.customer,c.site,c.service,filter))continue;add({id:'expense-'+c.expenseId,sourceKind:'expense',sourceId:c.expenseId!,manual:false,title:c.notes||'Учтённый расход',kind:c.category==='tax'?'tax':'outgoing',dueDate:dateFor('expense',c.expenseId!),amount:c.amount,paid:c.paid,held:c.held,customer:c.customer,site:c.site,notes:'Оплата из журнала расходов. Изменение срока не создаёт новый расход.'})}
 for(const a of data.accruals.filter(a=>a.active)){const trip=data.trips.find(t=>t.id===a.trip_id&&t.status==='delivered');if(!trip||!matches(trip.customer_id,trip.site_id,trip.service_name,filter))continue;for(const kind of ['salary','payroll_tax']){
  const payments=sum(data.payments.filter(p=>p.accrual_id===a.id&&p.kind===(kind==='salary'?'salary':'tax')).map(p=>cents(p.amount))),held=kind==='salary'?sum(data.deductions.filter(d=>d.accrual_id===a.id).map(d=>cents(d.amount))):0;
  add({id:kind+'-'+a.id,sourceKind:kind,sourceId:a.id,manual:false,title:(kind==='salary'?'Зарплата':'Налог на зарплату')+' · рейс '+trip.trip_number,kind:kind==='salary'?'outgoing':'tax',dueDate:dateFor(kind,a.id),amount:kind==='salary'?cents(a.base)+cents(a.bonus):cents(a.tax),paid:payments,held,customer:trip.customer_id||'',site:trip.site_id||'',notes:'Из начислений. Факт оплаты отмечается в разделе «ТС и водители».'});
 }}
 entries.sort((a,b)=>(a.dueDate||'9999').localeCompare(b.dueDate||'9999')||a.id.localeCompare(b.id));
 const incoming=sum(entries.filter(e=>e.kind==='incoming').map(e=>e.remaining)),outgoing=sum(entries.filter(e=>e.kind!=='incoming').map(e=>e.remaining));
 return {entries,incoming,outgoing,flow:incoming-outgoing,tax:sum(entries.filter(e=>e.kind==='tax').map(e=>e.remaining)),overdue:entries.filter(e=>e.status==='overdue').length,withoutDate:entries.filter(e=>!e.dueDate).length};
}
export function tripDistance(data:ProfitData,trip:ProfitTrip){const accrued=data.accruals.find(a=>a.active&&a.trip_id===trip.id);if(accrued?.distance_km!==null&&accrued?.distance_km!==undefined)return {km:Number(accrued.distance_km),basis:'payroll'};if(trip.distance_km_snapshot!==null&&trip.distance_km_snapshot!==undefined)return {km:Number(trip.distance_km_snapshot),basis:'snapshot'};const route=data.sites.find(s=>s.id===trip.site_id)?.route_km;return {km:route===null||route===undefined||route===''?null:Number(route),basis:'object_current'}}
export function tripCostReport(data:ProfitData,filter:ProfitFilter,includeGeneral=false,allocation:'distance'|'equal'='distance'){
 const trips=data.trips.filter(t=>t.status==='delivered'&&t.trip_date&&dates(t.trip_date,filter));
 const rows=trips.map(t=>({trip:t,...tripDistance(data,t),direct:0,distributed:0,sources:0,usedEqualFallback:false}));
 const costs=profitCosts(data).filter(c=>dates(c.date,filter));let undistributed=0,excludedGeneral=0;
 for(const cost of costs){const value=cost.amount-cost.vat;
  if(cost.trip){const row=rows.find(r=>r.trip.id===cost.trip);if(row){row.direct+=value;row.sources++}else undistributed+=value;continue}
  const general=!cost.customer&&!cost.site&&!cost.service&&!cost.vehicle;
  if(cost.category==='contractor'&&general){undistributed+=value;continue}
  if(general&&!includeGeneral){excludedGeneral+=value;continue}
  const candidates=rows.filter(r=>(!cost.customer||r.trip.customer_id===cost.customer)&&(!cost.site||r.trip.site_id===cost.site)&&(!cost.service||(r.trip.service_name||'').trim()===cost.service.trim())&&(!cost.vehicle||r.trip.vehicle_id===cost.vehicle));
  if(!candidates.length){undistributed+=value;continue}
  const useDistance=allocation==='distance'&&candidates.every(r=>r.km!==null&&Number.isFinite(r.km)&&r.km>0&&Math.round(r.km*1000)>0),weights=candidates.map(r=>useDistance?Math.round(r.km!*1000):1),parts=distribute(value,weights);
  candidates.forEach((r,i)=>{r.distributed+=parts[i];r.sources++;if(allocation==='distance'&&!useDistance)r.usedEqualFallback=true});
 }
 const selected=rows.filter(r=>matches(r.trip.customer_id,r.trip.site_id,r.trip.service_name,filter)).map(r=>{const cost=r.direct+r.distributed,earned=tripEarnings(r.trip,data.settings),hasDistance=r.km!==null&&Number.isFinite(r.km)&&r.km>0;return {...r,cost,revenue:earned.net,profit:earned.net-cost,perKm:hasDistance&&r.sources?cost/r.km!:null}}),totalCost=sum(selected.map(r=>r.cost)),known=selected.filter(r=>r.km!==null&&Number.isFinite(r.km)&&r.km>0&&r.sources>0),knownKm=sum(known.map(r=>r.km!));
 return {rows:selected,totalCost,perTrip:selected.length?totalCost/selected.length:null,perKm:knownKm?sum(known.map(r=>r.cost))/knownKm:null,knownKm,missingDistance:selected.filter(r=>r.km===null||!Number.isFinite(r.km)||r.km<=0).length,missingCosts:selected.filter(r=>!r.sources).length,currentObjectDistances:selected.filter(r=>r.basis==='object_current').length,undistributed,excludedGeneral,totalInput:sum(costs.map(c=>c.amount-c.vat)),totalAllocatedAllTrips:sum(rows.map(r=>r.direct+r.distributed))};
}
