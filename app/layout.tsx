import type {Metadata} from 'next';
import './globals.css';
import './profit.css';
import './accounting.css';
export const metadata: Metadata = {title:'Respectlogistic · Транспорт CRM', description:'Рабочее пространство транспортной компании'};
export default function Layout({children}:{children:React.ReactNode}) {
  return <html lang="ru"><body>{children}</body></html>;
}
