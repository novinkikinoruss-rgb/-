import {NextRequest,NextResponse} from 'next/server';
export async function GET(req:NextRequest){
const inn=req.nextUrl.searchParams.get('inn')?.trim()??'';
if(!/^\d{10}(\d{2})?$/.test(inn))return NextResponse.json({error:'Укажите ИНН из 10 или 12 цифр'},{status:400});
const key=process.env.DADATA_API_KEY;
if(!key)return NextResponse.json({error:'Автозаполнение по ИНН пока не подключено: нужен API-ключ DaData. Реквизиты можно заполнить вручную.'},{status:503});
try{const res=await fetch('https://suggestions.dadata.ru/suggestions/api/4_1/rs/findById/party',{method:'POST',headers:{Authorization:'Token '+key,'Content-Type':'application/json'},body:JSON.stringify({query:inn,count:1}),cache:'no-store'});if(!res.ok)throw Error('Справочник организаций недоступен');const body=await res.json();const match=body.suggestions?.find((x:{data?:{inn?:string}})=>x.data?.inn===inn);if(!match)return NextResponse.json({error:'Организация с таким ИНН не найдена'},{status:404});return NextResponse.json({name:match.data?.name?.full_with_opf||match.value,inn:match.data?.inn});}catch{return NextResponse.json({error:'Не удалось получить данные организации'},{status:502})}
}