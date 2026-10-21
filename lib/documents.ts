import {money,type Document,type Customer} from './domain';
export const escapeHtml=(value:unknown)=>String(value??'').replace(/[&<>"']/g,char=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[char]!));
const labels:Record<string,string>={number:'Номер',kind:'Тип договора',date:'Дата',endDate:'Действует до',notes:'Примечания',name:'Наименование',unit:'Ед. измерения',address:'Адрес объекта',loadingAddress:'Адрес погрузки',routeKm:'Расстояние в одну сторону, км',foreman:'Ответственный прораб',foremanPhone:'Телефон прораба',foremanEmail:'Email прораба',access:'Условия доступа'};
export function documentHtml(document:Document,customer:Customer){
  const savedCustomer=document.snapshot.customer;
  if(savedCustomer&&typeof savedCustomer==='object')customer=savedCustomer as Customer;
  const rows=Object.entries(document.snapshot).filter(([key])=>labels[key]).map(([key,value])=>`<tr><th>${escapeHtml(labels[key])}</th><td>${escapeHtml(key==='kind'?(value==='transport'?'Транспортные услуги':'Поставка'):value)}</td></tr>`).join('');
  const services=Array.isArray(document.snapshot.services)?document.snapshot.services as {name:string;unit:string;priceKopecks:number}[]:[];
  return `<!doctype html><html lang="ru"><meta charset="utf-8"><title>${escapeHtml(document.title)}</title><style>body{font:15px Arial;color:#24303c;margin:50px;line-height:1.7}h1{font-size:26px}small{color:#64748b}table{border-collapse:collapse;width:100%;margin:20px 0}td,th{text-align:left;padding:10px;border-bottom:1px solid #ddd}th{width:35%}.draft{padding:16px;background:#fff7dc;border-radius:10px}@media print{body{margin:15mm}}</style><h1>${escapeHtml(document.title)}</h1><p>${escapeHtml(customer.fullName||customer.name)} · ИНН ${escapeHtml(customer.inn)}</p><p class="draft">Проект документа. Требует проверки реквизитов, условий и подписания. Карточка CRM не заменяет согласованный юридический договор.</p><table>${rows}</table>${services.length?`<h2>Услуги и цены</h2><table><tr><th>Услуга</th><th>Ед.</th><th>Цена</th></tr>${services.map(s=>`<tr><td>${escapeHtml(s.name)}</td><td>${escapeHtml(s.unit)}</td><td>${escapeHtml(money(s.priceKopecks))}</td></tr>`).join('')}</table>`:''}<small>Сформировано в Respectlogistic · ${escapeHtml(document.createdAt.slice(0,10))}</small></html>`;
}
export function downloadDocument(document:Document,customer:Customer){
  const url=URL.createObjectURL(new Blob([documentHtml(document,customer)],{type:'text/html;charset=utf-8'}));
  const link=window.document.createElement('a');link.href=url;link.download=document.title.replace(/[^\p{L}\p{N} ._-]/gu,'_')+'.html';link.click();setTimeout(()=>URL.revokeObjectURL(url),1000);
}
