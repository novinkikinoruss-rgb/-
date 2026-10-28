export type DispatchRequest={id:string;number:number;customer_id:string;site_id:string;date_from:string;date_to:string;payload:Record<string,string>;version:number;cancelled_at:string|null;modified_at:string};
export type DispatchShift={id:string;request_id:string;shift_date:string;vehicle_id:string;driver_id:string|null;carrier_id:string|null;driver_name:string;starts_at:string;ends_at:string;snapshot:Record<string,string>;status:string;version:number;sent_at:string|null;seen_at:string|null;accepted_at:string|null;response_note:string};
export type DispatchDocument={id:string;shift_id:string;batch_id:string;kind:string;number:number;copies:number;snapshot:Record<string,string>};
export type DispatchResult={trip_deleted?:boolean;id:string;shift_id:string;trip_id:string;volume:number;unit:string;created_at:string};
export type DispatchTemplate={id:string;kind:string;name:string;storage_path:string;active:boolean;created_at:string};
export type DispatchData={requests:DispatchRequest[];shifts:DispatchShift[];documents:DispatchDocument[];templates:DispatchTemplate[];results:DispatchResult[];events:{id:number;request_id:string;shift_id:string|null;action:string;created_at:string}[];vehicles:{id:string;plate:string;carrier_id:string|null;is_subcontractor_vehicle:boolean;assigned_driver_id:string|null;status:string}[];drivers:{id:string;full_name:string;carrier_id:string|null;ready:boolean}[];carriers:{id:string;name:string}[]};
export type DriverDispatchShift=Omit<DispatchShift,'snapshot'|'seen_at'|'driver_id'|'carrier_id'|'driver_name'>&{details:Record<string,string>;results:DispatchResult[]};
export const emptyDispatch=():DispatchData=>({requests:[],shifts:[],documents:[],templates:[],results:[],events:[],vehicles:[],drivers:[],carriers:[]});
export const documentKinds:Record<string,string>={waybill:'Путевой лист',invoice:'Накладная',ttn:'ТТН'};
export const dispatchStatuses:Record<string,string>={draft:'Не отправлена',sent:'Ожидает подтверждения',accepted:'Принята водителем',rejected:'Отказ водителя',completed:'Работа завершена',cancelled:'Отменена'};
export function businessDate(zone='Europe/Moscow'){return new Intl.DateTimeFormat('en-CA',{timeZone:zone,year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date())}
export function addDays(date:string,days:number){const d=new Date(date+'T12:00:00Z');d.setUTCDate(d.getUTCDate()+days);return d.toISOString().slice(0,10)}
export function workMode(from:string,to:string){return to<=from?'Ночная · окончание на следующий день':Number(from.slice(0,2))>=18||Number(from.slice(0,2))<6?'Ночная · одна смена':'Дневная · одна смена'}
export function canAssignVehicle(status:string){return ['available','busy'].includes(status)}
const escape=(value:unknown)=>String(value??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]!));
export function dispatchPrintHtml(docs:DispatchDocument[]){
 const sections=docs.flatMap(d=>Array.from({length:d.copies},(_,i)=>{const p=d.snapshot;const fields=[['Заявка','З'+p.number],['Дата смены',p.shift_date],['Автомобиль',p.plate],['Водитель',p.driver_name],['Услуга',p.service_name],['Наименование',p.cargo_name],['Масса по заявке',p.cargo_mass],['От (грузоотправитель)',p.sender],['Кому (грузополучатель)',p.recipient],['Погрузка',p.loading_address],['Точка погрузки',p.loading_point],['Режим погрузки',p.loading_from+' — '+p.loading_to],['Выгрузка',p.unloading_address],['Точка выгрузки',p.unloading_point],['Режим выгрузки',p.unloading_from+' — '+p.unloading_to],['Ответственный',p.contact_name+' · '+p.contact_phone],['Фактическое количество','________________ '+p.unit]];return '<section><h1>'+escape(documentKinds[d.kind]||d.kind)+' № '+d.number+'</h1><p>Экземпляр '+(i+1)+' из '+d.copies+'</p><p class="draft">ПРОЕКТ БЛАНКА · пользовательский шаблон ещё не настроен</p><table>'+fields.map(([k,v])=>'<tr><th>'+escape(k)+'</th><td>'+escape(v||'________________')+'</td></tr>').join('')+'</table><p>Примечания: '+escape(p.notes)+'</p><p class="sign">Водитель ________________ &nbsp; Отпустил ________________ &nbsp; Принял ________________</p></section>'})).join('');
 return '<!doctype html><html lang="ru"><meta charset="utf-8"><title>Бланки распределения</title><style>body{font:12px Arial;color:#26382d;margin:24px}section{break-after:page}section:last-child{break-after:auto}h1{font-size:20px}table{border-collapse:collapse;width:100%}th,td{border:1px solid #b5c1ae;text-align:left;padding:8px}th{width:30%}.draft{padding:8px;background:#f5eedc;color:#786241}.sign{margin-top:40px}@page{size:A4;margin:12mm}@media print{button{display:none}body{margin:0}}</style><button onclick="window.print()">Печать / сохранить PDF</button>'+sections+'</html>';
}
export function printDispatch(docs:DispatchDocument[]){if(!docs.length)throw Error('Сначала сформируйте бланки');const win=window.open('','_blank');if(!win)throw Error('Разрешите открытие окна печати в браузере');win.opener=null;win.document.write(dispatchPrintHtml(docs));win.document.close();win.focus();}

