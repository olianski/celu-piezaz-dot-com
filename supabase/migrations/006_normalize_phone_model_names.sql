-- Prevent duplicate phone models ignoring case and repeated whitespace.
create or replace function public.set_phone_model_normalized_name()
returns trigger language plpgsql as $$
begin
  new.normalized_name := trim(regexp_replace(
    translate(lower(trim(new.brand || ' ' || new.model)),
      'áàäâãåéèëêíìïîóòöôõúùüûñçýÿ',
      'aaaaaaeeeeiiiiooooouuuuncyy'),
    '\s+', ' ', 'g'));
  return new;
end;
$$;
drop trigger if exists phone_model_normalized_name_before_write on public.phone_models;
create trigger phone_model_normalized_name_before_write
before insert or update of brand, model, normalized_name on public.phone_models
for each row execute function public.set_phone_model_normalized_name();
create unique index if not exists phone_models_normalized_name_unique
  on public.phone_models (lower(regexp_replace(trim(normalized_name), '\s+', ' ', 'g')));
