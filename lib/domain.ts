export type Customer = {
  id:string; name:string; fullName:string; inn:string; kpp:string; ogrn:string;
  legalAddress:string; postalAddress:string; director:string; basis:string;
  contactName:string; phone:string; email:string; bank:string; bik:string;
  account:string; correspondent:string; notes:string; createdAt:string;
};
export type Contract = {id:string; customerId:string; kind:'transport'|'supply'; number:string; date:string; endDate:string; notes:string};
export type Service = {id:string; name:string; unit:string; priceKopecks:number};
export type Specification = {id:string; customerId:string; contractId:string; number:string; date:string; services:Service[]};
export type Site = {id:string; customerId:string; contractId:string; specificationId:string; serviceId:string; name:string; address:string; loadingAddress:string; routeKm:string; foreman:string; foremanPhone:string; foremanEmail:string; access:string; notes:string};
export type Document = {id:string; customerId:string; entityId:string; folder:'contracts'|'specifications'|'sites'; title:string; createdAt:string; snapshot:Record<string,unknown>};
export type Activity = {id:string; customerId:string; text:string; createdAt:string};
export type Workspace = {revision:number; customers:Customer[]; contracts:Contract[]; specifications:Specification[]; sites:Site[]; documents:Document[]; activity:Activity[]};
export type CustomerInput = Omit<Customer,'id'|'createdAt'>;
export type Command =
  | {type:'customer.create'; id:string; data:CustomerInput}
  | {type:'customer.update'; id:string; customerId:string; data:CustomerInput}
  | {type:'contract.create'; id:string; customerId:string; data:Omit<Contract,'id'|'customerId'|'number'>}
  | {type:'specification.create'; id:string; customerId:string; data:Omit<Specification,'id'|'customerId'|'number'>}
  | {type:'site.create'; id:string; customerId:string; data:Omit<Site,'id'|'customerId'>};
