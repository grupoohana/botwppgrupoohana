begin;
create function public.wa_login_gate(p_key text) returns void language plpgsql security definer set search_path='' as $$
begin
 if p_key !~ '^[a-f0-9]{64}$' then raise exception 'Identificador inválido'; end if;
 perform privado.wa_rate('auth:'||p_key,10,900);
end $$;
create function public.wa_companies() returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object('id',e.id,'nombre',e.nombre,'rol',m.rol)),'[]'::jsonb) from public.usuarios_empresas m join public.empresas e on e.id=m.empresa_id and e.activo join public.usuarios u on u.id=m.usuario_id and u.activo where m.usuario_id=auth.uid() and m.activo
$$;
revoke all on function public.wa_login_gate(text),public.wa_companies() from public,anon,authenticated;
grant execute on function public.wa_login_gate(text),public.wa_companies() to service_role;
grant execute on function public.wa_companies() to authenticated;
commit;
