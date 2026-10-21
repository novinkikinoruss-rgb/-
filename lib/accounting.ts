export type Customer = {id:string; name:string; inn:string|null; kpp?:string|null; legal_address?:string|null};
export type Site = {id:string; customer_id:string; name:string; route_km:number|null};
export type Order = {id:string; customer_id:string; site_id:string|null};
export type Trip = {id:string; customer_id:string|null; order_id:string|null; site_id:string|null; trip_number:string; trip_date:string|null; status:string; service_name:string|null; volume:number|null; unit_price:number|null; driver_id:string|null};
export type Seller = {name:string; inn:string; kpp:string; address:string; bank:string; bik:string; account:string};
export type Invoice = {id:string; customer_id:string; invoice_number:string; invoice_date:string; amount:number; trip_id:string|null; seller_snapshot?:Partial<Seller>; buyer_snapshot?:Partial<Customer>};
export type InvoiceLine = {invoice_id:string; trip_id:string; site_id:string|null; trip_number:string; trip_date:string; service_name:string; volume:number; unit_price:number; amount:number};
export type AccountingDocument = {id:string; invoice_id:string; customer_id:string; kind:'register'|'upd'; document_number:string; document_date:string; amount:number};
export type DocumentTrip = {document_id:string; trip_id:string};
export type Payment = {id:string; invoice_id:string; amount:number; payment_date:string};
export type Accrual = {id:string; driver_id:string; trip_id:string; customer_id:string; site_id:string; accrual_date:string; distance_km:number; base:number; bonus:number; tax:number; active:boolean};
export type PayrollPayment = {id:string; accrual_id:string; kind:'salary'|'tax'; amount:number; payment_date:string};
export type PayrollDeduction = {id:string; accrual_id:string; fine_id:string; amount:number; deduction_date:string};
export type Driver = {id:string; full_name:string};
export type Fine = {reason:string; id:string; driver_id:string; amount:number; fine_date:string; paid:boolean; order_id:string|null; trip_id?:string|null};
export type Filters = {customerId:string; siteId:string; from:string; to:string};
export const roundMoney = (n:number) => Math.round((n + Number.EPSILON) * 100) / 100;
export function validPeriod(from:string,to:string) { return !from || !to || from <= to; }
export function inPeriod(date:string|null,from:string,to:string) {return !!date && (!from||date>=from)&&(!to||date<=to);}
export function tripContext(t:Trip,orders:Order[]) {
  const order=orders.find(o=>o.id===t.order_id);
  return {customerId:t.customer_id??order?.customer_id,siteId:t.site_id??order?.site_id};
}
export function completedTrips(trips:Trip[],orders:Order[],f:Filters) {
  if(!validPeriod(f.from,f.to)) return [];
  return trips.filter(t=>{const c=tripContext(t,orders);return t.status==='delivered'&&!!c.customerId&&(!f.customerId||c.customerId===f.customerId)&&(!f.siteId||c.siteId===f.siteId)&&inPeriod(t.trip_date,f.from,f.to);});
}
export function invoiceTotal(lines:Pick<InvoiceLine,'volume'|'unit_price'>[]) {
  return roundMoney(lines.reduce((s,l)=>s+roundMoney(Number(l.volume)*Number(l.unit_price)),0));
}
export function reconciliation(invoices:Invoice[],payments:Payment[],from:string,to:string) {
  // Оплаты в периоде включают счета, выставленные до начала периода.
  const ids=new Set(invoices.map(i=>i.id));
  const events=[...invoices.map(i=>({date:i.invoice_date,label:'Счёт № '+i.invoice_number,debit:Number(i.amount),credit:0,id:'i'+i.id})),...payments.filter(p=>ids.has(p.invoice_id)).map(p=>({date:p.payment_date,label:'Оплата счёта № '+invoices.find(i=>i.id===p.invoice_id)!.invoice_number,debit:0,credit:Number(p.amount),id:'p'+p.id}))].sort((a,b)=>a.date.localeCompare(b.date)||a.id.localeCompare(b.id));
  const opening=roundMoney(events.filter(e=>!!from&&e.date<from).reduce((s,e)=>s+e.debit-e.credit,0));
  let balance=opening;
  const rows=events.filter(e=>inPeriod(e.date,from,to)).map(e=>({...e,balance:balance=roundMoney(balance+e.debit-e.credit)}));
  return {opening,rows,closing:balance,debit:roundMoney(rows.reduce((s,e)=>s+e.debit,0)),credit:roundMoney(rows.reduce((s,e)=>s+e.credit,0))};
}
export function payrollSummary(accruals:Accrual[],payments:PayrollPayment[],deductions:PayrollDeduction[]=[]) {
  const active=accruals.filter(a=>a.active),ids=new Set(active.map(a=>a.id));
  const base=roundMoney(active.reduce((s,a)=>s+Number(a.base),0));
  const bonus=roundMoney(active.reduce((s,a)=>s+Number(a.bonus),0));
  const tax=roundMoney(active.reduce((s,a)=>s+Number(a.tax),0));
  const paid=roundMoney(payments.filter(p=>ids.has(p.accrual_id)&&p.kind==='salary').reduce((s,p)=>s+Number(p.amount),0));
  const taxPaid=roundMoney(payments.filter(p=>ids.has(p.accrual_id)&&p.kind==='tax').reduce((s,p)=>s+Number(p.amount),0));
  const deducted=roundMoney(deductions.filter(d=>ids.has(d.accrual_id)).reduce((s,d)=>s+Number(d.amount),0));
  return {base,bonus,tax,paid,taxPaid,deducted,accrued:roundMoney(base+bonus),due:roundMoney(Math.max(0,base+bonus-paid-deducted)),taxDue:roundMoney(Math.max(0,tax-taxPaid))};
}
export function escapeHtml(value:unknown) {return String(value??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]!));}
export function csvCell(value:unknown) {let s=String(value??'');if(/^[=+@\-]/.test(s)&&!/^-[0-9]+([.,][0-9]+)?$/.test(s))s="'"+s;return '"'+s.replaceAll('"','""')+'"';}