// Copy only editable request details; new identity/dates and fresh service pricing remain separate.
export function copyDispatchFields(source:DispatchRequest,current:Record<string,string>){
 const keys=['loading_address','loading_point','unloading_address','unloading_point','loading_from','loading_to','unloading_from','unloading_to','contact_name','contact_phone','sender','recipient','cargo_name','cargo_mass','notes','time_zone'];
 return {...current,...Object.fromEntries(keys.map(key=>[key,source.payload[key]||''])),customer_id:source.customer_id,site_id:source.site_id};
}
export function dispatchSourceNumber(value:string){const match=value.trim().match(/^(?:[ЗзZz][-\s]*)?(\d+)$/);return match?Number(match[1]):null}

export type RequestFilter={customer:string;service:string;site:string;vehicle:string;driver:string;from:string;to:string;query:string;cancelled:boolean};
export const blankRequestFilter:RequestFilter={customer:'',service:'',site:'',vehicle:'',driver:'',from:'',to:'',query:'',cancelled:false};
export function filterRequests(requests:DispatchRequest[],shifts:DispatchShift[],filter:RequestFilter){
 const q=filter.query.trim().toLocaleLowerCase('ru-RU');return requests.filter(r=>
  (filter.cancelled||!r.cancelled_at)&&(!filter.customer||r.customer_id===filter.customer)&&(!filter.site||r.site_id===filter.site)&&(!filter.service||r.payload.service_name===filter.service)&&(!filter.from||r.date_to>=filter.from)&&(!filter.to||r.date_from<=filter.to)&&(!q||dispatchSourceNumber(filter.query)===r.number||['З'+r.number,r.number,r.payload.loading_address,r.payload.unloading_address,r.payload.site_name].join(' ').toLocaleLowerCase('ru-RU').includes(q))&&
  ((!filter.vehicle&&!filter.driver)||shifts.some(s=>s.request_id===r.id&&(filter.cancelled||s.status!=='cancelled')&&(!filter.vehicle||s.vehicle_id===filter.vehicle)&&(!filter.driver||(filter.driver.startsWith('name:')?s.driver_name===filter.driver.slice(5):s.driver_id===filter.driver))&&(!filter.from||s.shift_date>=filter.from)&&(!filter.to||s.shift_date<=filter.to)))
 );
}
