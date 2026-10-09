-- Prevent duplicate phone models regardless of capitalization or repeated spaces.
create or replace function public.normalize_phone_model_name()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.brand := trim(regexp_replace(coalesce(new.brand, ''), '[[:space:]]+', ' ', 'g'));
  new.model := trim(regexp_replace(coalesce(new.model, ''), '[[:space:]]+', ' ', 'g'));
  new.normalized_name := lower(trim(regexp_replace(new.brand || ' ' || new.model, '[[:space:]]+', ' ', 'g')));
  return new;
end;
$$;

drop trigger if exists normalize_phone_model_name_before_write on public.phone_models;
create trigger normalize_phone_model_name_before_write
before insert or update of brand, model, normalized_name on public.phone_models
for each row execute function public.normalize_phone_model_name();

create unique index if not exists phone_models_normalized_name_unique
on public.phone_models (normalized_name);

update public.phone_models
set brand = trim(regexp_replace(brand, '[[:space:]]+', ' ', 'g')),
    model = trim(regexp_replace(model, '[[:space:]]+', ' ', 'g')),
    normalized_name = lower(trim(regexp_replace(brand || ' ' || model, '[[:space:]]+', ' ', 'g')));
