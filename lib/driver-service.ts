export type Vehicle={id:string;plate:string;brand?:string;model?:string;odometer_km:number;assigned_driver_id:string;next_service_km:number|null;next_oil_km:number|null;reminder_before_km:number};
export type Driver={id:string;full_name:string;phone?:string};
export type Partner={id:string;name:string;address:string;phone:string;contact:string;working_hours:string;time_zone:string;contract_number:string;contract_from:string;contract_until:string|null;work_kinds:string[];notes:string;archived:boolean;modified_at:string};
export type ServiceRequest={id:string;driver_id:string;vehicle_id:string;partner_id:string;kind:string;status:string;requested_date:string|null;scheduled_at:string|null;reported_odometer:number;driver_note:string;dispatcher_note:string;partner_snapshot:Partner;modified_at:string};
export type Note={id:string;driver_id:string;title:string;has_credentials:boolean;modified_at:string};
export type NoteBody=Note&{login:string;password:string;body:string};
export type Shift={id:string;driver_id:string;vehicle_id:string;shift_date:string;odometer:number;technical_note:string;supplies_note:string;comment:string;status:string;supplies_status:string;dispatcher_note:string;modified_at:string};
export type ShiftFile={id:string;report_id:string;trip_id:string|null;kind:string;file_name:string};
export type Duty={id:string;plate?:string;driver_id:string;vehicle_id:string;started_at:string;ended_at:string|null;start_odometer:number;end_odometer:number|null};
export type Fine={id:string;plate?:string;driver_id:string|null;vehicle_id:string;violation_at:string;location:string;reason:string;notice_number:string;amount:number;assignment:string;linked_fine_id:string|null;deducted:number;acknowledged_at:string|null;dispute:string};
export type Account={driver_id:string;login:string;blocked:boolean;must_change_password:boolean};
export type DriverTrip={id:string;trip_number:string;trip_date:string;vehicle_id:string;object:string;service_name:string;status:string;modified_at:string;stage:string;plate:string;customer:string;loading_address:string;unloading_address:string;route_km:number|null;volume:number;unit:string;documents_confirmed:boolean};
export type DriverData={driver?:Driver;drivers:Driver[];vehicles:Vehicle[];partners:Partner[];requests:ServiceRequest[];accounts:Account[];notes:Note[];shifts:Shift[];shift_files:ShiftFile[];duties:Duty[];fines:Fine[];driver_trips:DriverTrip[]};
export const emptyDriverData=():DriverData=>({drivers:[],vehicles:[],partners:[],requests:[],accounts:[],notes:[],shifts:[],shift_files:[],duties:[],fines:[],driver_trips:[]});
export const serviceKinds:Record<string,string>={service:'Техническое обслуживание',oil:'Замена масла',repair:'Ремонт',tyres:'Шиномонтаж'};
export const statusLabels:Record<string,string>={requested:'Ожидает диспетчера',confirmed:'Запись подтверждена',arrived:'Машина в сервисе',completed:'Выполнено',rejected:'Возвращено',cancelled:'Отменено',draft:'Черновик',submitted:'На проверке',reviewed:'Принято',open:'Нужно закупить',in_progress:'В работе',done:'Выдано'};
export function dateTime(value:string|null,zone?:string){return value?new Date(value).toLocaleString('ru-RU',{timeZone:zone||undefined,dateStyle:'short',timeStyle:'short'}):'—';}
export function phoneLink(value:string){const normalized=value.replace(/[^+0-9]/g,'');return /^\+?\d{6,15}$/.test(normalized)?'tel:'+normalized:undefined;}
// Driver photos are decoded and re-encoded to JPEG before sending. No SVG or original metadata.
export async function prepareDriverPhoto(file:File):Promise<string>{
 if(!file.type.startsWith('image/')||file.size>25*1024*1024)throw Error('Выберите фото до 25 МБ');
 const bitmap=await createImageBitmap(file);try{
  const scale=Math.min(1,1600/Math.max(bitmap.width,bitmap.height));
  const canvas=document.createElement('canvas');canvas.width=Math.round(bitmap.width*scale);canvas.height=Math.round(bitmap.height*scale);
  const ctx=canvas.getContext('2d');if(!ctx)throw Error('Не удалось обработать фотографию');ctx.drawImage(bitmap,0,0,canvas.width,canvas.height);
  const data=canvas.toDataURL('image/jpeg',.8).split(',')[1];if(data.length>2796208)throw Error('Фото превышает 2 МБ после сжатия');return data;
 }finally{bitmap.close();}
}

export const tripStages:Record<string,{label:string;next:string|null;action:string}>={
 '':{label:'Назначен',next:'accepted',action:'Принять рейс'},accepted:{label:'Принят',next:'loading',action:'На погрузке'},loading:{label:'На погрузке',next:'on_route',action:'Погружен · выехал'},on_route:{label:'В пути',next:'unloading',action:'На выгрузке'},unloading:{label:'На выгрузке',next:'completed',action:'Завершить рейс'},completed:{label:'Выполнен',next:null,action:''}};
