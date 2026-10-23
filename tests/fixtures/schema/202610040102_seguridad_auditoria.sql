-- 02. Auditoría automática, integración Auth, integridad y RLS.
begin;
create function privado.es_miembro(p_empresa uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.usuarios_empresas m join public.usuarios u on u.id=m.usuario_id join public.empresas e on e.id=m.empresa_id where m.empresa_id=p_empresa and m.usuario_id=auth.uid() and m.activo and u.activo and e.activo)
$$;
create function privado.es_administrador(p_empresa uuid) returns boolean language sql stable security definer set search_path='' as $$
 select privado.es_miembro(p_empresa) and exists(select 1 from public.usuarios_empresas where empresa_id=p_empresa and usuario_id=auth.uid() and rol='administrador' and activo)
$$;
create function privado.ve_empresa(p_empresa uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.usuarios_empresas m join public.usuarios u on u.id=m.usuario_id join public.empresas e on e.id=m.empresa_id where m.empresa_id=p_empresa and m.usuario_id=auth.uid() and m.activo and u.activo and (e.activo or m.rol='administrador'))
$$;
create function privado.gestiona_equipo(p_equipo uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.equipos e join public.areas a on a.id=e.area_id where e.id=p_equipo and e.activo and a.activo and privado.es_miembro(e.empresa_id) and (privado.es_administrador(e.empresa_id) or exists(select 1 from public.miembros_equipo m where m.equipo_id=e.id and m.usuario_id=auth.uid() and m.activo and m.rol='lider')))
$$;
create function privado.ve_equipo(p_equipo uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.equipos e where e.id=p_equipo and privado.es_miembro(e.empresa_id) and (privado.es_administrador(e.empresa_id) or exists(select 1 from public.miembros_equipo m where m.equipo_id=e.id and m.usuario_id=auth.uid() and m.activo)))
$$;
create function privado.ve_tablero(p_tablero uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.tableros b where b.id=p_tablero and privado.es_miembro(b.empresa_id) and (privado.es_administrador(b.empresa_id) or privado.gestiona_equipo(b.equipo_id) or exists(select 1 from public.participantes_tablero p join public.miembros_equipo m using(empresa_id,equipo_id,usuario_id) where p.tablero_id=b.id and p.usuario_id=auth.uid() and m.activo)))
$$;
create function privado.ve_tarea(p_tarea uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.tareas t where t.id=p_tarea and privado.ve_tablero(t.tablero_id))
$$;
create function privado.trabaja_tarea(p_tarea uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.tareas t join public.tableros b on b.id=t.tablero_id where t.id=p_tarea and b.estado='activo' and t.estado<>'finalizado' and privado.ve_tarea(t.id) and (privado.gestiona_equipo(t.equipo_id) or t.responsable_id=auth.uid() or exists(select 1 from public.subtareas s where s.tarea_id=t.id and s.responsable_id=auth.uid() and s.estado<>'finalizado')))
$$;
create function privado.ve_usuario(p_usuario uuid) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid()=p_usuario or exists(select 1 from public.usuarios_empresas m where m.usuario_id=p_usuario and m.activo and privado.es_administrador(m.empresa_id)) or exists(select 1 from public.miembros_equipo m where m.usuario_id=p_usuario and m.activo and privado.ve_equipo(m.equipo_id))
$$;

create function privado.sellar_auditoria() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_op='INSERT' then
   new.usuario_creacion:=auth.uid(); new.fecha_creacion:=now();
 else
   new.usuario_creacion:=old.usuario_creacion; new.fecha_creacion:=old.fecha_creacion;
 end if;
 new.usuario_modificacion:=auth.uid(); new.fecha_modificacion:=now();
 return new;
end $$;
create function privado.registrar_auditoria() returns trigger language plpgsql security definer set search_path='' as $$
declare anterior jsonb; nuevo jsonb; fila jsonb; empresa uuid;
begin
 if tg_op<>'INSERT' then anterior:=to_jsonb(old); end if;
 if tg_op<>'DELETE' then nuevo:=to_jsonb(new); end if;
 fila:=coalesce(nuevo,anterior);
 empresa:=case when tg_table_name='empresas' then (fila->>'id')::uuid else (fila->>'empresa_id')::uuid end;
 insert into public.historial_auditoria(empresa_id,tabla,registro_id,operacion,datos_anteriores,datos_nuevos,usuario_creacion,usuario_modificacion)
 values(empresa,tg_table_name,(fila->>'id')::uuid,tg_op,anterior,nuevo,auth.uid(),auth.uid());
 return null;
