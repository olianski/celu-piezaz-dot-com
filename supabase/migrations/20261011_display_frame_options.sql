-- Display frame options: preserve existing inventory on the default no-frame products.
-- Stage in feature branch only; do not apply to production until reviewed.
BEGIN;
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS frame_type text;
ALTER TABLE public.products DROP CONSTRAINT IF EXISTS products_frame_type_check;
ALTER TABLE public.products ADD CONSTRAINT products_frame_type_check
  CHECK (frame_type IS NULL OR frame_type IN ('sin_marco', 'con_marco'));

DROP INDEX IF EXISTS public.products_unique_catalog_key_uidx;

UPDATE public.products p
SET frame_type = 'sin_marco',
    display_name = CASE WHEN p.display_name ILIKE '%sin marco%' THEN p.display_name ELSE p.display_name || ' · Sin marco' END,
    normalized_search = CASE WHEN p.normalized_search ILIKE '%sin marco%' THEN p.normalized_search ELSE p.normalized_search || ' sin marco' END
FROM public.part_types t
WHERE t.id = p.part_type_id
  AND (lower(t.name) LIKE '%pantalla%' OR lower(t.name) LIKE '%display%')
  AND p.frame_type IS NULL;

INSERT INTO public.products
  (phone_model_id, part_type_id, part_variant_id, frame_type, display_name, normalized_search, active)
SELECT p.phone_model_id, p.part_type_id, p.part_variant_id, 'con_marco',
       regexp_replace(p.display_name, ' · Sin marco$', '', 'i') || ' · Con marco',
       regexp_replace(p.normalized_search, ' sin marco$', '', 'i') || ' con marco',
       p.active
FROM public.products p
JOIN public.part_types t ON t.id = p.part_type_id
WHERE (lower(t.name) LIKE '%pantalla%' OR lower(t.name) LIKE '%display%')
  AND p.frame_type = 'sin_marco'
  AND NOT EXISTS (
    SELECT 1 FROM public.products x
    WHERE x.phone_model_id = p.phone_model_id
      AND x.part_type_id = p.part_type_id
      AND x.part_variant_id IS NOT DISTINCT FROM p.part_variant_id
      AND x.frame_type = 'con_marco'
  );

CREATE UNIQUE INDEX products_unique_catalog_key_uidx
  ON public.products (
    phone_model_id, part_type_id,
    COALESCE(part_variant_id, '00000000-0000-0000-0000-000000000000'::uuid),
    COALESCE(frame_type, '')
  );
COMMIT;
