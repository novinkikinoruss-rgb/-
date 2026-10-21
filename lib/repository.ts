import {applyCommand,type Command,type Workspace} from './domain';
import {demoWorkspace} from './demo';
import {db} from './supabase';
import {deadline} from './network';
export const STORAGE_KEY='respectlogistic-preview-v1';
export async function loadWorkspace():Promise<Workspace>{
  if(db){const {data,error}=await deadline(db.rpc('respectlogistic_read_workspace'),25000,'База данных не ответила вовремя. Повторите загрузку.');if(error)throw new Error(/timeout|не ответил|fetch|network/i.test(error.message)?'База данных не ответила. Проверьте соединение и повторите загрузку.':'Не удалось загрузить базу: '+error.message);return data as Workspace;}
  const raw=localStorage.getItem(STORAGE_KEY);
  if(!raw){const seed=demoWorkspace();localStorage.setItem(STORAGE_KEY,JSON.stringify(seed));return seed;}
  const parsed=JSON.parse(raw) as Workspace;
  if(!Array.isArray(parsed.customers)||!Array.isArray(parsed.documents)||!Number.isInteger(parsed.revision))throw new Error('Сохранённые данные повреждены. Сохраните копию перед восстановлением.');
  return parsed;
}
export async function commitCommand(command:Command):Promise<Workspace>{
  if(db){
    const {data,error}=await db.rpc('respectlogistic_customer_action',{command});
    if(error)throw new Error(error.message);
    return data as Workspace;
  }
  if(!navigator.locks)throw new Error('Для сохранения нужен современный браузер с поддержкой Web Locks');
  return navigator.locks.request('respectlogistic-preview-write',async()=>{
    const current=await loadWorkspace();const next=applyCommand(current,command);
    localStorage.setItem(STORAGE_KEY,JSON.stringify(next));return next;
  });
}