end $$;
do $$ declare nombre text; begin
 foreach nombre in array array['usuarios','empresas','usuarios_empresas','areas','equipos','miembros_equipo','tableros','participantes_tablero','tareas','subtareas','evidencias','comentarios_tarea','eventos_tarea','preferencias_usuario','notificaciones'] loop
   execute format('create trigger z_sellar_auditoria before insert or update on public.%I for each row execute function privado.sellar_auditoria()',nombre);
   execute format('create trigger registrar_auditoria after insert or update or delete on public.%I for each row execute function privado.registrar_auditoria()',nombre);
 end loop;
end $$;

create function privado.crear_perfil_auth() returns trigger language plpgsql security definer set search_path='' as $$
begin
 insert into public.usuarios(id,nombre_completo) values(new.id,left(coalesce(nullif(btrim(new.raw_user_meta_data->>'nombre_completo'),''),'Usuario'),120));
 insert into public.preferencias_usuario(usuario_id) values(new.id);
 return new;
end $$;
create trigger ohana_crear_usuario after insert on auth.users for each row execute function privado.crear_perfil_auth();
-- Usuarios que ya existían en Auth antes de instalar los scripts.
insert into public.usuarios(id,nombre_completo)
select id,left(coalesce(nullif(btrim(raw_user_meta_data->>'nombre_completo'),''),'Usuario'),120) from auth.users on conflict(id) do nothing;
insert into public.preferencias_usuario(usuario_id) select id from public.usuarios on conflict(usuario_id) do nothing;

create function privado.validar_trabajo() returns trigger language plpgsql set search_path='' as $$
declare tablero public.tableros; tarea public.tareas; zona text;
begin
 if tg_table_name='tareas' then
   select * into strict tablero from public.tableros where id=new.tablero_id;
   if tg_op='UPDATE' and (new.empresa_id,new.equipo_id,new.tablero_id) is distinct from (old.empresa_id,old.equipo_id,old.tablero_id) then raise exception 'La pertenencia de la tarea no se puede cambiar'; end if;
   new.empresa_id:=tablero.empresa_id; new.equipo_id:=tablero.equipo_id;
   if tg_op='UPDATE' then new.version:=old.version+1; else new.version:=1; end if;
   select zona_horaria into zona from public.empresas where id=new.empresa_id;
   if (new.fecha_fin at time zone zona)::date-(new.fecha_inicio at time zone zona)::date+1>14 then raise exception 'Máximo 14 días inclusivos por tarea'; end if;
 else
   select * into strict tarea from public.tareas where id=new.tarea_id;
   if tg_op='UPDATE' and (new.empresa_id,new.tablero_id,new.tarea_id) is distinct from (old.empresa_id,old.tablero_id,old.tarea_id) then raise exception 'La pertenencia de la subtarea no se puede cambiar'; end if;
   new.empresa_id:=tarea.empresa_id; new.tablero_id:=tarea.tablero_id;
   select * into strict tablero from public.tableros where id=tarea.tablero_id;
   if tarea.estado='finalizado' then raise exception 'Reabre la tarea antes de editar subtareas'; end if;
 end if;
 if tablero.estado<>'activo' then raise exception 'Reabre el tablero'; end if;
 if not exists(select 1 from public.equipos e join public.areas a on a.id=e.area_id join public.empresas c on c.id=e.empresa_id where e.id=tablero.equipo_id and e.activo and a.activo and c.activo) then raise exception 'Empresa, área o equipo inactivo'; end if;
 if not exists(select 1 from public.participantes_tablero p join public.miembros_equipo m using(empresa_id,equipo_id,usuario_id) join public.usuarios_empresas ue on ue.empresa_id=p.empresa_id and ue.usuario_id=p.usuario_id join public.usuarios u on u.id=p.usuario_id where p.tablero_id=tablero.id and p.usuario_id=new.responsable_id and m.activo and ue.activo and u.activo) then raise exception 'Responsable no activo o ajeno al tablero'; end if;
 if new.estado='finalizado' then
   new.fecha_finalizacion:=case when tg_op='UPDATE' and old.estado='finalizado' then old.fecha_finalizacion else now() end;
   new.usuario_finalizacion:=case when tg_op='UPDATE' and old.estado='finalizado' then old.usuario_finalizacion else coalesce(auth.uid(),new.usuario_finalizacion) end;
 else new.fecha_finalizacion:=null; new.usuario_finalizacion:=null;
 end if;
 return new;
