-- Permisos por empresa, equipo y tarea. Mantiene los administradores existentes.
begin;

-- Reconoce el rol de quienes ya lideran equipos, sin retirar administradores.
update public.usuarios_empresas ue set rol='lider'
where ue.rol='miembro' and exists(select 1 from public.miembros_equipo me where me.empresa_id=ue.empresa_id and me.usuario_id=ue.usuario_id and me.rol='lider' and me.activo);

create or replace function privado.gestiona_tarea(p_tarea uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.tareas t where t.id=p_tarea and privado.ve_tarea(t.id)
 and (privado.gestiona_equipo(t.equipo_id) or t.responsable_id=auth.uid() or t.usuario_creacion=auth.uid()))
$$;
create or replace function privado.trabaja_tarea(p_tarea uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.tareas t join public.tableros b on b.id=t.tablero_id
 where t.id=p_tarea and b.estado='activo' and t.estado<>'finalizado' and privado.ve_tarea(t.id)
 and (privado.gestiona_tarea(t.id) or exists(select 1 from public.subtareas s where s.tarea_id=t.id and s.responsable_id=auth.uid() and s.estado<>'finalizado')))
$$;

-- Un líder puede consultar los usuarios activos de su empresa para agregarlos
-- a sus equipos. Esta lectura no otorga permisos de gestión en otros equipos.
create or replace function privado.lider_en_empresa(p_empresa uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select privado.es_miembro(p_empresa) and exists(select 1 from public.miembros_equipo m join public.equipos e on e.id=m.equipo_id
 where m.empresa_id=p_empresa and m.usuario_id=auth.uid() and m.rol='lider' and m.activo and e.activo)
$$;
drop policy usuarios_empresas_lectura on public.usuarios_empresas;
create policy usuarios_empresas_lectura on public.usuarios_empresas for select to authenticated
 using((usuario_id=auth.uid() and privado.ve_empresa(empresa_id)) or privado.es_administrador(empresa_id) or (activo and privado.lider_en_empresa(empresa_id)));
create or replace function privado.ve_usuario(p_usuario uuid) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid()=p_usuario or exists(select 1 from public.usuarios_empresas m where m.usuario_id=p_usuario and m.activo and
 (privado.es_administrador(m.empresa_id) or privado.lider_en_empresa(m.empresa_id)))
 or exists(select 1 from public.miembros_equipo m where m.usuario_id=p_usuario and m.activo and privado.ve_equipo(m.equipo_id))
$$;

revoke all on function privado.gestiona_tarea(uuid),privado.lider_en_empresa(uuid) from public,anon;
grant execute on function privado.gestiona_tarea(uuid),privado.lider_en_empresa(uuid) to authenticated;

create or replace function public.asignar_usuario_empresa(p_empresa uuid,p_usuario uuid,p_rol public.rol_empresa default 'miembro',p_activo boolean default true) returns public.usuarios_empresas
language plpgsql security definer set search_path='' as $$
declare resultado public.usuarios_empresas;
begin
 perform privado.exigir_administrador(p_empresa);
 if not exists(select 1 from public.usuarios where id=p_usuario and activo) then raise exception 'Crea primero el usuario en Authentication'; end if;
 if exists(select 1 from public.usuarios_empresas where empresa_id=p_empresa and usuario_id=p_usuario and rol='administrador' and activo) and (not p_activo or p_rol<>'administrador') and (select count(*) from public.usuarios_empresas where empresa_id=p_empresa and rol='administrador' and activo)<2 then raise exception 'La empresa necesita al menos un administrador'; end if;
 if (not p_activo or p_rol<>'lider') and exists(select 1 from public.miembros_equipo where empresa_id=p_empresa and usuario_id=p_usuario and rol='lider' and activo) then raise exception 'Asigna primero otro lider a sus equipos'; end if;
 if not p_activo and exists(select 1 from public.miembros_equipo where empresa_id=p_empresa and usuario_id=p_usuario and activo) then raise exception 'Retira primero al usuario de sus equipos'; end if;
 insert into public.usuarios_empresas(empresa_id,usuario_id,rol,activo) values(p_empresa,p_usuario,p_rol,p_activo)
 on conflict(empresa_id,usuario_id) do update set rol=excluded.rol,activo=excluded.activo returning * into resultado;
 return resultado;
end $$;

create or replace function public.guardar_equipo(p_empresa uuid,p_area uuid,p_nombre text,p_lider uuid,p_descripcion text default '',p_id uuid default null,p_activo boolean default true) returns public.equipos
language plpgsql security definer set search_path='' as $$
declare resultado public.equipos;
begin
 perform privado.exigir_administrador(p_empresa);
 if not (p_id is not null and exists(select 1 from public.miembros_equipo where equipo_id=p_id and usuario_id=p_lider and rol='lider' and activo)) and not exists(select 1 from public.usuarios_empresas m join public.usuarios u on u.id=m.usuario_id where m.empresa_id=p_empresa and m.usuario_id=p_lider and m.rol='lider' and m.activo and u.activo) then raise exception 'Líder ajeno o no activo'; end if;
 if not exists(select 1 from public.areas where id=p_area and empresa_id=p_empresa and (activo or not p_activo)) then raise exception 'Área inválida'; end if;
 if p_id is not null and exists(select 1 from public.equipos where id=p_id and area_id<>p_area) and exists(select 1 from public.tableros where equipo_id=p_id) then raise exception 'No cambies el área de un equipo con tableros'; end if;
 if not p_activo and exists(select 1 from public.tableros where equipo_id=p_id and estado='activo') then raise exception 'Finaliza primero los tableros'; end if;
 if p_id is null then insert into public.equipos(empresa_id,area_id,nombre,descripcion,activo) values(p_empresa,p_area,btrim(p_nombre),p_descripcion,p_activo) returning * into resultado;
 else update public.equipos set area_id=p_area,nombre=btrim(p_nombre),descripcion=p_descripcion,activo=p_activo where id=p_id and empresa_id=p_empresa returning * into strict resultado; end if;
 update public.miembros_equipo set rol='miembro' where equipo_id=resultado.id and rol='lider';
 insert into public.miembros_equipo(empresa_id,equipo_id,usuario_id,rol) values(p_empresa,resultado.id,p_lider,'lider') on conflict(empresa_id,equipo_id,usuario_id) do update set rol='lider',activo=true;
 -- El nuevo líder participa también en los tableros existentes.
 insert into public.participantes_tablero(empresa_id,equipo_id,tablero_id,usuario_id) select p_empresa,resultado.id,id,p_lider from public.tableros where equipo_id=resultado.id on conflict do nothing;
 return resultado;
end $$;

create or replace function public.asignar_miembro_equipo(p_equipo uuid,p_usuario uuid,p_activo boolean default true) returns public.miembros_equipo
language plpgsql security definer set search_path='' as $$
declare equipo public.equipos; resultado public.miembros_equipo;
begin
 select * into strict equipo from public.equipos where id=p_equipo;
 perform privado.bloquear_empresa(equipo.empresa_id);
 if not privado.gestiona_equipo(p_equipo) then raise exception 'Solo administrador o lider de este equipo'; end if;
 if not p_activo and not privado.es_administrador(equipo.empresa_id) then raise exception 'Solo administrador puede retirar miembros'; end if;
 if not exists(select 1 from public.usuarios_empresas m join public.usuarios u on u.id=m.usuario_id where m.empresa_id=equipo.empresa_id and m.usuario_id=p_usuario and m.activo and u.activo) then raise exception 'Usuario ajeno o inactivo'; end if;
 if not p_activo and exists(select 1 from public.participantes_tablero where equipo_id=p_equipo and usuario_id=p_usuario) then raise exception 'Retira primero al participante de sus tableros'; end if;
 if not p_activo and exists(select 1 from public.miembros_equipo where equipo_id=p_equipo and usuario_id=p_usuario and rol='lider') then raise exception 'Asigna antes otro líder'; end if;
 insert into public.miembros_equipo(empresa_id,equipo_id,usuario_id,activo) values(equipo.empresa_id,p_equipo,p_usuario,p_activo) on conflict(empresa_id,equipo_id,usuario_id) do update set activo=excluded.activo returning * into resultado;
 return resultado;
end $$;

create or replace function public.guardar_tarea(p_tablero uuid,p_titulo text,p_descripcion text,p_responsable uuid,p_fecha_inicio timestamptz,p_fecha_fin timestamptz,p_criticidad public.criticidad_trabajo,p_id uuid default null,p_version integer default null) returns public.tareas
language plpgsql security definer set search_path='' as $$
declare tablero public.tableros; resultado public.tareas;
begin
 select * into strict tablero from public.tableros where id=p_tablero;
 perform privado.bloquear_empresa(tablero.empresa_id);
 if not privado.ve_tablero(p_tablero) then raise exception 'No administras este tablero'; end if;
 if p_id is null then
   insert into public.tareas(empresa_id,equipo_id,tablero_id,titulo,descripcion,responsable_id,fecha_inicio,fecha_fin,criticidad) values(tablero.empresa_id,tablero.equipo_id,p_tablero,btrim(p_titulo),p_descripcion,p_responsable,p_fecha_inicio,p_fecha_fin,p_criticidad) returning * into resultado;
 else
   select * into strict resultado from public.tareas where id=p_id and tablero_id=p_tablero for update;
   if not privado.gestiona_tarea(resultado.id) then raise exception 'No puedes editar esta tarea'; end if;
   if resultado.version is distinct from p_version then raise exception 'Versión obsoleta: recarga la tarea'; end if;
   if resultado.estado='finalizado' then raise exception 'Reabre la tarea'; end if;
   update public.tareas set titulo=btrim(p_titulo),descripcion=p_descripcion,responsable_id=p_responsable,fecha_inicio=p_fecha_inicio,fecha_fin=p_fecha_fin,criticidad=p_criticidad where id=p_id returning * into resultado;
 end if;
 perform privado.evento(resultado.id,case when p_id is null then 'tarea_creada' else 'tarea_modificada' end);
 return resultado;
end $$;

create or replace function public.cambiar_estado_tarea(p_tarea uuid,p_version integer,p_estado public.estado_trabajo,p_comentario text default null) returns public.tareas
language plpgsql security definer set search_path='' as $$
declare resultado public.tareas; anterior public.estado_trabajo;
begin
 select * into strict resultado from public.tareas where id=p_tarea;
 perform privado.bloquear_empresa(resultado.empresa_id);
 select * into strict resultado from public.tareas where id=p_tarea for update;
 if not privado.ve_tarea(p_tarea) or resultado.version is distinct from p_version then raise exception 'Sin acceso o versión obsoleta'; end if;
 anterior:=resultado.estado;
 if anterior=p_estado then raise exception 'El estado ya es el solicitado'; end if;
 if not privado.gestiona_tarea(p_tarea) then raise exception 'No puedes cambiar esta tarea'; end if;
 update public.tareas set estado=p_estado where id=p_tarea returning * into resultado;
 if nullif(btrim(p_comentario),'') is not null then insert into public.comentarios_tarea(empresa_id,tarea_id,contenido) values(resultado.empresa_id,p_tarea,btrim(p_comentario)); end if;
 perform privado.evento(p_tarea,'estado_modificado',jsonb_build_object('anterior',anterior,'nuevo',p_estado));
 return resultado;
end $$;

create or replace function public.guardar_subtarea(p_tarea uuid,p_version integer,p_titulo text,p_responsable uuid,p_fecha_inicio timestamptz,p_fecha_fin timestamptz,p_criticidad public.criticidad_trabajo,p_estado public.estado_trabajo default 'por_hacer',p_id uuid default null) returns public.tareas
language plpgsql security definer set search_path='' as $$
declare tarea public.tareas; anterior public.subtareas; resultado public.subtareas;
begin
 select * into strict tarea from public.tareas where id=p_tarea;
 perform privado.bloquear_empresa(tarea.empresa_id);
 select * into strict tarea from public.tareas where id=p_tarea for update;
 if not privado.ve_tarea(p_tarea) or tarea.version is distinct from p_version then raise exception 'Sin acceso o versión obsoleta'; end if;
 if p_id is not null then select * into strict anterior from public.subtareas where id=p_id and tarea_id=p_tarea; end if;
 if not privado.gestiona_tarea(p_tarea) and (p_id is null or anterior.responsable_id<>auth.uid() or (anterior.titulo,anterior.responsable_id,anterior.fecha_inicio,anterior.fecha_fin,anterior.criticidad) is distinct from (p_titulo,p_responsable,p_fecha_inicio,p_fecha_fin,p_criticidad)) then raise exception 'Solo puedes cambiar el estado de tu subtarea'; end if;
 if p_id is null then insert into public.subtareas(empresa_id,tablero_id,tarea_id,titulo,responsable_id,fecha_inicio,fecha_fin,criticidad,estado) values(tarea.empresa_id,tarea.tablero_id,p_tarea,btrim(p_titulo),p_responsable,p_fecha_inicio,p_fecha_fin,p_criticidad,p_estado) returning * into resultado;
 else update public.subtareas set titulo=btrim(p_titulo),responsable_id=p_responsable,fecha_inicio=p_fecha_inicio,fecha_fin=p_fecha_fin,criticidad=p_criticidad,estado=p_estado where id=p_id returning * into resultado; end if;
 update public.tareas set fecha_modificacion=now() where id=p_tarea returning * into tarea;
 perform privado.evento(p_tarea,'subtarea_guardada',jsonb_build_object('subtarea_id',resultado.id,'estado',resultado.estado));
 return tarea;
end $$;

commit;
