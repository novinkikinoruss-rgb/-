export const dynamic='force-dynamic';
export async function GET(){return Response.json({status:'ok',service:'respectlogistic',timestamp:new Date().toISOString(),innConfigured:Boolean(process.env.DADATA_API_KEY)},{headers:{'Cache-Control':'no-store'}});}
