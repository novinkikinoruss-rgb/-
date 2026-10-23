export type TripRow={id:string;trip_number:string;trip_date:string|null;customer_id:string|null;site_id:string|null;vehicle_id:string|null;driver_id:string|null;carrier_id:string|null;loading_address:string;unloading_address:string;volume:number;unit:string;unit_price:number;service_name:string|null;status:string;modified_at:string;locked:boolean;documents_confirmed?:boolean};
export type TripFilter={from:string;to:string;customer:string;site:string;search:string};
export const blankTripFilter:TripFilter={from:'',to:'',customer:'',site:'',search:''};
export function filterTrips(rows:TripRow[],filter:TripFilter,vehicleNames:Record<string,string>={}){
 const query=filter.search.trim().toLocaleLowerCase('ru-RU');
 return rows.filter(t=>(!filter.from||Boolean(t.trip_date&&t.trip_date>=filter.from))&&(!filter.to||Boolean(t.trip_date&&t.trip_date<=filter.to))&&(!filter.customer||t.customer_id===filter.customer)&&(!filter.site||t.site_id===filter.site)&&(!query||[t.trip_number,t.loading_address,t.unloading_address,vehicleNames[t.vehicle_id||'']].join(' ').toLocaleLowerCase('ru-RU').includes(query)));
}
export function toggleVisibleSelection(selected:string[],visible:string[],checked:boolean){
 const current=new Set(selected);for(const id of visible)if(checked)current.add(id);else current.delete(id);return Array.from(current);
}
function localDate(date:Date){return date.getFullYear()+'-'+String(date.getMonth()+1).padStart(2,'0')+'-'+String(date.getDate()).padStart(2,'0')}
export function tripPeriod(period:string,now=new Date()){
 const start=new Date(now.getFullYear(),now.getMonth(),now.getDate());
 if(period==='today')return {from:localDate(start),to:localDate(start)};
 if(period==='week'){start.setDate(start.getDate()-6);return {from:localDate(start),to:localDate(now)}}
 if(period==='month'){start.setDate(1);return {from:localDate(start),to:localDate(now)}}
 return {from:'',to:''};
}
export function csvCell(value:unknown){
 let s=String(value??'');if(/^[=+@\-\t\r]/.test(s))s="'"+s;
 return '"'+s.replaceAll('"','""')+'"';
}
export function volumeTotals(rows:TripRow[]){
 const result:Record<string,number>={};for(const t of rows){const unit=t.unit||'м³';result[unit]=(result[unit]||0)+Number(t.volume||0)}
 return Object.entries(result).map(([unit,total])=>({unit,total:Math.round((total+Number.EPSILON)*1000)/1000}));
}

