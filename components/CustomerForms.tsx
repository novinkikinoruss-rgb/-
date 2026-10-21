'use client';
import {useRef,useState,type FormEvent} from 'react';
import {Plus,SearchCheck,LoaderCircle,ArrowRight,Trash2,Building2,FileText,MapPin} from 'lucide-react';
import {emptyCustomer,validInn,moneyInput,type Customer,type CustomerInput,type Command,type Workspace,type Service} from '../lib/domain';
import {db} from '../lib/supabase';
import {useNotice} from './Notifications';
import {Modal} from './Modal';
export type FormKind='customer'|'contract'|'specification'|'site';
export function CustomerForms({kind,customer,edit=false,state,preferredContractId,preferredSpecId,onClose,onSaved}:{kind:FormKind;customer:Customer|null;edit?:boolean;state:Workspace;preferredContractId?:string;preferredSpecId?:string;onClose:()=>void;onSaved:(command:Command)=>Promise<void>}){
  const notify=useNotice();const [busy,setBusy]=useState(false),[lookup,setLookup]=useState(false),[error,setError]=useState('');
  const saving=useRef(false);const innGeneration=useRef(0);const lastInn=useRef('');const requestId=useRef(crypto.randomUUID());
  const [company,setCompany]=useState<CustomerInput>(edit&&customer?{...customer}:{...emptyCustomer});
  const today=new Date().toLocaleDateString('en-CA');
  const contracts=state.contracts.filter(c=>c.customerId===customer?.id);
  const [contract,setContract]=useState({kind:'transport' as 'transport'|'supply',date:today,endDate:'',notes:''});
  const [contractId,setContractId]=useState(preferredContractId||contracts.at(-1)?.id||'');
  const [specDate,setSpecDate]=useState(today);
  const [rows,setRows]=useState([{id:crypto.randomUUID(),name:'',unit:'м³',price:''}]);
  const specs=state.specifications.filter(s=>s.customerId===customer?.id&&s.contractId===contractId);
  const [specId,setSpecId]=useState(preferredSpecId||specs.at(-1)?.id||'');
  const selectedSpec=specs.find(s=>s.id===specId);
  const [site,setSite]=useState({serviceId:selectedSpec?.services[0]?.id||'',name:'',address:'',loadingAddress:'',routeKm:'',foreman:'',foremanPhone:'',foremanEmail:'',access:'',notes:''});
  const labels={customer:edit?'Редактировать заказчика':'Новый заказчик',contract:'Новый договор',specification:'Новая спецификация',site:'Новый объект'};
  function changeCompany(key:keyof CustomerInput,value:string){if(key==='inn')innGeneration.current++;setCompany(p=>({...p,[key]:value}));}
  async function lookupInn(){
    if(!validInn(company.inn)){setError('Введите корректный ИНН организации: 10 цифр');return;}
    if(lookup)return;
    const generation=++innGeneration.current;lastInn.current=company.inn;setLookup(true);setError('');
    try{
      const session=db?await db.auth.getSession():null;
      const response=await fetch('/api/company',{method:'POST',headers:{'Content-Type':'application/json',...(session?.data.session?{Authorization:`Bearer ${session.data.session.access_token}`}:{})},body:JSON.stringify({inn:company.inn}),signal:AbortSignal.timeout(15000)});
      const result=await response.json();if(!response.ok){window.dispatchEvent(new CustomEvent('respectlogistic:inn',{detail:response.status===503?'unconfigured':'error'}));throw new Error(result.error||'Не удалось получить реквизиты');}
      if(generation!==innGeneration.current)return;
      setCompany(previous=>({...previous,...result.company}));notify('Реквизиты организации загружены. Проверьте их перед сохранением.');window.dispatchEvent(new CustomEvent('respectlogistic:inn',{detail:'ok'}));
    }catch(e){const message=e instanceof Error?e.message:'Не удалось загрузить данные';setError(message);notify(message,'error');}
    finally{setLookup(false);}
  }
  function companyField(label:string,key:keyof CustomerInput,required=false,type='text'){
    return <label className="field" key={key}>{label}{required&&<span className="required">*</span>}<input name={key} value={company[key]} required={required} type={type} maxLength={key==='inn'?10:4000} onChange={e=>changeCompany(key,e.target.value)} autoComplete="off"/></label>;
  }
  async function save(event:FormEvent){
    event.preventDefault();if(saving.current)return;saving.current=true;setBusy(true);setError('');
    try{
      const id=requestId.current;let command:Command;
      if(kind==='customer')command=edit&&customer?{type:'customer.update',id,customerId:customer.id,data:company}:{type:'customer.create',id,data:company};
      else{
        if(!customer)throw new Error('Сначала создайте заказчика');
        if(kind==='contract')command={type:'contract.create',id,customerId:customer.id,data:contract};
        else if(kind==='specification'){
          const services:Service[]=rows.map(row=>({id:row.id,name:row.name.trim(),unit:row.unit,priceKopecks:moneyInput(row.price)}));
          command={type:'specification.create',id,customerId:customer.id,data:{contractId,date:specDate,services}};
        }else command={type:'site.create',id,customerId:customer.id,data:{...site,contractId,specificationId:specId,routeKm:site.routeKm.replace(',','.')}};
      }
      await onSaved(command);
    }catch(e){const message=e instanceof Error?e.message:'Не удалось сохранить';setError(message);notify(message,'error');}
    finally{saving.current=false;setBusy(false);}
  }
  return <Modal title={labels[kind]} onClose={onClose} busy={busy||lookup}><form onSubmit={save}><fieldset disabled={busy} className="form-body">
    <div className="form-intro"><span className="soft-icon">{kind==='customer'?<Building2/>:kind==='site'?<MapPin/>:<FileText/>}</span><p>{kind==='customer'?'Заполните реквизиты. После сохранения предложим создать договор.':kind==='contract'?'Номер присвоится при сохранении. Договор появится в папке компании.':kind==='specification'?'Услуги и цены будут доступны при создании объекта и будущих рейсов.':'Укажите маршрут, услугу и ответственного за объект.'}</p></div>
    {kind==='customer'&&<>
      <section className="form-section"><h3>Компания и реквизиты</h3><div className="inn-lookup"><label className="field">ИНН организации *<input name="inn" inputMode="numeric" placeholder="10 цифр" required maxLength={10} value={company.inn} onChange={e=>changeCompany('inn',e.target.value.replace(/\D/g,''))} onBlur={()=>{if(db&&validInn(company.inn)&&lastInn.current!==company.inn)void lookupInn();}}/></label><button type="button" className="button secondary" disabled={lookup} onClick={()=>void lookupInn()}>{lookup?<LoaderCircle className="spin" size={16}/>:<SearchCheck size={16}/>}Заполнить по ИНН</button></div><div className="form-grid">{companyField('Краткое название','name',true)}{companyField('Полное наименование','fullName')}{companyField('КПП','kpp')}{companyField('ОГРН','ogrn')}<label className="field wide">Юридический адрес<textarea value={company.legalAddress} maxLength={4000} onChange={e=>changeCompany('legalAddress',e.target.value)}/></label>{companyField('Почтовый адрес','postalAddress')}{companyField('Руководитель','director')}{companyField('Действует на основании','basis')}</div></section>
      <section className="form-section"><h3>Контакты</h3><div className="form-grid">{companyField('Контактное лицо','contactName')}{companyField('Телефон','phone',false,'tel')}{companyField('Email','email',false,'email')}</div></section>
      <details className="form-section"><summary>Банковские реквизиты и примечания</summary><div className="form-grid">{companyField('Банк','bank')}{companyField('БИК','bik')}{companyField('Расчётный счёт','account')}{companyField('Корреспондентский счёт','correspondent')}<label className="field wide">Примечания<textarea value={company.notes} maxLength={4000} onChange={e=>changeCompany('notes',e.target.value)}/></label></div></details>
    </>}
    {kind==='contract'&&<section className="form-section"><label className="field">Тип договора</label><div className="segmented">{([['transport','Транспортные услуги'],['supply','Поставка']] as const).map(([value,label])=><button key={value} type="button" className={contract.kind===value?'chosen':''} aria-pressed={contract.kind===value} onClick={()=>setContract(p=>({...p,kind:value}))}>{label}</button>)}</div><div className="auto-number"><span>Номер договора</span><strong>{contract.kind==='transport'?'ТР':'ПС'}-{contract.date.slice(0,4)||'ГГГГ'}-••••</strong><small>Присваивается автоматически при сохранении</small></div><div className="form-grid"><label className="field">Дата договора *<input aria-label="Дата договора" type="date" required value={contract.date} onChange={e=>setContract(p=>({...p,date:e.target.value}))}/></label><label className="field">Действует до<input type="date" min={contract.date} value={contract.endDate} onChange={e=>setContract(p=>({...p,endDate:e.target.value}))}/></label><label className="field wide">Условия и примечания<textarea value={contract.notes} maxLength={4000} onChange={e=>setContract(p=>({...p,notes:e.target.value}))}/></label></div><p className="hint">Будет создан проект документа для проверки и согласования.</p></section>}
    {(kind==='specification'||kind==='site')&&<section className="form-section"><div className="form-grid"><label className="field">Договор *<select required value={contractId} onChange={e=>{setContractId(e.target.value);setSpecId('');setSite(p=>({...p,serviceId:''}));}}><option value="">Выберите договор</option>{contracts.map(c=><option key={c.id} value={c.id}>{c.number} · {c.kind==='transport'?'Перевозка':'Поставка'}</option>)}</select></label>{kind==='specification'&&<label className="field">Дата спецификации *<input type="date" required value={specDate} onChange={e=>setSpecDate(e.target.value)}/></label>}{kind==='site'&&<><label className="field">Спецификация *<select required value={specId} onChange={e=>{setSpecId(e.target.value);setSite(p=>({...p,serviceId:''}));}}><option value="">Выберите спецификацию</option>{specs.map(s=><option key={s.id} value={s.id}>{s.number}</option>)}</select></label><label className="field wide">Услуга и цена *<select required value={site.serviceId} onChange={e=>setSite(p=>({...p,serviceId:e.target.value}))}><option value="">Выберите услугу</option>{selectedSpec?.services.map(s=><option key={s.id} value={s.id}>{s.name} · {(s.priceKopecks/100).toLocaleString('ru-RU')} ₽/{s.unit}</option>)}</select></label></>}</div></section>}
    {kind==='specification'&&<section className="form-section"><h3>Услуги и цены</h3>{rows.map((row,index)=><div className="service-row" key={row.id}><label className="field">Услуга {index+1}<input required aria-label={`Услуга ${index+1}`} maxLength={4000} value={row.name} onChange={e=>setRows(p=>p.map(r=>r.id===row.id?{...r,name:e.target.value}:r))}/></label><label className="field">Ед.<select value={row.unit} onChange={e=>setRows(p=>p.map(r=>r.id===row.id?{...r,unit:e.target.value}:r))}>{['м³','т','км','рейс','час','шт.'].map(unit=><option key={unit}>{unit}</option>)}</select></label><label className="field">Цена, ₽<input required aria-label={`Цена ${index+1}`} inputMode="decimal" value={row.price} onChange={e=>setRows(p=>p.map(r=>r.id===row.id?{...r,price:e.target.value}:r))}/></label><button type="button" className="icon-button" aria-label={`Удалить услугу ${index+1}`} disabled={rows.length===1} onClick={()=>setRows(p=>p.filter(r=>r.id!==row.id))}><Trash2 size={17}/></button></div>)}<button type="button" className="button secondary" onClick={()=>setRows(p=>[...p,{id:crypto.randomUUID(),name:'',unit:'м³',price:''}])}><Plus size={16}/>Добавить услугу</button></section>}
    {kind==='site'&&<section className="form-section"><h3>Объект и ответственный</h3><div className="form-grid">{([['name','Название объекта',true],['address','Адрес объекта',true],['loadingAddress','Адрес погрузки',false],['routeKm','Расстояние в одну сторону, км',false],['foreman','Ответственный прораб',true],['foremanPhone','Телефон прораба',false],['foremanEmail','Email прораба',false],['access','Условия доступа и часы работы',false]] as const).map(([key,label,required])=><label key={key} className="field">{label}{required?' *':''}<input required={required} type={key==='foremanEmail'?'email':'text'} inputMode={key==='routeKm'?'decimal':undefined} maxLength={4000} value={site[key]} onChange={e=>setSite(p=>({...p,[key]:e.target.value}))}/></label>)}<label className="field wide">Примечания<textarea maxLength={4000} value={site.notes} onChange={e=>setSite(p=>({...p,notes:e.target.value}))}/></label></div><p className="hint">Объект хранит связь с заказчиком, договором, спецификацией и услугой. В следующих разделах будет использоваться эта же запись.</p></section>}
    </fieldset>{error&&<div className="form-error" role="alert">{error}</div>}<footer className="modal-actions"><span>{busy?'Сохраняем изменения…':'* Обязательные поля'}</span><button type="button" disabled={busy||lookup} className="button secondary" onClick={onClose}>Отмена</button><button className="button" disabled={busy||lookup}>{busy?<LoaderCircle size={17} className="spin"/>:<ArrowRight size={17}/>} {busy?'Сохранение…':'Сохранить'}</button></footer></form></Modal>;
}
