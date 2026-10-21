export const dynamic = 'force-dynamic';
export async function GET(){return Response.json({status:'ok',service:'transport-crm',timestamp:new Date().toISOString()},{headers:{'Cache-Control':'no-store'}})}
