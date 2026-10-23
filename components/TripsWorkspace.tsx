'use client';
import {Fragment,useEffect,useRef,useState,type FormEvent} from 'react';
import {Plus,Search,RefreshCw,Download,Pencil,Trash2,Truck,Lock} from 'lucide-react';
import {db} from '../lib/supabase';
import type {AccountingDocument} from '../lib/accounting';
import {Modal} from './Modal';
import {TripDocuments,sendTripToDrive,type TripFile,type DriveExport} from './TripDocuments';
import {blankTripFilter,tripVehicleChoices,filterTrips,toggleVisibleSelection,tripPeriod,volumeTotals,csvCell,type TripFilter,type TripRow} from '../lib/trips';
type Customer={id:string;name:string};
type Site={id:string;customer_id:string;name:string;loading_address:string;unloading_address:string;route_km:string|null;service_name:string|null;unit:string|null;unit_price:number|null;contract_number:string|null};
type Vehicle={id:string;plate:string;brand:string|null;model:string|null;carrier_id:string|null;is_subcontractor_vehicle:boolean;assigned_driver_id:string|null;archived_at:string|null};
type Driver={id:string;full_name:string;carrier_id:string|null;job_status:string;archived_at:string|null};
type Carrier={id:string;name:string;is_blocked:boolean};
type Workspace={accounting_documents?:AccountingDocument[];trips:TripRow[];customers:Customer[];sites:Site[];vehicles:Vehicle[];drivers:Driver[];carriers:Carrier[];files:TripFile[];exports:DriveExport[]};
const empty:Workspace={trips:[],customers:[],sites:[],vehicles:[],drivers:[],carriers:[],files:[],exports:[]};
const statuses:Record<string,string>={assigned:'Запланирован',sent:'В работе',delivered:'Выполнен',cancelled:'Отменён'};
const money=(n:number)=>new Intl.NumberFormat('ru-RU',{style:'currency',currency:'RUB'}).format(n||0);
const today=()=>tripPeriod('today').from;
export function TripsWorkspace(){
 const [data,setData]=useState<Workspace>(empty),[loading,setLoading]=useState(true),[busy,setBusy]=useState(false),[error,setError]=useState(''),[notice,setNotice]=useState('');
 const [draft,setDraft]=useState<TripFilter>({...blankTripFilter}),[applied,setApplied]=useState<TripFilter>({...blankTripFilter}),[period,setPeriod]=useState('all'),[selected,setSelected]=useState<string[]>([]);
 const [modal,setModal]=useState<'edit'|'delete'|null>(null),[form,setForm]=useState<Record<string,string>>({}),[expectedVersion,setExpectedVersion]=useState<string|null>(null);
 const selectAll=useRef<HTMLInputElement>(null),sending=useRef(false);
 async function reload(){
  if(!db){setError('Рабочая база не подключена');setLoading(false);return}
  setLoading(true);
  try{const [workspace,files,exports]=await Promise.all([db.rpc('crm_read_trip_workspace'),db.from('crm_trip_files').select('*').order('created_at'),db.from('crm_drive_exports').select('*')]);const {data:result,error:failure}=workspace;if(failure||files.error||exports.error)throw Error((failure||files.error||exports.error)!.message);if(!result||!Array.isArray(result.trips)||!Array.isArray(result.customers))throw Error('Список рейсов получен в неверном формате');setData({...result,files:files.data||[],exports:exports.data||[]} as Workspace);setSelected(ids=>ids.filter(id=>result.trips.some((t:TripRow)=>t.id===id)));setError('')}
  catch(e){setError((e as Error).message||'Не удалось загрузить рейсы')}finally{setLoading(false)}
 }
 useEffect(()=>{void reload();const timer=setInterval(()=>void reload(),60000);return ()=>clearInterval(timer)},[]);
 useEffect(()=>{const pending=data.exports.filter(e=>e.state==='pending'||e.state==='awaiting_connection');if(!pending.length||sending.current)return;sending.current=true;void(async()=>{let attempted=false;try{const readiness=await fetch('/api/trip-drive',{cache:'no-store'}).then(r=>r.json());for(const e of pending.filter(e=>e.state==='pending'||readiness.configured)){attempted=true;await sendTripToDrive(e.trip_id)}}catch{}finally{sending.current=false;if(attempted)await reload()}})()},[data.exports]);
 const vehicleNames=Object.fromEntries(data.vehicles.map(v=>[v.id,v.plate]));
 const rows=filterTrips(data.trips,applied,vehicleNames),visibleIds=rows.map(t=>t.id),selectedRows=data.trips.filter(t=>selected.includes(t.id));
 const allChecked=rows.length>0&&rows.every(t=>selected.includes(t.id)),someChecked=rows.some(t=>selected.includes(t.id));
 useEffect(()=>{if(selectAll.current)selectAll.current.indeterminate=someChecked&&!allChecked},[someChecked,allChecked]);
 const chosenVehicle=data.vehicles.find(v=>v.id===form.vehicle_id);
 const external=form.vehicle_source==='contractor';
 const selectedCarrier=chosenVehicle?.carrier_id||(external?form.carrier_id:'');
 const currentSites=data.sites.filter(s=>s.customer_id===form.customer_id);
 const filterSites=data.sites.filter(s=>!draft.customer||s.customer_id===draft.customer);
 const volume=volumeTotals(rows);
 const vehicleChoices=tripVehicleChoices(data.vehicles,form.vehicle_source||'own',selectedCarrier||'',form.vehicle_id);
 function chooseSource(source:string){setForm(p=>({...p,vehicle_source:source,vehicle_id:'',driver_id:'',carrier_id:''}))}
 function chooseCarrier(carrier:string){setForm(p=>({...p,carrier_id:carrier,vehicle_id:'',driver_id:''}))}
 function set(key:string,value:string){setForm(p=>({...p,[key]:value}))}
 function newTrip(){
  setExpectedVersion(null);setError('');setNotice('');
  setForm({id:crypto.randomUUID(),trip_number:'',trip_date:today(),customer_id:applied.customer,site_id:'',vehicle_id:'',driver_id:'',carrier_id:'',vehicle_source:'own',loading_address:'',unloading_address:'',volume:'',unit:'м³',unit_price:'0',service_name:'',status:'assigned'});
  setModal('edit');
 }
 function editTrip(t:TripRow){
  if(t.locked){setError('Рейс включён в счёт или по нему уже есть выплаты/удержания. Для изменения нужна бухгалтерская корректировка.');return}
  setExpectedVersion(t.modified_at);setError('');setNotice('');
  const v=data.vehicles.find(v=>v.id===t.vehicle_id);
  setForm({...Object.fromEntries(Object.entries(t).map(([k,v])=>[k,v===null?'':String(v)])),vehicle_source:t.carrier_id||v?.carrier_id||v?.is_subcontractor_vehicle?'contractor':'own'});setModal('edit');
 }
 function chooseSite(id:string){
  const s=data.sites.find(s=>s.id===id);setForm(p=>({...p,site_id:id,loading_address:s?.loading_address||'',unloading_address:s?.unloading_address||'',service_name:s?.service_name||'',unit:s?.unit||'м³',unit_price:String(s?.unit_price||0)}));
 }
 function chooseVehicle(id:string){
  const v=vehicleChoices.find(v=>v.id===id),carrier=v?.carrier_id||(external?form.carrier_id:'')||'';
  if(id&&!v)return;
  const prior=data.drivers.find(d=>d.id===form.driver_id),assigned=data.drivers.find(d=>d.id===v?.assigned_driver_id&&!d.archived_at);
  setForm(p=>({...p,vehicle_id:id,carrier_id:carrier,driver_id:assigned&&assigned.carrier_id===v?.carrier_id?assigned.id:prior&&(prior.carrier_id||'')===carrier?prior.id:''}));
 }
 async function save(e:FormEvent){
  e.preventDefault();if(busy||!db)return;setBusy(true);setError('');
  try{
   const volume=Number(form.volume),price=Number(form.unit_price);
   if(form.volume===''||!Number.isFinite(volume)||volume<0||!Number.isFinite(price)||price<0)throw Error('Проверьте объём и цену');
   if(!vehicleChoices.some(v=>v.id===form.vehicle_id))throw Error('Выберите машину для выбранного исполнителя');
   if(external&&!selectedCarrier)throw Error('Выберите контрагента');
   const result=await db.rpc('crm_save_trip',{p_trip:{...form,volume,unit_price:price},p_expected_modified_at:expectedVersion});
   if(result.error)throw Error(result.error.message);
   setModal(null);setSelected([]);await reload();setNotice(expectedVersion?'Рейс изменён':'Рейс создан');
  }catch(e){setError((e as Error).message||'Не удалось сохранить рейс')}finally{setBusy(false)}
 }
 async function changeStatus(trip:TripRow,status:string){
  if(!db||busy||status===trip.status)return;setBusy(true);setError('');setNotice('');
  try{
   const r=await db.rpc('crm_save_trip',{p_trip:{...trip,status},p_expected_modified_at:trip.modified_at});
   if(r.error)throw Error(r.error.message);
   await reload();setNotice('Рейс '+trip.trip_number+': '+statuses[status]);
  }catch(e){setError((e as Error).message||'Не удалось изменить статус рейса')}finally{setBusy(false)}
 }
 async function remove(){
  if(!db||busy)return;setBusy(true);setError('');
  try{
   const result=await db.rpc('crm_delete_trips',{p_ids:selectedRows.map(t=>t.id),p_versions:Object.fromEntries(selectedRows.map(t=>[t.id,t.modified_at]))});
   if(result.error)throw Error(result.error.message);
   setModal(null);setSelected([]);await reload();setNotice('Удалено рейсов: '+result.data);
  }catch(e){setError((e as Error).message||'Не удалось удалить рейсы')}finally{setBusy(false)}
 }
 function exportCSV(){
  const exporting=selectedRows.length?selectedRows:rows;
  const header=['Номер рейса','Дата','Адрес погрузки','Адрес выгрузки','Госномер','Исполнитель','Объём','Ед.','Заказчик','Объект','Водитель','Услуга','Цена','Сумма','Статус'];
  const lines=exporting.map(t=>{const v=data.vehicles.find(v=>v.id===t.vehicle_id);return [t.trip_number,t.trip_date,t.loading_address,t.unloading_address,v?.plate,t.carrier_id?data.carriers.find(c=>c.id===t.carrier_id)?.name:'Своя техника',t.volume,t.unit,data.customers.find(c=>c.id===t.customer_id)?.name,data.sites.find(s=>s.id===t.site_id)?.name,data.drivers.find(d=>d.id===t.driver_id)?.full_name,t.service_name,t.unit_price,Number(t.volume||0)*Number(t.unit_price||0),statuses[t.status]||t.status]});
  const content='\ufeff'+[header,...lines].map(row=>row.map(csvCell).join(';')).join('\r\n');
  const url=URL.createObjectURL(new Blob([content],{type:'text/csv;charset=utf-8'})),link=document.createElement('a');link.href=url;link.download='Рейсы-'+today()+'.csv';link.click();setTimeout(()=>URL.revokeObjectURL(url),1000);
 }
 const input=(key:string,label:string,type='text',required=false)=><label className="field" key={key}>{label}{required?' *':''}<input type={type} required={required} value={form[key]||''} min={type==='number'?0:undefined} step={type==='number'?'0.001':undefined} placeholder={key==='trip_number'?'Автоматически: 1–1000':undefined} onChange={e=>set(key,e.target.value)}/></label>;
 return <section className="trips-workspace">
  <div className="page-heading"><div><span className="eyebrow">Операционная таблица</span><h1>Рейсы <span className="count-badge">{rows.length}</span></h1><p>Погрузка, выгрузка, техника и объёмы — в одной таблице.</p></div><div className="trip-heading-actions"><button className="button secondary" disabled={loading||!rows.length} onClick={exportCSV}><Download size={16}/>Выгрузить CSV</button><button className="button" onClick={newTrip}><Plus size={18}/>Добавить рейс</button></div></div>
  {rows.some(t=>!data.files.some(f=>f.trip_id===t.id))&&<div className="trip-alert" role="alert">Нет документов от водителя по рейсам: {rows.filter(t=>!data.files.some(f=>f.trip_id===t.id)).length}. Загрузите файлы в строке под рейсом.</div>}
  {error&&!modal&&<div className="trip-alert" role="alert">{error}<button className="text-button" onClick={()=>void reload()}>Обновить список</button></div>}{notice&&<p className="trip-success" role="status">{notice}</p>}
  <form className="panel trip-filter" onSubmit={e=>{e.preventDefault();if(draft.from&&draft.to&&draft.from>draft.to){setError('Дата начала периода позже даты окончания');return}setApplied({...draft});setSelected([]);setError('')}}>
   <label className="field">Период<select value={period} onChange={e=>{setPeriod(e.target.value);if(e.target.value!=='custom')setDraft(p=>({...p,...tripPeriod(e.target.value)}))}}><option value="all">Все даты</option><option value="today">Сегодня</option><option value="week">Последние 7 дней</option><option value="month">Текущий месяц</option><option value="custom">Свой период</option></select></label>
   <label className="field">С даты<input type="date" value={draft.from} onChange={e=>{setPeriod('custom');setDraft(p=>({...p,from:e.target.value}))}}/></label>
   <label className="field">По дату<input type="date" value={draft.to} onChange={e=>{setPeriod('custom');setDraft(p=>({...p,to:e.target.value}))}}/></label>
   <label className="field">Заказчик<select value={draft.customer} onChange={e=>setDraft(p=>({...p,customer:e.target.value,site:''}))}><option value="">Все заказчики</option>{data.customers.map(c=><option key={c.id} value={c.id}>{c.name}</option>)}</select></label>
   <label className="field">Объект<select value={draft.site} onChange={e=>setDraft(p=>({...p,site:e.target.value}))}><option value="">Все объекты</option>{filterSites.map(s=><option key={s.id} value={s.id}>{s.name}</option>)}</select></label>
   <div className="trip-filter-buttons"><button className="button">Применить</button><button type="button" className="button secondary" onClick={()=>{setPeriod('all');setDraft({...blankTripFilter});setApplied({...blankTripFilter});setSelected([])}}>Сбросить</button></div>
   <label className="search-box trip-search"><Search size={16}/><input aria-label="Найти рейс" placeholder="Номер рейса, госномер или адрес" value={draft.search} onChange={e=>setDraft(p=>({...p,search:e.target.value}))}/></label>
  </form>
  <div className="trip-table-toolbar"><label className="trip-select-all"><input type="checkbox" checked={allChecked} disabled={!rows.length||busy} onChange={e=>setSelected(p=>toggleVisibleSelection(p,visibleIds,e.target.checked))}/>Выбрать все найденные</label><span className="trip-selection-count">Выбрано: {selectedRows.length}</span><div className="trip-toolbar-actions"><button className="button secondary" disabled={selectedRows.length!==1||busy||selectedRows[0]?.locked} onClick={()=>editTrip(selectedRows[0])}><Pencil size={15}/>Редактировать</button><button className="button secondary trip-delete" disabled={!selectedRows.length||busy} onClick={()=>{setError('');setModal('delete')}}><Trash2 size={15}/>Удалить выбранные</button><button className="icon-button" disabled={loading||busy} onClick={()=>void reload()} aria-label="Обновить рейсы"><RefreshCw size={17} className={loading?'spin':''}/></button></div></div>
  <div className="trip-sheet" aria-label="Таблица рейсов"><table>
   <colgroup><col style={{width:46}}/><col style={{width:150}}/><col style={{width:115}}/><col style={{width:230}}/><col style={{width:230}}/><col style={{width:185}}/><col style={{width:110}}/><col style={{width:210}}/><col style={{width:200}}/><col style={{width:210}}/><col style={{width:190}}/><col style={{width:130}}/><col style={{width:140}}/><col style={{width:140}}/><col style={{width:145}}/></colgroup>
   <thead><tr><th className="trip-sticky-check"><input ref={selectAll} type="checkbox" aria-label="Выбрать все рейсы" checked={allChecked} disabled={!rows.length||busy} onChange={e=>setSelected(p=>toggleVisibleSelection(p,visibleIds,e.target.checked))}/></th><th className="trip-sticky-number">Номер рейса</th><th>Дата</th><th>Адрес погрузки</th><th>Адрес выгрузки</th><th>Госномер / техника</th><th>Объём</th><th>Заказчик</th><th>Объект</th><th>Водитель</th><th>Услуга</th><th>Цена, ₽</th><th>Сумма, ₽</th><th>Статус</th><th>Действия</th></tr></thead>
   <tbody>{rows.map((t,index)=>{const v=data.vehicles.find(v=>v.id===t.vehicle_id),contractor=Boolean(t.carrier_id||v?.carrier_id||v?.is_subcontractor_vehicle),carrierName=data.carriers.find(c=>c.id===(t.carrier_id||v?.carrier_id))?.name;return <Fragment key={t.id}><tr className={selected.includes(t.id)?'trip-selected':''} onDoubleClick={()=>editTrip(t)}>
    <td className="trip-sticky-check"><input type="checkbox" checked={selected.includes(t.id)} disabled={busy} aria-label={'Выбрать рейс '+t.trip_number} onChange={e=>setSelected(p=>e.target.checked?Array.from(new Set([...p,t.id])):p.filter(id=>id!==t.id))}/></td>
    <td className="trip-sticky-number"><strong>{t.trip_number}</strong>{t.locked&&<small className="trip-locked"><Lock size={11}/>Счёт / выплаты</small>}</td><td>{t.trip_date||'—'}</td><td>{t.loading_address||'—'}</td><td>{t.unloading_address||'—'}</td>
    <td><span className={'trip-plate '+(contractor?'contractor':'owned')}>{v?.plate||'Не указано'}</span><small>{contractor?'Контрагент':'Своя техника'}</small>{contractor&&carrierName&&<small>{carrierName}</small>}</td>
    <td><strong>{Number(t.volume||0).toLocaleString('ru-RU',{maximumFractionDigits:3})}</strong><small>{t.unit||'м³'}</small></td>
    <td>{data.customers.find(c=>c.id===t.customer_id)?.name||'—'}</td><td>{data.sites.find(s=>s.id===t.site_id)?.name||'—'}</td><td>{data.drivers.find(d=>d.id===t.driver_id)?.full_name||'—'}</td><td>{t.service_name||'—'}</td><td>{money(Number(t.unit_price||0))}</td><td><strong>{money(Number(t.unit_price||0)*Number(t.volume||0))}</strong></td><td><span className={'trip-status '+(t.status==='delivered'&&(!t.documents_confirmed||!data.files.some(f=>f.trip_id===t.id))?'sent':t.status)}>{t.status==='delivered'&&!t.documents_confirmed?'Выполнен · нужны документы':statuses[t.status]||t.status}</span><select className="trip-status-select" aria-label={'Изменить статус рейса '+t.trip_number} value={t.status} disabled={busy||t.locked} onChange={e=>void changeStatus(t,e.target.value)} onDoubleClick={e=>e.stopPropagation()}>{Object.entries(statuses).map(([value,label])=><option key={value} value={value}>{label}</option>)}</select></td>
    <td><div className="trip-row-actions"><button className="icon-button" aria-label={'Редактировать '+t.trip_number} disabled={busy||t.locked} onClick={()=>editTrip(t)}><Pencil size={15}/></button><button className="icon-button trip-delete" aria-label={'Удалить '+t.trip_number} disabled={busy} onClick={()=>{setSelected([t.id]);setError('');setModal('delete')}}><Trash2 size={15}/></button></div></td>
   </tr><tr className="trip-documents-row"><td colSpan={15}><TripDocuments accountingDocuments={data.accounting_documents?.filter(d=>d.trip_ids?.includes(t.id))} tripId={t.id} files={data.files.filter(f=>f.trip_id===t.id)} confirmed={Boolean(t.documents_confirmed)} completed={t.status==='delivered'} archive={data.exports.find(e=>e.trip_id===t.id)} onChanged={reload}/></td></tr></Fragment>})}</tbody>
  </table>{loading&&<div className="trip-table-empty">Загрузка рейсов…</div>}{!loading&&!rows.length&&<div className="trip-table-empty"><Truck size={30}/><strong>Рейсов пока нет</strong><p>Измените фильтр или добавьте первый рейс.</p><button className="button" onClick={newTrip}>Добавить рейс</button></div>}</div>
  <footer className="trip-sheet-footer"><span>Рейсов: <strong>{rows.length}</strong></span><span>Объём: <strong>{volume.map(v=>v.total.toLocaleString('ru-RU')+' '+v.unit).join(' · ')||'—'}</strong></span><span>Сумма: <strong>{money(rows.reduce((s,t)=>s+Number(t.volume||0)*Number(t.unit_price||0),0))}</strong></span><span className="trip-footer-hint">Прокрутите таблицу вправо для остальных столбцов</span></footer>
  {modal==='edit'&&<Modal title={expectedVersion?'Редактирование рейса':'Новый рейс'} busy={busy} onClose={()=>{if(!busy)setModal(null)}}><form onSubmit={save}><fieldset className="form-body" disabled={busy}><div className="form-grid">
   {input('trip_number','Номер рейса')}{input('trip_date','Дата','date',true)}
   <label className="field">Заказчик *<select required value={form.customer_id||''} onChange={e=>setForm(p=>({...p,customer_id:e.target.value,site_id:'',loading_address:'',unloading_address:'',service_name:'',unit_price:'0'}))}><option value="">Выберите заказчика</option>{data.customers.map(c=><option key={c.id} value={c.id}>{c.name}</option>)}</select></label>
   <label className="field">Объект *<select required value={form.site_id||''} disabled={!form.customer_id} onChange={e=>chooseSite(e.target.value)}><option value="">Выберите объект</option>{currentSites.map(s=><option key={s.id} value={s.id}>{s.name}</option>)}</select></label>
   {input('loading_address','Адрес погрузки','text',true)}{input('unloading_address','Адрес выгрузки','text',true)}
   <fieldset className="trip-source-switch"><legend>Чья техника *</legend><div className="trip-source-options">{[['own','Своя техника'],['contractor','Техника контрагента']].map(([value,label])=><label key={value} className={'trip-source-option '+((form.vehicle_source||'own')===value?'chosen':'')}><input type="radio" name="trip-vehicle-source" value={value} checked={(form.vehicle_source||'own')===value} onChange={()=>chooseSource(value)}/><span>{label}</span></label>)}</div></fieldset>
   {external&&<label className="field wide">Контрагент *<select required value={selectedCarrier||''} onChange={e=>chooseCarrier(e.target.value)}><option value="">Выберите исполнителя</option>{data.carriers.filter(c=>!c.is_blocked||c.id===selectedCarrier).map(c=><option key={c.id} value={c.id}>{c.name}{c.is_blocked?' · заблокирован':''}</option>)}</select>{!data.carriers.some(c=>!c.is_blocked)&&<small>Добавьте исполнителя в разделе «Контрагенты».</small>}</label>}
   <label className={'field '+(external?'trip-external-field':'')}>Госномер *<select required disabled={external&&!selectedCarrier} value={form.vehicle_id||''} onChange={e=>chooseVehicle(e.target.value)}><option value="">{external&&!selectedCarrier?'Сначала выберите контрагента':vehicleChoices.length?'Выберите машину':'Нет добавленной техники'}</option>{vehicleChoices.map(v=><option key={v.id} value={v.id}>{v.plate} · {v.brand} {v.model}{v.archived_at?' · архив':''}</option>)}</select>{(!external||selectedCarrier)&&!vehicleChoices.length&&<small className="trip-vehicle-empty">{external?'Добавьте технику в карточку выбранного контрагента.':'Добавьте собственную машину в разделе «ТС и водители».'}</small>}{external&&<small className="trip-external-note">Техника контрагента</small>}</label>
   <label className="field">Водитель<select value={form.driver_id||''} disabled={external&&!selectedCarrier} onChange={e=>set('driver_id',e.target.value)}><option value="">Не назначен</option>{data.drivers.filter(d=>(!external||Boolean(selectedCarrier))&&(d.carrier_id||'')===(selectedCarrier||'')&&(!d.archived_at||d.id===form.driver_id)).map(d=><option key={d.id} value={d.id}>{d.full_name}</option>)}</select></label>
   {input('volume','Объём','number',true)}<label className="field">Единица<select value={form.unit||'м³'} onChange={e=>set('unit',e.target.value)}>{Array.from(new Set(['м³','т','рейс','час','смена','км','шт.',form.unit].filter(Boolean))).map(u=><option key={u}>{u}</option>)}</select></label>
   {input('service_name','Услуга')}{input('unit_price','Цена за единицу, ₽','number')}
   <label className="field">Статус<select value={form.status||'assigned'} onChange={e=>set('status',e.target.value)}>{Object.entries(statuses).map(([k,v])=><option key={k} value={k}>{v}</option>)}</select></label>
   <div className="trip-form-total"><small>Сумма рейса</small><strong>{money(Number(form.volume||0)*Number(form.unit_price||0))}</strong></div>
  </div><p className="hint">Адреса, услуга и цена подставляются из объекта. Для выполненного рейса своей техники нужны водитель и настроенное плечо маршрута — по нему фиксируется зарплата.</p>{error&&<div className="form-error" role="alert">{error}</div>}</fieldset><footer className="modal-actions"><span>* Обязательные поля</span><button type="button" className="button secondary" disabled={busy} onClick={()=>setModal(null)}>Отмена</button><button className="button" disabled={busy}>{busy?'Сохранение…':'Сохранить рейс'}</button></footer></form></Modal>}
  {modal==='delete'&&<Modal title={'Удаление рейсов: '+selectedRows.length} busy={busy} onClose={()=>{if(!busy)setModal(null)}}><div className="form-body"><p className="trip-delete-description">Из рабочего списка будут убраны выбранные рейсы. История сохраняется в базе. Если хотя бы один рейс связан со счётом, выплатой или удержанием, выборка не будет удалена.</p><ul className="trip-delete-list">{selectedRows.slice(0,12).map(t=><li key={t.id}>{t.trip_number} · {t.trip_date}</li>)}{selectedRows.length>12&&<li>И ещё {selectedRows.length-12} рейсов</li>}</ul>{error&&<div className="form-error" role="alert">{error}</div>}</div><footer className="modal-actions"><span>Выбрано {selectedRows.length}</span><button className="button secondary" disabled={busy} onClick={()=>setModal(null)}>Отмена</button><button className="button trip-danger-button" disabled={busy||!selectedRows.length} onClick={()=>void remove()}>{busy?'Удаление…':'Удалить выбранные'}</button></footer></Modal>}
 </section>
}

