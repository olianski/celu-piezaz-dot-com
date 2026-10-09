-- Avoid creating repeated open requests from the same technician for the same product.
create unique index if not exists demand_requests_one_open_per_product_uidx
on public.demand_requests(technician_id, product_id)
where status = 'open';
