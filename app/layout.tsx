import type { Metadata } from 'next';
import './globals.css';
export const metadata: Metadata = {title:'Транспорт CRM | Управление перевозками',description:'CRM для грузоперевозок и автопарка'};
export default function RootLayout({children}:{children:React.ReactNode}){return <html lang="ru"><body>{children}</body></html>}
