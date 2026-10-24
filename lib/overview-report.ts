import {allocatePaid,cents,tripEarnings,type ProfitData,type ProfitFilter,type ProfitTrip} from './profit.ts';
import type {AccountingDocument,AccountingCredit} from './accounting.ts';
export function overviewTrips<T extends ProfitTrip>(data:{trips:T[]},filter:ProfitFilter){return data.trips.filter(t=>(!filter.from||Boolean(t.trip_date&&t.trip_date>=filter.from))&&(!filter.to||Boolean(t.trip_date&&t.trip_date<=filter.to))&&(!filter.customer||t.customer_id===filter.customer)&&(!filter.site||t.site_id===filter.site)&&(!filter.service||(t.service_name||'').trim()===filter.service.trim()))}
export function customerOverview(data:ProfitData,documents:AccountingDocument[],credits:AccountingCredit[],filter:ProfitFilter){
 const trips=overviewTrips(data,filter).filter(t=>t.status==='delivered'&&t.trip_date),selected=new Set(trips.map(t=>t.id));
 const rows=new Map<string,{id:string;name:string;trips:number;gross:number;serviceCount:number;services:{name:string;unit:string;volume:number;gross:number;trips:number}[];closedGross:number;closingCount:number;billed:number;paid:number;credited:number;due:number;unbilled:number}>();
 for(const t of trips){const id=t.customer_id||'';let row=rows.get(id);if(!row){row={id,name:data.customers.find(c=>c.id===id)?.name||'Заказчик не указан',trips:0,gross:0,serviceCount:0,services:[],closedGross:0,closingCount:0,billed:0,paid:0,credited:0,due:0,unbilled:0};rows.set(id,row)}
  const amount=tripEarnings(t,data.settings).gross;row.trips++;row.gross+=amount;
  let service=row.services.find(s=>s.name===(t.service_name||'Без названия')&&s.unit===t.unit);if(!service){service={name:t.service_name||'Без названия',unit:t.unit,volume:0,gross:0,trips:0};row.services.push(service)}service.volume+=Number(t.volume);service.gross+=amount;service.trips++;
 }
 const closed=new Set<string>();
 for(const doc of documents.filter(d=>['issued','sent','signed'].includes(d.status))){
  const items=doc.snapshot?.items||[];
  if(doc.kind==='upd'||doc.kind==='registry'){
   const ids=new Set([...(doc.trip_ids||[]),...items.map(i=>i.trip_id).filter((id):id is string=>Boolean(id))].filter(id=>selected.has(id)));
   if(ids.size){const customers=new Set(trips.filter(t=>ids.has(t.id)).map(t=>t.customer_id||''));for(const id of customers){const row=rows.get(id);if(row)row.closingCount++}for(const id of ids)closed.add(id)}
  }
  if(doc.kind!=='invoice')continue;
  const selectedItems=items.map((item,index)=>({item,index})).filter(({item})=>item.trip_id&&selected.has(item.trip_id));
  if(!selectedItems.length)continue;
  const weights=items.map(i=>cents(i.gross)),paid=cents(doc.paid_amount),credited=credits.filter(c=>c.invoice_id===doc.id).reduce((s,c)=>s+cents(c.amount),0);
  const covered=allocatePaid(paid+credited,weights),paidParts=allocatePaid(paid,covered);
  for(const {item,index} of selectedItems){const trip=trips.find(t=>t.id===item.trip_id)!;const row=rows.get(trip.customer_id||'')!;row.billed+=weights[index];row.paid+=paidParts[index];row.credited+=covered[index]-paidParts[index]}
 }
 for(const t of trips)if(closed.has(t.id))rows.get(t.customer_id||'')!.closedGross+=tripEarnings(t,data.settings).gross;
 for(const row of rows.values()){row.serviceCount=row.services.length;row.due=Math.max(0,row.billed-row.paid-row.credited);row.unbilled=Math.max(0,row.gross-row.billed)}
 return Array.from(rows.values()).sort((a,b)=>b.gross-a.gross||a.name.localeCompare(b.name,'ru'));
}
