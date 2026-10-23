alter table public.respectlogistic_trip_files drop constraint respectlogistic_trip_files_doc_type_check;
alter table public.respectlogistic_trip_files add constraint respectlogistic_trip_files_doc_type_check check(doc_type in ('ttn','waybill','ticket','invoice','upd','registry','other'));
revoke execute on function public.respectlogistic_queue_trip_documents() from authenticated;
notify pgrst,'reload schema';