export const emptyWorkspace = ():Workspace => ({revision:0,customers:[],contracts:[],specifications:[],sites:[],documents:[],activity:[]});
export const emptyCustomer:CustomerInput = {name:'',fullName:'',inn:'',kpp:'',ogrn:'',legalAddress:'',postalAddress:'',director:'',basis:'Устав',contactName:'',phone:'',email:'',bank:'',bik:'',account:'',correspondent:'',notes:''};
export function validInn(value:string){
  if(!/^\d{10}$/.test(value))return false;
  const weights=[2,4,10,3,5,9,4,6,8];
  return weights.reduce((sum,w,i)=>sum+w*Number(value[i]),0)%11%10===Number(value[9]);
}
export function moneyInput(value:string){
  const normalized=value.trim().replace(',','.');
  if(!/^\d+(\.\d{1,2})?$/.test(normalized))throw new Error('Цена должна быть положительной суммой с точностью до копеек');
  const [whole,fraction='']=normalized.split('.');
  const result=Number(whole)*100+Number(fraction.padEnd(2,'0'));
  if(!Number.isSafeInteger(result)||result<=0||result>999999999999)throw new Error('Проверьте цену услуги');
  return result;
}
export const money=(kopecks:number)=>new Intl.NumberFormat('ru-RU',{style:'currency',currency:'RUB',maximumFractionDigits:2}).format(kopecks/100);
export function dateOnly(value:string){return /^\d{4}-\d{2}-\d{2}$/.test(value)&&!Number.isNaN(Date.parse(value))&&new Date(value+'T00:00:00Z').toISOString().slice(0,10)===value;}
function required(value:string,label:string){if(typeof value!=='string'||!value.trim())throw new Error(`Заполните поле «${label}»`);if(value.length>4000)throw new Error(`Поле «${label}» слишком длинное`);}
export function validateCustomer(data:CustomerInput){
  for(const [key,value] of Object.entries(data))if(typeof value!=='string'||value.length>4000)throw new Error(`Проверьте поле ${key}`);
  required(data.name,'Название компании');required(data.inn,'ИНН');
  if(!validInn(data.inn))throw new Error('Проверьте ИНН организации: 10 цифр и контрольная сумма');
  if(data.kpp&&!/^\d{9}$/.test(data.kpp))throw new Error('КПП должен содержать 9 цифр');
  if(data.ogrn&&!/^\d{13}$/.test(data.ogrn))throw new Error('ОГРН должен содержать 13 цифр');
  if(data.bik&&!/^\d{9}$/.test(data.bik))throw new Error('БИК должен содержать 9 цифр');
  if([data.account,data.correspondent].some(v=>v&&!/^\d{20}$/.test(v)))throw new Error('Банковский счёт должен содержать 20 цифр');
  if(data.email&&!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(data.email))throw new Error('Проверьте email');
}
// Immutable domain operation, shared by preview and the authenticated server API.
export function applyCommand(current:Workspace,command:Command,now=new Date().toISOString()):Workspace{
  if(!/^[a-zA-Z0-9-]{6,80}$/.test(command.id))throw new Error('Некорректный идентификатор действия');
  if(current.activity.some(a=>a.id===command.id))return current; // idempotent retry
  const state=structuredClone(current);
  let customerId='', text='';
  if(command.type==='customer.create'||command.type==='customer.update'){
    validateCustomer(command.data);
    if(state.customers.some(c=>c.inn===command.data.inn&&c.id!==(command.type==='customer.update'?command.customerId:'')))throw new Error('Заказчик с таким ИНН уже существует');
    if(command.type==='customer.create'){
      customerId=command.id;
      state.customers.push({...command.data,id:customerId,createdAt:now});text='Создана карточка заказчика';
    }else{
      const customer=state.customers.find(c=>c.id===command.customerId);
      if(!customer)throw new Error('Заказчик не найден');
      state.customers=state.customers.map(c=>c.id===customer.id?{...c,...command.data}:c);customerId=customer.id;text='Карточка заказчика обновлена';
    }
  }else{
    customerId=command.customerId;
    if(!state.customers.some(c=>c.id===customerId))throw new Error('Заказчик не найден');
    if(command.type==='contract.create'){
      const d=command.data;
      if(!['transport','supply'].includes(d.kind))throw new Error('Выберите тип договора');
      if(!dateOnly(d.date)||d.endDate&&(!dateOnly(d.endDate)||d.endDate<d.date))throw new Error('Проверьте даты договора');
      const prefix=d.kind==='transport'?'ТР':'ПС',year=d.date.slice(0,4);
      const numbers=state.contracts.filter(c=>c.kind===d.kind&&c.date.startsWith(year)).map(c=>Number(c.number.split('-').at(-1)));
      const number=`${prefix}-${year}-${String(Math.max(0,...numbers)+1).padStart(4,'0')}`;
      const contract={...d,id:command.id,customerId,number};state.contracts.push(contract);text=`Создан договор ${number}`;
      state.documents.push({id:command.id,customerId,entityId:command.id,folder:'contracts',title:`Договор ${number}`,createdAt:now,snapshot:{...contract,customer:state.customers.find(c=>c.id===customerId)}});
    }else if(command.type==='specification.create'){
      const d=command.data,contract=state.contracts.find(c=>c.id===d.contractId&&c.customerId===customerId);
      if(!contract)throw new Error('Выберите договор этого заказчика');
      if(!dateOnly(d.date)||d.date<contract.date||contract.endDate&&d.date>contract.endDate)throw new Error('Дата спецификации должна входить в период договора');
      if(!d.services.length||d.services.length>100)throw new Error('Добавьте от 1 до 100 услуг');
      const ids=new Set<string>();
      for(const service of d.services){required(service.name,'Услуга');required(service.unit,'Единица измерения');if(!service.id||ids.has(service.id))throw new Error('Услуги должны иметь разные идентификаторы');ids.add(service.id);if(!Number.isSafeInteger(service.priceKopecks)||service.priceKopecks<=0||service.priceKopecks>999999999999)throw new Error('Проверьте цену услуги');}
      const number=`${contract.number}/СП-${String(state.specifications.filter(s=>s.contractId===contract.id).length+1).padStart(2,'0')}`;
      const specification={...d,id:command.id,customerId,number};state.specifications.push(specification);text=`Создана спецификация ${number}`;
      state.documents.push({id:command.id,customerId,entityId:command.id,folder:'specifications',title:`Спецификация ${number}`,createdAt:now,snapshot:{...specification,customer:state.customers.find(c=>c.id===customerId),contract}});
    }else if(command.type==='site.create'){
      const d=command.data;
      const specification=state.specifications.find(s=>s.id===d.specificationId&&s.customerId===customerId&&s.contractId===d.contractId);
      if(!specification||!specification.services.some(s=>s.id===d.serviceId))throw new Error('Выберите спецификацию и услугу этого заказчика');
      required(d.name,'Название объекта');required(d.address,'Адрес объекта');required(d.foreman,'Ответственный прораб');
      if(d.routeKm&&!/^\d+(\.\d{1,3})?$/.test(d.routeKm)||Number(d.routeKm)>100000)throw new Error('Расстояние в одну сторону должно быть неотрицательным числом');
      if(d.foremanEmail&&!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(d.foremanEmail))throw new Error('Проверьте email прораба');
      const site={...d,id:command.id,customerId};state.sites.push(site);text=`Создан объект «${d.name}»`;
      state.documents.push({id:command.id,customerId,entityId:command.id,folder:'sites',title:`Карточка объекта «${d.name}»`,createdAt:now,snapshot:{...site,service:specification.services.find(s=>s.id===d.serviceId)}});
    }else throw new Error('Неизвестное действие');
  }
  state.activity.unshift({id:command.id,customerId,text,createdAt:now});state.revision++;
  return state;
}
