'use client';
import type {ReactNode,Dispatch,SetStateAction} from 'react';
import {useRef} from 'react';
import {Mountain,Menu,LogOut,ChevronRight,AlignJustify,type LucideIcon} from 'lucide-react';
import {SystemStatus} from './SystemStatus';
import {NotificationBell} from './Notifications';
import {useUiPreferences} from './UiPreferences';

type Item={name:string;Icon:LucideIcon;active:boolean;disabled:boolean;count?:number;onClick:()=>void};
export function CrmShell({items,title,sessionName,authenticated,cloud,mobile,setMobile,onSignOut,children,dialogs}:{items:Item[];title:string;sessionName:string;authenticated:boolean;cloud:boolean;mobile:boolean;setMobile:Dispatch<SetStateAction<boolean>>;onSignOut:()=>void;children:ReactNode;dialogs?:ReactNode}){
 const navigation=useRef<HTMLElement>(null);
 const settings=useUiPreferences(),view=settings.values.tables as {density?:string;wrap?:boolean}|undefined;
 const density=view?.density==='comfortable'?'comfortable':'compact',wrap=view?.wrap!==false;
 return <div className="app-shell crm-workspace" data-density={density} data-wrap={wrap?'true':'false'}>
  <header className="crm-header"><div className="crm-brand-group"><button className="icon-button mobile-toggle" aria-label="Открыть меню" aria-expanded={mobile} aria-controls="crm-navigation" onClick={()=>setMobile(!mobile)}><Menu size={20}/></button><a className="brand" href="/" aria-label="Транспорт CRM"><span className="brand-icon"><Mountain size={24}/></span><span>Транспорт<span className="brand-sub">RESPECTLOGISTIC · CRM</span></span></a></div>
   <div className="topbar-right"><SystemStatus/><NotificationBell/><span className="divider"/><span className="user-label">{sessionName}</span><span className="avatar">{sessionName.slice(0,1).toUpperCase()}</span>{cloud&&authenticated&&<button className="icon-button crm-logout" aria-label="Выйти из CRM" title="Выйти из CRM" onClick={onSignOut}><LogOut size={18}/></button>}</div>
  </header>
  <aside id="crm-navigation" className={'sidebar '+(mobile?'mobile-open':'')}><nav ref={navigation} aria-label="Разделы CRM">{items.map(({name,Icon,active,disabled,count,onClick})=><button key={name} className={'nav-item '+(active?'active':'')} disabled={disabled} title={disabled?'Запланировано на следующий этап':undefined} onClick={onClick}><Icon size={17}/><span>{name}</span>{count!==undefined&&<span className="nav-count">{count}</span>}</button>)}</nav><div className="crm-nav-tools"><button className="icon-button" type="button" aria-label="Прокрутить меню влево" onClick={()=>navigation.current?.scrollBy({left:-320,behavior:'smooth'})}>‹</button><button className="icon-button" type="button" aria-label="Прокрутить меню вправо" onClick={()=>navigation.current?.scrollBy({left:320,behavior:'smooth'})}>›</button></div></aside>
  {mobile&&<button className="mobile-backdrop" aria-label="Закрыть меню" onClick={()=>setMobile(false)}/>}
  <main className="main"><div className="crm-contextbar"><div className="breadcrumb"><span>Рабочее пространство</span><ChevronRight size={13}/><strong>{title}</strong></div>
   {authenticated&&<div className="crm-view-controls" aria-label="Настройки просмотра"><AlignJustify size={16}/><label>Строки<select aria-label="Плотность строк" value={density} disabled={!settings.loaded} onChange={e=>settings.update('tables',p=>({...p,density:e.target.value}))}><option value="compact">Компактные</option><option value="comfortable">Просторные</option></select></label><label className="crm-wrap-control"><input type="checkbox" checked={wrap} disabled={!settings.loaded} onChange={e=>settings.update('tables',p=>({...p,wrap:e.target.checked}))}/>Перенос текста</label>{cloud&&<span className={'crm-settings-state '+settings.status} role="status">{settings.status==='saving'?'Сохраняем в БД…':settings.status==='loading'?'Загружаем настройки…':settings.status==='saved'?'Настройки в БД':settings.status==='error'?<><span>{settings.error}</span><button type="button" onClick={settings.retry}>Повторить</button></>:''}</span>}</div>}
  </div>{children}</main>{dialogs}
 </div>;
}
