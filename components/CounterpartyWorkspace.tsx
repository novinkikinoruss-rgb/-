'use client';
import {useEffect,useMemo,useState,type FormEvent} from 'react';
import {Building2,Truck,Users,Plus,Search,Check,FileText,Wallet,RefreshCw,Download} from 'lucide-react';
import {db} from '../lib/supabase';
import {Modal} from './Modal';
type Carrier={id:string;name:string;inn:string|null;kpp:string|null;ogrn:string|null;phone:string|null;email:string|null;legal_address:string|null};
type Vehicle={id:string;carrier_id:string|null;plate:string;brand:string|null;model:string|null;vehicle_type:string|null;phone:string|null;status:string};
type Driver={id:string;carrier_id:string|null;full_name:string;phone:string|null;license_number:string|null};
type Trip={id:string;carrier_id:string|null;trip_number:string;trip_date:string|null;service_name:string|null;volume:number|null;unit_price:number|null;site_id:string|null;vehicle_id:string|null;driver_id:string|null;status:string};
type Site={id:string;name:string};
type Doc={id:string;trip_id:string|null;doc_type:string};
type Invoice={id:string;counterparty_id:string;invoice_number:string;invoice_date:string;due_date:string|null;amount:number;paid_amount:number;status:string};
type Contract={id:string;counterparty_id:string;number:string;kind:string;date:string;end_date:string|null;notes:string};
type Service={id:string;name:string;unit:string;price:string};
type Specification={id:string;contract_id:string;number:string;date:string;services:Service[]};
type Kind='carrier'|'contract'|'specification'|'vehicle'|'driver'|'invoice'|'payment'|'status';
type Tab='Обзор'|'Реквизиты'|'Договоры'|'Спецификации'|'Техника и водители'|'Документы';
type Filter={from:string;to:string;site:string;service:string};
const blankFilter:Filter={from:'',to:'',site:'',service:''};
const today=()=>new Date().toLocaleDateString('en-CA');
const money=(v:number|string)=>new Intl.NumberFormat('ru-RU',{style:'currency',currency:'RUB'}).format(Number(v)||0);
const cents=(v:number|string)=>Math.round(Number(String(v).replace(',','.'))*100);
const documents=['Накладная','Талон','УПД','Реестр'];
const titles:Record<Kind,string>={carrier:'Карточка контрагента',contract:'Новый договор',specification:'Новая спецификация',vehicle:'Техника исполнителя',driver:'Водитель исполнителя',invoice:'Счёт исполнителя',payment:'Добавить оплату',status:'Статус счёта'};
function invoiceState(i:Invoice){if(cents(i.paid_amount)>=cents(i.amount))return 'Оплачен';if(i.due_date&&i.due_date<today())return 'Просрочен';if(cents(i.paid_amount)>0)return 'Частично оплачен';return i.status==='Оплачен'||i.status==='Частично оплачен'?'Ожидает оплаты':i.status;}
function tone(status:string){return status==='Оплачен'?'paid':status==='Просрочен'?'overdue':status==='Частично оплачен'?'partial':'pending';}
export function CounterpartyWorkspace(){
 const [carriers,setCarriers]=useState<Carrier[]>([]),[vehicles,setVehicles]=useState<Vehicle[]>([]),[drivers,setDrivers]=useState<Driver[]>([]),[trips,setTrips]=useState<Trip[]>([]),[sites,setSites]=useState<Site[]>([]),[docs,setDocs]=useState<Doc[]>([]),[invoices,setInvoices]=useState<Invoice[]>([]),[contracts,setContracts]=useState<Contract[]>([]),[specifications,setSpecifications]=useState<Specification[]>([]);
 const [selected,setSelected]=useState(''),[query,setQuery]=useState(''),[tab,setTab]=useState<Tab>('Обзор'),[loading,setLoading]=useState(true),[error,setError]=useState(''),[success,setSuccess]=useState(''),[busy,setBusy]=useState(false);
 const [modal,setModal]=useState<Kind|null>(null),[editing,setEditing]=useState(false),[form,setForm]=useState<Record<string,string>>({}),[services,setServices]=useState<Service[]>([]);
 const [draft,setDraft]=useState<Filter>(blankFilter),[applied,setApplied]=useState<Filter>(blankFilter),[expanded,setExpanded]=useState(false);
 const current=carriers.find(c=>c.id===selected);
 const cpContracts=contracts.filter(c=>c.counterparty_id===selected);
 const contractIds=new Set(cpContracts.map(c=>c.id));
 const cpSpecs=specifications.filter(s=>contractIds.has(s.contract_id));
 const cpVehicles=vehicles.filter(v=>v.carrier_id===selected),cpDrivers=drivers.filter(d=>d.carrier_id===selected),cpInvoices=invoices.filter(i=>i.counterparty_id===selected);
 const allTrips=trips.filter(t=>t.carrier_id===selected||cpVehicles.some(v=>v.id===t.vehicle_id));
 const filteredTrips=useMemo(()=>allTrips.filter(t=>(!applied.from||Boolean(t.trip_date&&t.trip_date>=applied.from))&&(!applied.to||Boolean(t.trip_date&&t.trip_date<=applied.to))&&(!applied.site||t.site_id===applied.site)&&(!applied.service||t.service_name===applied.service)),[allTrips,applied]);
 const billed=cpInvoices.reduce((s,i)=>s+cents(i.amount),0)/100,paid=cpInvoices.reduce((s,i)=>s+cents(i.paid_amount),0)/100;
 async function load(){
  if(!db){setError('Рабочая база не подключена');setLoading(false);return}
  setLoading(true);
  try{
   const results=await Promise.all([
    db.from('crm_carriers').select('id,name,inn,kpp,ogrn,phone,email,legal_address').order('created_at',{ascending:false}),
    db.from('crm_vehicles').select('id,carrier_id,plate,brand,model,vehicle_type,phone,status'),
    db.from('crm_drivers').select('id,carrier_id,full_name,phone,license_number'),
    db.from('crm_trips').select('id,carrier_id,trip_number,trip_date,service_name,volume,unit_price,site_id,driver_id,vehicle_id,status').is('deleted_at',null).order('trip_date',{ascending:false}),
    db.from('crm_sites').select('id,name').is('deleted_at',null),
    db.from('crm_trip_files').select('id,trip_id,doc_type'),
    db.from('crm_counterparty_invoices').select('id,counterparty_id,invoice_number,invoice_date,due_date,amount,paid_amount,status').is('deleted_at',null).order('invoice_date',{ascending:false}),
    db.from('crm_counterparty_contracts').select('id,counterparty_id,number,kind,date,end_date,notes').order('date',{ascending:false}),
    db.from('crm_counterparty_specifications').select('id,contract_id,number,date,services').order('date',{ascending:false})
   ]);
   const labels=['Контрагенты','Техника','Водители','Рейсы','Объекты','Документы','Счета','Договоры','Спецификации'];
   const setters=[setCarriers,setVehicles,setDrivers,setTrips,setSites,setDocs,setInvoices,setContracts,setSpecifications];
   const failures:string[]=[];
   results.forEach((r,index)=>{if(r.error)failures.push(labels[index]+': '+r.error.message);else (setters[index] as (rows:unknown[])=>void)(r.data||[])});
   if(failures.length)throw Error(failures.join('; '));
   setError('');
   setSelected(prev=>results[0].data?.some(c=>c.id===prev)?prev:results[0].data?.[0]?.id||'');
  }catch(e){setError((e as Error).message||'Не удалось загрузить данные')}finally{setLoading(false)}
 }
 useEffect(()=>{void load()},[]);
 useEffect(()=>{setDraft(blankFilter);setApplied(blankFilter);setExpanded(false)},[selected]);
 const set=(key:string,value:string)=>setForm(f=>({...f,[key]:value}));
 function open(kind:Kind,values:Record<string,string>={},edit=false){setError('');setSuccess('');setEditing(edit);setForm({date:today(),invoice_date:today(),...values});setServices([{id:crypto.randomUUID(),name:'',unit:'м³',price:''}]);setModal(kind)}
 async function save(event:FormEvent){
  event.preventDefault();if(busy||!db)return;setBusy(true);setError('');
  try{
   let result;
   if(modal==='carrier'){
    const payload={name:form.name?.trim(),inn:form.inn?.trim()||null,kpp:form.kpp||null,ogrn:form.ogrn||null,phone:form.phone||null,email:form.email||null,legal_address:form.legal_address||null};
    if(!payload.name)throw Error('Укажите название компании');
    if(editing&&!current)throw Error('Выберите контрагента');
    result=editing?await db.from('crm_carriers').update(payload).eq('id',selected).select().single():await db.from('crm_carriers').insert(payload).select().single();
    if(!result.error&&result.data?.id)setSelected(result.data.id);
   }else{
    if(!current)throw Error('Сначала создайте карточку контрагента');
    if(modal==='contract'){
     if(form.end_date&&form.end_date<form.date)throw Error('Проверьте срок действия договора');
     result=await db.from('crm_counterparty_contracts').insert({counterparty_id:selected,number:form.number?.trim(),kind:form.kind||'transport',date:form.date,end_date:form.end_date||null,notes:form.notes||''}).select().single();
    }
    if(modal==='specification'){
     const parent=cpContracts.find(c=>c.id===form.contract_id);
     if(!parent)throw Error('Выберите договор контрагента');
     if(form.date<parent.date||parent.end_date&&form.date>parent.end_date)throw Error('Дата спецификации должна входить в период договора');
     if(!services.length||services.length>100||services.some(s=>!s.name.trim()||!s.unit.trim()||!Number.isFinite(cents(s.price))||cents(s.price)<=0))throw Error('Заполните услуги, единицы измерения и положительные цены');
     result=await db.from('crm_counterparty_specifications').insert({contract_id:parent.id,number:form.number?.trim(),date:form.date,services:services.map(s=>({...s,name:s.name.trim(),price:String(cents(s.price)/100)}))}).select().single();
    }
    if(modal==='vehicle')result=await db.from('crm_vehicles').insert({carrier_id:selected,is_subcontractor_vehicle:true,plate:form.plate?.trim(),brand:form.brand||null,model:form.model||null,vehicle_type:form.vehicle_type||'Спецтехника',phone:form.phone||null,status:form.status||'available'}).select().single();
    if(modal==='driver')result=await db.from('crm_drivers').insert({carrier_id:selected,full_name:form.full_name?.trim(),phone:form.phone||null,license_number:form.license_number||null}).select().single();
    if(modal==='invoice'){
     if(!Number.isFinite(cents(form.amount))||cents(form.amount)<=0)throw Error('Укажите положительную сумму счёта');
     if(form.due_date&&form.due_date<form.invoice_date)throw Error('Срок оплаты не может быть раньше даты счёта');
     result=await db.from('crm_counterparty_invoices').insert({counterparty_id:selected,invoice_number:form.invoice_number?.trim(),invoice_date:form.invoice_date,due_date:form.due_date||null,amount:cents(form.amount)/100,paid_amount:0,status:'Ожидает оплаты'}).select().single();
    }
    if(modal==='payment'||modal==='status'){
     const invoice=cpInvoices.find(i=>i.id===form.invoice_id);if(!invoice)throw Error('Выберите счёт');
     if(modal==='payment'){
      const delta=cents(form.payment_amount),next=cents(invoice.paid_amount)+delta;
      if(!Number.isFinite(delta)||delta<=0||next>cents(invoice.amount))throw Error('Сумма оплаты должна быть больше нуля и не превышать задолженность');
      result=await db.from('crm_counterparty_invoices').update({paid_amount:next/100,status:next===cents(invoice.amount)?'Оплачен':'Частично оплачен'}).eq('id',invoice.id).eq('paid_amount',invoice.paid_amount).select().single();
     }else result=await db.from('crm_counterparty_invoices').update({status:form.status}).eq('id',invoice.id).select().single();
    }
   }
   if(!result)throw Error('Не удалось выполнить действие');
   if(result.error)throw Error(result.error.message||'Сохранение не выполнено');
   const kind=modal;setModal(null);setForm({});await load();setSuccess('Изменения сохранены');
   if(kind==='carrier')setTab('Обзор');if(kind==='contract')setTab('Спецификации');
  }catch(e){setError((e as Error).message||'Ошибка сохранения')}finally{setBusy(false)}
 }
 function hasDoc(trip:string,type:string){const aliases:Record<string,string[]>= {'Накладная':['наклад','ttn'],'Талон':['талон','ticket'],'УПД':['упд','upd'],'Реестр':['реестр','registry','register']};return docs.some(d=>d.trip_id===trip&&aliases[type].some(a=>d.doc_type.toLowerCase().includes(a)))}
 const field=(key:string,label:string,type='text',required=false)=><label className="field" key={key}>{label}{required?' *':''}<input type={type} required={required} value={form[key]||''} step={type==='number'?'0.01':undefined} min={type==='number'?'0.01':undefined} onChange={e=>set(key,e.target.value)}/></label>;
 const contractBlock=<section className="panel module-card"><div className="block-heading"><h3>Договоры</h3><button className="button compact" onClick={()=>open('contract')}><Plus size={15}/>Договор</button></div>{cpContracts.map(c=><article className="record" key={c.id}><span className="soft-icon"><FileText size={18}/></span><div><strong>{c.number}</strong><small>{c.kind==='transport'?'Транспортные услуги':'Поставка'} · {c.date}</small></div></article>)}{!cpContracts.length&&<p className="hint">После карточки создайте договор исполнителя.</p>}</section>;
 const specBlock=<section className="panel module-card"><div className="block-heading"><h3>Спецификации</h3><button className="button compact" disabled={!cpContracts.length} onClick={()=>open('specification',{contract_id:cpContracts[0]?.id||''})}><Plus size={15}/>Спецификация</button></div>{cpSpecs.map(s=><article className="spec-record" key={s.id}><div className="mini-heading"><strong>{s.number}</strong><small>{s.date} · {cpContracts.find(c=>c.id===s.contract_id)?.number}</small></div>{s.services.map(service=><div className="price-row" key={service.id}><span>{service.name}</span><small>{service.unit}</small><strong>{money(service.price)}</strong></div>)}</article>)}{!cpSpecs.length&&<p className="hint">{cpContracts.length?'Добавьте услуги и цены к договору.':'Сначала создайте договор.'}</p>}</section>;
 const fleetBlock=<div className="module-grid"><section className="panel module-card"><div className="block-heading"><h3>Техника контрагента</h3><button className="button compact" onClick={()=>open('vehicle')}><Plus size={15}/>Техника</button></div>{cpVehicles.map(v=><article className="record" key={v.id}><Truck size={20}/><div><strong>{v.vehicle_type} · {v.plate}</strong><small>{[v.brand,v.model,v.phone].filter(Boolean).join(' · ')||'Контакты не заполнены'}</small></div></article>)}{!cpVehicles.length&&<p className="hint">Вид спецтехники, госномер, телефон.</p>}</section><section className="panel module-card"><div className="block-heading"><h3>Водители исполнителя</h3><button className="button compact" onClick={()=>open('driver')}><Plus size={15}/>Водитель</button></div>{cpDrivers.map(d=><article className="record" key={d.id}><Users size={20}/><div><strong>{d.full_name}</strong><small>{d.phone||'Телефон не указан'} · Удостоверение {d.license_number||'—'}</small></div></article>)}{!cpDrivers.length&&<p className="hint">Добавьте водителей и их телефоны.</p>}</section></div>;
 return <div className="counterparty-v2">
  <div className="page-heading"><div><span className="eyebrow">Управление исполнителями</span><h1>Контрагенты <span className="count-badge">{carriers.length}</span></h1><p>Карточка → договор → спецификация → рейсы и взаиморасчёты</p></div><button className="button" onClick={()=>open('carrier')}><Plus size={18}/>Новый контрагент</button></div>
  {error&&!modal&&<div className="cp-alert" role="alert">{error}<button className="text-button" onClick={()=>void load()}>Повторить загрузку</button></div>}{success&&<p className="cp-success" role="status">{success}</p>}
  <div className="workspace-toolbar"><label className="search-box"><Search size={18}/><input aria-label="Поиск контрагента" placeholder="Компания, ИНН или телефон" value={query} onChange={e=>setQuery(e.target.value)}/></label><button className="icon-button" disabled={loading} onClick={()=>void load()} aria-label="Обновить контрагентов"><RefreshCw size={17} className={loading?'spin':''}/></button></div>
  <div className="customer-workspace"><aside className="customer-directory panel"><div className="block-heading"><h2>Исполнители</h2><span>{carriers.length}</span></div>{carriers.filter(c=>[c.name,c.inn,c.phone].join(' ').toLowerCase().includes(query.toLowerCase())).map(c=><button className={'customer-choice '+(selected===c.id?'chosen':'')} key={c.id} onClick={()=>{setSelected(c.id);setTab('Обзор')}}><span className="customer-letter">{c.name.slice(0,1)}</span><span><strong>{c.name}</strong><small>ИНН {c.inn||'—'}</small></span></button>)}{loading&&<p className="hint">Загрузка…</p>}{!loading&&!carriers.length&&<p className="hint">Создайте первую карточку исполнителя.</p>}</aside>
  <div className="customer-details">{!current?<section className="panel empty-company"><Building2 size={40}/><h2>Карточка исполнителя</h2><p>Создайте контрагента, затем добавьте договор и спецификацию с услугами и ценами.</p><button className="button" onClick={()=>open('carrier')}>Создать контрагента</button></section>:<>
   <div className="detail-title"><div><span className="eyebrow">Карточка исполнителя</span><h2>{current.name}</h2></div><button className="button secondary" onClick={()=>open('carrier',{name:current.name,inn:current.inn||'',kpp:current.kpp||'',ogrn:current.ogrn||'',phone:current.phone||'',email:current.email||'',legal_address:current.legal_address||''},true)}>Редактировать</button></div>
   <ol className="workflow-steps">{['Контрагент','Договор','Спецификация'].map((label,index)=><li className={index===0||index===1&&cpContracts.length||index===2&&cpSpecs.length?'complete':''} key={label}><span>{index===0||index===1&&cpContracts.length||index===2&&cpSpecs.length?<Check size={15}/>:index+1}</span><div><strong>{label}</strong><small>{index===0?'Создано':index===1?cpContracts.length+' договоров':cpSpecs.length+' спецификаций'}</small></div></li>)}</ol>
   <div className="customer-tabs" role="tablist">{(['Обзор','Реквизиты','Договоры','Спецификации','Техника и водители','Документы'] as Tab[]).map(t=><button role="tab" aria-selected={tab===t} className={tab===t?'selected':''} key={t} onClick={()=>setTab(t)}>{t}</button>)}</div>
   {(tab==='Обзор'||tab==='Реквизиты')&&<section className="panel requisites"><div className="company-heading"><span className="company-avatar"><Building2 size={25}/></span><div><h2>{current.name}</h2><p>Исполнитель транспортных услуг</p></div></div><dl className="requisite-grid">{[['ИНН',current.inn],['КПП',current.kpp],['ОГРН',current.ogrn],['Телефон',current.phone],['Email',current.email],['Юридический адрес',current.legal_address]].map(([label,value])=><div key={label}><dt>{label}</dt><dd>{value||'Не заполнено'}</dd></div>)}</dl></section>}
   {tab==='Обзор'?<><div className="module-grid">{contractBlock}{specBlock}</div>{fleetBlock}</>:tab==='Договоры'?contractBlock:tab==='Спецификации'?specBlock:tab==='Техника и водители'?fleetBlock:null}
   {tab==='Документы'&&<section className="panel"><h3>Документы по рейсам</h3><p className="hint">Статусы накладных, талонов, УПД и реестров отображаются в таблице ниже после применения фильтра.</p></section>}
   <section className="panel cp-trip-section"><div className="block-heading"><div><h3>Рейсы исполнителя</h3><p className="hint">Выберите объект, услугу и период, затем нажмите «Применить».</p></div></div>
    <form className="cp-filter" onSubmit={e=>{e.preventDefault();if(draft.from&&draft.to&&draft.from>draft.to){setError('Дата начала периода позже даты окончания');return}setApplied({...draft});setExpanded(true);setError('')}}>
     <label className="field">Объект<select value={draft.site} onChange={e=>setDraft(f=>({...f,site:e.target.value}))}><option value="">Все объекты</option>{sites.map(s=><option key={s.id} value={s.id}>{s.name}</option>)}</select></label>
     <label className="field">Услуга<select value={draft.service} onChange={e=>setDraft(f=>({...f,service:e.target.value}))}><option value="">Все услуги</option>{Array.from(new Set([...allTrips.map(t=>t.service_name),...cpSpecs.flatMap(s=>s.services.map(x=>x.name))].filter((s):s is string=>Boolean(s)))).map(s=><option key={s}>{s}</option>)}</select></label>
     <label className="field">С даты<input type="date" value={draft.from} onChange={e=>setDraft(f=>({...f,from:e.target.value}))}/></label><label className="field">По дату<input type="date" value={draft.to} onChange={e=>setDraft(f=>({...f,to:e.target.value}))}/></label><button className="button">Применить</button><button type="button" className="button secondary" onClick={()=>{setDraft(blankFilter);setApplied(blankFilter);setExpanded(false)}}>Сбросить</button>
    </form>
    {expanded&&<details className="cp-trip-results" open><summary>Список рейсов · {filteredTrips.length} · {money(filteredTrips.reduce((s,t)=>s+Number(t.volume||0)*Number(t.unit_price||0),0))}</summary><div className="table-scroll cp-sheet"><table><thead><tr><th>№</th><th>Дата</th><th>Рейс</th><th>Объект</th><th>Услуга</th><th>Техника</th><th>Водитель</th><th>Объём</th><th>Цена</th><th>Сумма</th>{documents.map(d=><th key={d}>{d}</th>)}</tr></thead><tbody>{filteredTrips.map((t,index)=><tr key={t.id}><td>{index+1}</td><td>{t.trip_date||'—'}</td><td>{t.trip_number}</td><td>{sites.find(s=>s.id===t.site_id)?.name||'—'}</td><td>{t.service_name||'—'}</td><td>{vehicles.find(v=>v.id===t.vehicle_id)?.plate||'—'}</td><td>{drivers.find(d=>d.id===t.driver_id)?.full_name||'—'}</td><td>{t.volume||0}</td><td>{money(t.unit_price||0)}</td><td>{money(Number(t.volume||0)*Number(t.unit_price||0))}</td>{documents.map(d=><td key={d}><span className={'cp-badge '+(hasDoc(t.id,d)?'paid':'pending')}>{hasDoc(t.id,d)?'Получен':'Не получен'}</span></td>)}</tr>)}</tbody></table>{!filteredTrips.length&&<p className="empty">Рейсов по выбранным условиям нет</p>}</div></details>}
   </section>
   <section className="panel cp-finance"><div className="block-heading"><h3>Счета исполнителя</h3><button className="button compact" onClick={()=>open('invoice')}><Plus size={15}/>Добавить счёт</button></div>
    <div className="cp-totals">{[['Выставлено',billed],['Оплачено',paid],['Задолженность',billed-paid]].map(([label,value])=><div key={label}><small>{label}</small><strong>{money(Number(value))}</strong></div>)}</div>
    <div className="table-scroll"><table><thead><tr><th>Счёт</th><th>Дата / срок</th><th>Сумма</th><th>Оплачено</th><th>Долг</th><th>Статус</th><th>Действие</th></tr></thead><tbody>{cpInvoices.map(i=><tr key={i.id}><td><strong>{i.invoice_number}</strong></td><td>{i.invoice_date}<br/><small>{i.due_date||'Срок не указан'}</small></td><td>{money(i.amount)}</td><td>{money(i.paid_amount)}</td><td>{money((cents(i.amount)-cents(i.paid_amount))/100)}</td><td><span className={'cp-badge '+tone(invoiceState(i))}>{invoiceState(i)}</span></td><td><button className="text-button" disabled={cents(i.paid_amount)>=cents(i.amount)} onClick={()=>open('payment',{invoice_id:i.id})}>Добавить оплату</button><button className="text-button" disabled={Number(i.paid_amount)>0} onClick={()=>open('status',{invoice_id:i.id,status:i.status})}>Изменить статус</button></td></tr>)}</tbody></table>{!cpInvoices.length&&<p className="empty">Исполнитель пока не выставил счета</p>}</div><p className="hint">Зелёный — оплачен, жёлтый — частичная оплата, красный — просрочен. Оплата и долг рассчитываются по суммам.</p>
   </section>
  </>}</div></div>
  {modal&&<Modal title={titles[modal]} busy={busy} onClose={()=>{if(!busy)setModal(null)}}><form onSubmit={save}><fieldset className="form-body" disabled={busy}><div className="form-grid">
   {modal==='carrier'&&<>{field('name','Название компании','text',true)}{field('inn','ИНН')}{field('kpp','КПП')}{field('ogrn','ОГРН')}{field('phone','Телефон','tel')}{field('email','Email','email')}{field('legal_address','Юридический адрес')}</>}
   {modal==='contract'&&<>{field('number','Номер договора','text',true)}{field('date','Дата договора','date',true)}{field('end_date','Действует до','date')}<label className="field">Тип договора<select value={form.kind||'transport'} onChange={e=>set('kind',e.target.value)}><option value="transport">Транспортные услуги</option><option value="supply">Поставка</option></select></label>{field('notes','Условия и примечания')}</>}
   {modal==='specification'&&<>{field('number','Номер спецификации','text',true)}{field('date','Дата спецификации','date',true)}<label className="field wide">Договор<select required value={form.contract_id||''} onChange={e=>set('contract_id',e.target.value)}><option value="">Выберите договор</option>{cpContracts.map(c=><option key={c.id} value={c.id}>{c.number}</option>)}</select></label><div className="wide cp-service-editor"><h3>Услуги и цены</h3>{services.map((s,index)=><div className="cp-service-row" key={s.id}><label className="field">Услуга {index+1}<input required value={s.name} onChange={e=>setServices(rows=>rows.map(x=>x.id===s.id?{...x,name:e.target.value}:x))}/></label><label className="field">Ед.<select value={s.unit} onChange={e=>setServices(rows=>rows.map(x=>x.id===s.id?{...x,unit:e.target.value}:x))}>{['м³','т','час','смена','рейс','км','шт.'].map(u=><option key={u}>{u}</option>)}</select></label><label className="field">Цена, ₽<input required type="number" min="0.01" step="0.01" value={s.price} onChange={e=>setServices(rows=>rows.map(x=>x.id===s.id?{...x,price:e.target.value}:x))}/></label><button type="button" className="icon-button" aria-label={'Удалить услугу '+(index+1)} disabled={services.length===1} onClick={()=>setServices(rows=>rows.filter(x=>x.id!==s.id))}>×</button></div>)}<button type="button" className="button secondary" onClick={()=>setServices(rows=>[...rows,{id:crypto.randomUUID(),name:'',unit:'м³',price:''}])}>Добавить услугу</button></div></>}
   {modal==='vehicle'&&<>{field('vehicle_type','Вид спецтехники','text',true)}{field('plate','Госномер','text',true)}{field('phone','Телефон техники','tel')}{field('brand','Марка')}{field('model','Модель')}</>}
   {modal==='driver'&&<>{field('full_name','ФИО водителя','text',true)}{field('phone','Телефон водителя','tel')}{field('license_number','Номер удостоверения')}</>}
   {modal==='invoice'&&<>{field('invoice_number','Номер счёта','text',true)}{field('invoice_date','Дата счёта','date',true)}{field('amount','Сумма, ₽','number',true)}{field('due_date','Оплатить до','date')}</>}
   {(modal==='payment'||modal==='status')&&<label className="field wide">Счёт<select required value={form.invoice_id||''} onChange={e=>set('invoice_id',e.target.value)}>{cpInvoices.filter(i=>modal!=='payment'||cents(i.paid_amount)<cents(i.amount)).map(i=><option key={i.id} value={i.id}>{i.invoice_number} · долг {money((cents(i.amount)-cents(i.paid_amount))/100)}</option>)}</select></label>}
   {modal==='payment'&&field('payment_amount','Сумма оплаты, ₽','number',true)}
   {modal==='status'&&<label className="field wide">Статус<select value={form.status||'Ожидает оплаты'} onChange={e=>set('status',e.target.value)}>{['Ожидает оплаты','На согласовании','Просрочен'].map(s=><option key={s}>{s}</option>)}</select></label>}
   </div>{error&&<p className="form-error" role="alert">{error}</p>}</fieldset><footer className="modal-actions"><span>* Обязательные поля</span><button type="button" className="button secondary" disabled={busy} onClick={()=>setModal(null)}>Отмена</button><button className="button" disabled={busy}>{busy?'Сохранение…':'Сохранить'}</button></footer></form></Modal>}
 </div>
}
