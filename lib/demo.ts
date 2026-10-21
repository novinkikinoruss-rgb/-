import {applyCommand,emptyCustomer,emptyWorkspace,type Workspace} from './domain';
export function demoWorkspace():Workspace{
  const date='2026-10-01',now='2026-10-01T09:00:00.000Z';
  let state=applyCommand(emptyWorkspace(),{type:'customer.create',id:'demo-customer',data:{...emptyCustomer,name:'ООО «Стройресурс»',fullName:'Общество с ограниченной ответственностью «Стройресурс»',inn:'7700000009',kpp:'770001001',legalAddress:'Москва · пример адреса',director:'Иванов Алексей Сергеевич',contactName:'Анна · пример контакта',phone:'+7 (000) 000-00-00',email:'office@example.com',notes:'Демонстрационная компания. Реквизиты и контакты приведены для примера.'}},now);
  state=applyCommand(state,{type:'contract.create',id:'demo-contract',customerId:'demo-customer',data:{kind:'transport',date,endDate:'2026-12-31',notes:'Проект договора'}},now);
  state=applyCommand(state,{type:'specification.create',id:'demo-specification',customerId:'demo-customer',data:{contractId:'demo-contract',date,services:[{id:'demo-service',name:'Перевозка песка',unit:'м³',priceKopecks:65000}]}},now);
  state=applyCommand(state,{type:'site.create',id:'demo-site',customerId:'demo-customer',data:{contractId:'demo-contract',specificationId:'demo-specification',serviceId:'demo-service',name:'ЖК «Северный»',address:'Москва · пример адреса объекта',loadingAddress:'Карьер · пример адреса погрузки',routeKm:'45',foreman:'Иван Петров · пример',foremanPhone:'+7 (000) 000-00-00',foremanEmail:'foreman@example.com',access:'Заезд через КПП № 2, с 08:00 до 18:00',notes:''}},now);
  return state;
}
