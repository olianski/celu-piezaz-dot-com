-- Prevent duplicate phone models, including case and extra whitespace variations.
-- The existing 109 models were checked and contain no duplicates.
create unique index if not exists phone_models_brand_model_normalized_uidx
on public.phone_models (
  lower(regexp_replace(trim(brand), '\s+', ' ', 'g')),
  lower(regexp_replace(trim(model), '\s+', ' ', 'g'))
);

create unique index if not exists phone_models_normalized_name_uidx
on public.phone_models (normalized_name)
where normalized_name is not null;

create or replace function public.normalize_phone_model_before_write()
returns trigger
language plpgsql
as $$
begin
  new.brand := regexp_replace(trim(coalesce(new.brand, '')), '\s+', ' ', 'g');
  new.model := regexp_replace(trim(coalesce(new.model, '')), '\s+', ' ', 'g');
  new.normalized_name := lower(regexp_replace(new.brand || ' ' || new.model, '\s+', ' ', 'g'));
  return new;
end;
$$;

drop trigger if exists normalize_phone_model_before_write on public.phone_models;
create trigger normalize_phone_model_before_write
before insert or update of brand, model, normalized_name
on public.phone_models
for each row execute function public.normalize_phone_model_before_write();
