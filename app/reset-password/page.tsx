import type {Metadata} from 'next';
import {PasswordRecovery} from '../../components/PasswordRecovery';

export const metadata:Metadata={title:'Восстановление доступа · CRM',referrer:'no-referrer',robots:{index:false,follow:false}};
export default function Page(){return <PasswordRecovery/>;}
