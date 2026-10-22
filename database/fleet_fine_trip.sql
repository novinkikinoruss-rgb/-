alter table public.crm_driver_fines add column if not exists trip_id uuid references public.crm_trips(id);
create index if not exists crm_driver_fines_trip_idx on public.crm_driver_fines(trip_id);
notify pgrst,'reload schema';
