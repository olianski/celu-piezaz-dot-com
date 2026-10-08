-- Celu Piezaz Dot Com — carga inicial del catálogo base.
insert into public.phone_models (brand, model, normalized_name)
values
('Samsung','Galaxy A15','samsung galaxy a15'),
('Samsung','Galaxy A24','samsung galaxy a24'),
('Xiaomi','Redmi Note 12','xiaomi redmi note 12'),
('Motorola','Moto G54','motorola moto g54'),
('Apple','iPhone 11','apple iphone 11')
on conflict (brand,model) do nothing;

insert into public.part_types (name)
values
('Pantalla'),('Batería'),('Puerto de carga'),('Cámara'),('Tapa trasera'),
('Parlante'),('Auricular'),('Micrófono'),('Flex'),('Marco / Chasis')
on conflict (name) do nothing;

insert into public.part_variants (part_type_id,name)
select pt.id, v.name
from public.part_types pt
cross join (values
('Pantalla','Incell'),('Pantalla','OLED'),('Pantalla','Original'),
('Batería','Compatible'),('Batería','Alta capacidad'),('Batería','Original'),
('Puerto de carga','Compatible'),('Puerto de carga','Original'),
('Cámara','Trasera'),('Cámara','Frontal'),('Cámara','Original'),
('Tapa trasera','Compatible'),('Tapa trasera','Original'),
('Parlante','Compatible'),('Parlante','Original'),
('Auricular','Compatible'),('Auricular','Original'),
('Micrófono','Compatible'),('Micrófono','Original'),
('Flex','Encendido'),('Flex','Volumen'),('Flex','Carga'),('Flex','Otro'),
('Marco / Chasis','Compatible'),('Marco / Chasis','Original')
) as v(part_type, name)
where pt.name=v.part_type
on conflict (part_type_id,name) do nothing;

insert into public.products(phone_model_id,part_type_id,part_variant_id,display_name,normalized_search)
select pm.id,pt.id,pv.id,
       pm.brand||' '||pm.model||' — '||pt.name||' — '||pv.name,
       lower(pm.brand||' '||pm.model||' '||pt.name||' '||pv.name)
from public.phone_models pm
cross join public.part_types pt
join public.part_variants pv on pv.part_type_id=pt.id
where not exists (
  select 1 from public.products p
  where p.phone_model_id=pm.id and p.part_type_id=pt.id and p.part_variant_id=pv.id
);
