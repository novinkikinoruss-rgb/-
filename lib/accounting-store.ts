import {db} from './supabase';
import type {Customer,Site,Order,Trip,Invoice,InvoiceLine,AccountingDocument,DocumentTrip,Payment,Accrual,PayrollPayment,Driver,PayrollDeduction,Fine} from './accounting';
// PostgREST ограничивает размер ответа: читаем страницы в стабильном порядке.
async function read<T>(table:string,columns:string,softDelete=false):Promise<T[]> {
  const rows:T[]=[];
  for(let offset=0;;offset+=500){
    let query=db.from(table).select(columns).order('id').range(offset,offset+499);
    if(softDelete)query=query.is('deleted_at',null);
    const {data,error}=await query;
    if(error)throw new Error(table+': '+error.message);
    rows.push(...(data??[]) as unknown as T[]);
    if((data?.length??0)<500)return rows;
  }
}
export async function loadAccounting() {
  const [customers,sites,orders,trips,invoices,lines,documents,documentTrips,payments,accruals,payrollPayments,drivers,deductions,fines]=await Promise.all([
    read<Customer>('crm_customers','id,name,inn,kpp,legal_address',true),read<Site>('crm_sites','id,customer_id,name,route_km',true),read<Order>('crm_orders','id,customer_id,site_id',true),read<Trip>('crm_trips','id,customer_id,order_id,site_id,trip_number,trip_date,status,service_name,volume,unit_price,driver_id',true),
    read<Invoice>('crm_invoices','id,customer_id,invoice_number,invoice_date,amount,trip_id,seller_snapshot,buyer_snapshot',true),read<InvoiceLine>('crm_invoice_lines','id,invoice_id,trip_id,site_id,trip_number,trip_date,service_name,volume,unit_price,amount'),read<AccountingDocument>('crm_accounting_documents','id,invoice_id,customer_id,kind,document_number,document_date,amount'),read<DocumentTrip>('crm_accounting_document_trips','id,document_id,trip_id'),read<Payment>('crm_invoice_payments','id,invoice_id,amount,payment_date'),read<Accrual>('crm_payroll_accruals','id,driver_id,trip_id,customer_id,site_id,accrual_date,distance_km,base,bonus,tax,active'),read<PayrollPayment>('crm_payroll_payments','id,accrual_id,kind,amount,payment_date'),read<Driver>('crm_drivers','id,full_name'),read<PayrollDeduction>('crm_payroll_deductions','id,accrual_id,fine_id,amount,deduction_date'),read<Fine>('crm_driver_fines','id,driver_id,order_id,fine_date,amount,reason,paid',true)
  ]);
  return {customers,sites,orders,trips,invoices,lines,documents,documentTrips,payments,accruals,payrollPayments,drivers,deductions,fines};
}
export type AccountingData=Awaited<ReturnType<typeof loadAccounting>>;
export async function loadTripDocuments(){
  const [invoices,lines,documents,documentTrips]=await Promise.all([
    read<Invoice>('crm_invoices','id,customer_id,invoice_number,invoice_date,amount,trip_id',true),
    read<InvoiceLine>('crm_invoice_lines','id,invoice_id,trip_id,site_id,trip_number,trip_date,service_name,volume,unit_price,amount'),
    read<AccountingDocument>('crm_accounting_documents','id,invoice_id,customer_id,kind,document_number,document_date,amount'),
    read<DocumentTrip>('crm_accounting_document_trips','id,document_id,trip_id')
  ]);return {invoices,lines,documents,documentTrips};
}
export type TripDocuments=Awaited<ReturnType<typeof loadTripDocuments>>;
