export type MobileRun={id:string;shift_id:string;duty_id:string;stage:string;trip_id:string|null;volume:number|null;created_at:string};
export type MobilePhoto={id:string;run_id:string|null;expense_id:string|null;kind:string;file_name:string};
export type MobileExpense={id:string;driver_id?:string;vehicle_id:string;kind:string;expense_date:string;litres:number|null;price:number|null;total:number;note:string};
export type SalaryRow={id:string;trip_id:string;date:string;base:number;bonus:number;deducted:number;trip_number:string;volume:number;unit:string;service_name:string};
export const runStages:Record<string,string>={heading:'В пути на погрузку',loading:'Погрузка',unloaded:'Выгрузился',completed:'Рейс завершён',interrupted:'Прерван: поломка'};
export function salaryAmount(rows:SalaryRow[]){return rows.reduce((n,x)=>n+Number(x.base)+Number(x.bonus)-Number(x.deducted),0)}
export function mapLink(point:string,address=''){
 const raw=point.trim();const found=raw.match(/https?:\/\/[^\s<>]+/i)?.[0];
 if(found){try{const u=new URL(found);if(u.protocol==='https:'&&(/(^|\.)yandex\.(ru|com|by|kz)$/.test(u.hostname)||u.hostname==='ya.ru'||u.hostname==='yandex.com.tr'))return u.href;}catch{}}
 const coords=raw.match(/^\s*(-?\d{1,3}(?:\.\d+)?)\s*[,;]\s*(-?\d{1,3}(?:\.\d+)?)\s*$/);
 if(coords&&Math.abs(Number(coords[1]))<=90&&Math.abs(Number(coords[2]))<=180)return 'https://yandex.ru/maps/?rtext=~'+encodeURIComponent(coords[1]+','+coords[2])+'&rtt=auto';
 return 'https://yandex.ru/maps/?text='+encodeURIComponent(found?(address||raw):(raw||address));
}
