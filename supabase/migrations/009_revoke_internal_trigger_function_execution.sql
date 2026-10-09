-- Keep trigger/helper functions inaccessible as public RPC endpoints.
begin;
revoke execute on function public.current_user_role() from public, anon;
grant execute on function public.current_user_role() to authenticated;

revoke execute on function public.guard_shop_lifecycle() from public, anon, authenticated;
revoke execute on function public.prevent_shop_self_approval() from public, anon, authenticated;
revoke execute on function public.normalize_phone_model_before_write() from public, anon, authenticated;
revoke execute on function public.set_phone_model_normalized_name() from public, anon, authenticated;
revoke execute on function public.handle_new_user() from public, anon, authenticated;
commit;
