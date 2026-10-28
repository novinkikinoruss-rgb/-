import type {AccountingDocument} from './accounting';
type Trip={id:string;deleted_at?:string|null;status:string};
type Link={document_id:string;trip_id:string;active:boolean};
// A mixed draft containing even one removed trip is stale as a whole: its amount/snapshot cannot be silently rewritten.
export function exportableDocuments(documents:AccountingDocument[],links:Link[],trips:Trip[]){
 const live=new Set(trips.filter(t=>!t.deleted_at&&t.status!=='cancelled').map(t=>t.id));
 const eligible=documents.filter(d=>{
  if(d.deleted_at||d.status==='cancelled')return false;
  const source=links.filter(l=>l.document_id===d.id&&l.active);
  if(d.kind!=='advance'&&!source.length)return false;
  return source.every(l=>live.has(l.trip_id))&&d.snapshot.items.every(i=>!i.trip_id||live.has(i.trip_id));
 });
 const ids=new Set(eligible.map(d=>d.id));return eligible.filter(d=>!d.invoice_id||ids.has(d.invoice_id));
}
