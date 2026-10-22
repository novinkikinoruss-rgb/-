export type FleetAccrual={id:string;trip_id:string;driver_id:string;site_id:string;accrual_date:string;distance_km:number;rate:number;bonus_pct:number;tax_pct:number;base:number;bonus:number;tax:number;active:boolean};
export type FleetPayment={id:string;accrual_id:string;kind:'salary'|'tax';amount:number;payment_date:string};
export type FleetDeduction={id:string;accrual_id:string;fine_id:string;amount:number;deduction_date:string};
export const roundMoney=(n:number)=>Math.round((n+Number.EPSILON)*100)/100;
export function fleetCalculation(rate:number,oneWayKm:number,bonusPct:number,taxPct:number,fines=0){
 for(const n of [rate,oneWayKm,bonusPct,taxPct,fines])if(!Number.isFinite(n)||n<0)throw Error('Ставка, плечо, проценты и штрафы должны быть неотрицательными числами');
 const base=roundMoney(rate*oneWayKm),bonus=roundMoney(base*bonusPct/100),gross=roundMoney(base+bonus),tax=roundMoney(gross*taxPct/100);
 return {base,bonus,gross,tax,toDriver:roundMoney(gross-fines),companyCost:roundMoney(gross+tax)};
}
export function accrualBalance(a:FleetAccrual,payments:FleetPayment[],deductions:FleetDeduction[]){
 const own=payments.filter(p=>p.accrual_id===a.id),paid=roundMoney(own.filter(p=>p.kind==='salary').reduce((s,p)=>s+Number(p.amount),0)),taxPaid=roundMoney(own.filter(p=>p.kind==='tax').reduce((s,p)=>s+Number(p.amount),0));
 const held=roundMoney(deductions.filter(d=>d.accrual_id===a.id).reduce((s,d)=>s+Number(d.amount),0)),gross=roundMoney(Number(a.base)+Number(a.bonus));
 return {gross,paid,taxPaid,held,due:roundMoney(gross-held-paid),taxDue:roundMoney(Number(a.tax)-taxPaid),companyCost:roundMoney(gross+Number(a.tax))};
}
export function maintenanceState(odometer:number,next:number|null,before:number){
 if(next===null)return {status:'unset',remaining:null,label:'Не настроено'};
 const remaining=next-odometer;
 return {status:remaining<=0?'overdue':remaining<=before?'soon':'ok',remaining,label:remaining<=0?'Требуется обслуживание':remaining<=before?'Скоро обслуживание':'По плану'};
}