end $$;
create trigger a_validar_trabajo before insert or update on public.tareas for each row execute function privado.validar_trabajo();
create trigger a_validar_trabajo before insert or update on public.subtareas for each row execute function privado.validar_trabajo();

create function privado.validar_lider() returns trigger language plpgsql set search_path='' as $$
declare equipo uuid;
begin
 if tg_table_name='equipos' then equipo:=new.id;
 elsif tg_op='DELETE' then equipo:=old.equipo_id;
 else equipo:=new.equipo_id; end if;
 if exists(select 1 from public.equipos where id=equipo and activo) and (select count(*) from public.miembros_equipo m join public.usuarios_empresas ue using(empresa_id,usuario_id) join public.usuarios u on u.id=m.usuario_id where m.equipo_id=equipo and m.activo and m.rol='lider' and ue.activo and u.activo)<>1 then raise exception 'Un equipo activo necesita exactamente un líder activo'; end if;
 return null;
end $$;
create constraint trigger comprobar_lider after insert or update on public.equipos deferrable initially deferred for each row execute function privado.validar_lider();
create constraint trigger comprobar_lider after insert or update or delete on public.miembros_equipo deferrable initially deferred for each row execute function privado.validar_lider();

-- Solo lectura directa. Todas las escrituras cliente pasan por RPC autorizadas.
grant usage on schema public,privado to authenticated;
grant select on public.usuarios,public.empresas,public.usuarios_empresas,public.areas,public.equipos,public.miembros_equipo,public.tableros,public.participantes_tablero,public.tareas,public.subtareas,public.evidencias,public.comentarios_tarea,public.eventos_tarea,public.preferencias_usuario,public.notificaciones,public.historial_auditoria to authenticated;
create policy usuarios_lectura on public.usuarios for select to authenticated using(privado.ve_usuario(id));
create policy empresas_lectura on public.empresas for select to authenticated using(privado.ve_empresa(id));
create policy usuarios_empresas_lectura on public.usuarios_empresas for select to authenticated using((usuario_id=auth.uid() and privado.ve_empresa(empresa_id)) or privado.es_administrador(empresa_id));
create policy areas_lectura on public.areas for select to authenticated using(privado.es_miembro(empresa_id) and (privado.es_administrador(empresa_id) or exists(select 1 from public.equipos e where e.area_id=areas.id and privado.ve_equipo(e.id))));
create policy equipos_lectura on public.equipos for select to authenticated using(privado.ve_equipo(id));
create policy miembros_equipo_lectura on public.miembros_equipo for select to authenticated using(privado.ve_equipo(equipo_id));
create policy tableros_lectura on public.tableros for select to authenticated using(privado.ve_tablero(id));
create policy participantes_lectura on public.participantes_tablero for select to authenticated using(privado.ve_tablero(tablero_id));
create policy tareas_lectura on public.tareas for select to authenticated using(privado.ve_tarea(id));
create policy subtareas_lectura on public.subtareas for select to authenticated using(privado.ve_tarea(tarea_id));
create policy evidencias_lectura on public.evidencias for select to authenticated using(privado.ve_tarea(tarea_id));
create policy comentarios_lectura on public.comentarios_tarea for select to authenticated using(privado.ve_tarea(tarea_id));
create policy eventos_lectura on public.eventos_tarea for select to authenticated using(privado.ve_tarea(tarea_id));
create policy preferencias_lectura on public.preferencias_usuario for select to authenticated using(usuario_id=auth.uid());
create policy notificaciones_lectura on public.notificaciones for select to authenticated using(usuario_id=auth.uid() and privado.es_miembro(empresa_id));
create policy historial_lectura on public.historial_auditoria for select to authenticated using(privado.es_administrador(empresa_id));
-- Helpers: solo los predicados necesarios para RLS son ejecutables por clientes.
revoke all on all functions in schema privado from public,anon,authenticated;
grant execute on function privado.es_miembro(uuid),privado.es_administrador(uuid),privado.ve_empresa(uuid),privado.gestiona_equipo(uuid),privado.ve_equipo(uuid),privado.ve_tablero(uuid),privado.ve_tarea(uuid),privado.trabaja_tarea(uuid),privado.ve_usuario(uuid) to authenticated;
commit;
