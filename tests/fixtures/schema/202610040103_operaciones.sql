-- 03. API de escritura: autorización, transacciones y versión de tareas.
begin;
create function privado.bloquear_empresa(p_empresa uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or not privado.es_miembro(p_empresa) then raise exception 'Empresa sin acceso'; end if;
 perform 1 from public.empresas where id=p_empresa for update;
 -- Se vuelve a comprobar después del bloqueo para evitar carreras con desactivación.
 if not privado.es_miembro(p_empresa) then raise exception 'Empresa sin acceso'; end if;
end $$;
create function privado.exigir_administrador(p_empresa uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 perform privado.bloquear_empresa(p_empresa);
 if not privado.es_administrador(p_empresa) then raise exception 'Solo administrador de esta empresa'; end if;
end $$;
create function privado.evento(p_tarea uuid,p_accion text,p_detalles jsonb default '{}') returns void language plpgsql security definer set search_path='' as $$
declare t public.tareas;
begin
 select * into strict t from public.tareas where id=p_tarea;
 insert into public.eventos_tarea(empresa_id,tarea_id,accion,detalles) values(t.empresa_id,t.id,p_accion,p_detalles);
end $$;

create function public.guardar_mi_perfil(p_nombre_completo text,p_nombre_usuario text default null,p_telefono text default null,p_cargo text default null,p_biografia text default null,p_ruta_foto text default null) returns public.usuarios
language plpgsql security definer set search_path='' as $$
declare resultado public.usuarios;
begin
 if auth.uid() is null or not exists(select 1 from public.usuarios where id=auth.uid() and activo) then raise exception 'Usuario no activo'; end if;
 if p_ruta_foto is not null and not exists(select 1 from storage.objects where bucket_id='fotos-perfil' and name=p_ruta_foto and (storage.foldername(name))[1]=auth.uid()::text) then raise exception 'Primero carga tu foto en tu carpeta de Storage'; end if;
 update public.usuarios set nombre_completo=btrim(p_nombre_completo),nombre_usuario=nullif(lower(btrim(p_nombre_usuario)),''),telefono=p_telefono,cargo=p_cargo,biografia=p_biografia,ruta_foto_perfil=p_ruta_foto where id=auth.uid() returning * into resultado;
 return resultado;
end $$;
create function public.guardar_preferencias(p_recordatorios boolean,p_avisos_revision boolean) returns public.preferencias_usuario
language plpgsql security definer set search_path='' as $$
declare resultado public.preferencias_usuario;
begin
 if auth.uid() is null then raise exception 'Inicia sesión'; end if;
 update public.preferencias_usuario set recordatorios=p_recordatorios,avisos_revision=p_avisos_revision where usuario_id=auth.uid() returning * into strict resultado;
 return resultado;
end $$;
create function public.guardar_empresa(p_nombre text,p_identificador text,p_zona_horaria text default 'America/Bogota',p_id uuid default null,p_activo boolean default true) returns public.empresas
language plpgsql security definer set search_path='' as $$
declare resultado public.empresas;
begin
 if not exists(select 1 from public.usuarios where id=auth.uid() and activo) then raise exception 'Inicia sesión con un perfil activo'; end if;
 if not exists(select 1 from pg_catalog.pg_timezone_names where name=p_zona_horaria) then raise exception 'Zona horaria inválida'; end if;
 if p_id is null then
   if not exists(select 1 from public.usuarios_empresas where usuario_id=auth.uid() and privado.es_administrador(empresa_id)) then raise exception 'Solo un administrador puede crear empresas; la primera se inicializa desde SQL Editor'; end if;
   insert into public.empresas(nombre,identificador,zona_horaria,activo) values(btrim(p_nombre),p_identificador,p_zona_horaria,true) returning * into resultado;
   insert into public.usuarios_empresas(empresa_id,usuario_id,rol) values(resultado.id,auth.uid(),'administrador');
 else
   -- Permite al administrador reactivar su empresa; usuarios desactivados no pueden hacerlo.
   perform 1 from public.empresas where id=p_id for update;
   if not exists(select 1 from public.usuarios_empresas where empresa_id=p_id and usuario_id=auth.uid() and rol='administrador' and activo) then raise exception 'Solo administrador'; end if;
   update public.empresas set nombre=btrim(p_nombre),identificador=p_identificador,zona_horaria=p_zona_horaria,activo=p_activo where id=p_id returning * into strict resultado;
 end if;
 return resultado;
end $$;
create function public.asignar_usuario_empresa(p_empresa uuid,p_usuario uuid,p_rol public.rol_empresa default 'miembro',p_activo boolean default true) returns public.usuarios_empresas
language plpgsql security definer set search_path='' as $$
declare resultado public.usuarios_empresas;
begin
 perform privado.exigir_administrador(p_empresa);
 if not exists(select 1 from public.usuarios where id=p_usuario and activo) then raise exception 'Crea primero el usuario en Authentication'; end if;
 if exists(select 1 from public.usuarios_empresas where empresa_id=p_empresa and usuario_id=p_usuario and rol='administrador' and activo) and (not p_activo or p_rol<>'administrador') and (select count(*) from public.usuarios_empresas where empresa_id=p_empresa and rol='administrador' and activo)<2 then raise exception 'La empresa necesita al menos un administrador'; end if;
 if not p_activo and exists(select 1 from public.miembros_equipo where empresa_id=p_empresa and usuario_id=p_usuario and activo) then raise exception 'Retira primero al usuario de sus equipos'; end if;
 insert into public.usuarios_empresas(empresa_id,usuario_id,rol,activo) values(p_empresa,p_usuario,p_rol,p_activo)
 on conflict(empresa_id,usuario_id) do update set rol=excluded.rol,activo=excluded.activo returning * into resultado;
 return resultado;
end $$;
create function public.guardar_area(p_empresa uuid,p_nombre text,p_descripcion text default '',p_id uuid default null,p_activo boolean default true) returns public.areas
language plpgsql security definer set search_path='' as $$
declare resultado public.areas;
begin
 perform privado.exigir_administrador(p_empresa);
 if not p_activo and exists(select 1 from public.equipos where area_id=p_id and activo) then raise exception 'Desactiva primero los equipos del área'; end if;
 if p_id is null then insert into public.areas(empresa_id,nombre,descripcion,activo) values(p_empresa,btrim(p_nombre),p_descripcion,p_activo) returning * into resultado;
 else update public.areas set nombre=btrim(p_nombre),descripcion=p_descripcion,activo=p_activo where id=p_id and empresa_id=p_empresa returning * into strict resultado; end if;
 return resultado;
end $$;
create function public.guardar_equipo(p_empresa uuid,p_area uuid,p_nombre text,p_lider uuid,p_descripcion text default '',p_id uuid default null,p_activo boolean default true) returns public.equipos
language plpgsql security definer set search_path='' as $$
declare resultado public.equipos;
begin
 perform privado.exigir_administrador(p_empresa);
 if not exists(select 1 from public.usuarios_empresas m join public.usuarios u on u.id=m.usuario_id where m.empresa_id=p_empresa and m.usuario_id=p_lider and m.activo and u.activo) then raise exception 'Líder ajeno o no activo'; end if;
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
create function public.asignar_miembro_equipo(p_equipo uuid,p_usuario uuid,p_activo boolean default true) returns public.miembros_equipo
language plpgsql security definer set search_path='' as $$
declare equipo public.equipos; resultado public.miembros_equipo;
begin
 select * into strict equipo from public.equipos where id=p_equipo;
 perform privado.exigir_administrador(equipo.empresa_id);
 if not exists(select 1 from public.usuarios_empresas m join public.usuarios u on u.id=m.usuario_id where m.empresa_id=equipo.empresa_id and m.usuario_id=p_usuario and m.activo and u.activo) then raise exception 'Usuario ajeno o inactivo'; end if;
 if not p_activo and exists(select 1 from public.participantes_tablero where equipo_id=p_equipo and usuario_id=p_usuario) then raise exception 'Retira primero al participante de sus tableros'; end if;
 if not p_activo and exists(select 1 from public.miembros_equipo where equipo_id=p_equipo and usuario_id=p_usuario and rol='lider') then raise exception 'Asigna antes otro líder'; end if;
 insert into public.miembros_equipo(empresa_id,equipo_id,usuario_id,activo) values(equipo.empresa_id,p_equipo,p_usuario,p_activo) on conflict(empresa_id,equipo_id,usuario_id) do update set activo=excluded.activo returning * into resultado;
 return resultado;
end $$;
create function public.guardar_tablero(p_equipo uuid,p_nombre text,p_participantes uuid[],p_descripcion text default '',p_id uuid default null) returns public.tableros
language plpgsql security definer set search_path='' as $$
declare equipo public.equipos; resultado public.tableros; participantes uuid[];
begin
 select * into strict equipo from public.equipos where id=p_equipo;
 perform privado.bloquear_empresa(equipo.empresa_id);
 if not privado.gestiona_equipo(p_equipo) then raise exception 'No administras este equipo'; end if;
 select array_agg(distinct usuario) into participantes from (select unnest(coalesce(p_participantes,'{}'::uuid[])) usuario union select usuario_id from public.miembros_equipo where equipo_id=p_equipo and rol='lider' and activo) lista;
 if exists(select 1 from unnest(participantes) p where not exists(select 1 from public.miembros_equipo m join public.usuarios_empresas ue using(empresa_id,usuario_id) join public.usuarios u on u.id=m.usuario_id where m.equipo_id=p_equipo and m.usuario_id=p and m.activo and ue.activo and u.activo)) then raise exception 'Participante ajeno o inactivo'; end if;
 if p_id is null then insert into public.tableros(empresa_id,equipo_id,nombre,descripcion) values(equipo.empresa_id,p_equipo,btrim(p_nombre),p_descripcion) returning * into resultado;
 else update public.tableros set nombre=btrim(p_nombre),descripcion=p_descripcion where id=p_id and equipo_id=p_equipo and estado='activo' returning * into strict resultado; end if;
 if exists(select 1 from public.tareas where tablero_id=resultado.id and not (responsable_id=any(participantes))) or exists(select 1 from public.subtareas where tablero_id=resultado.id and not (responsable_id=any(participantes))) then raise exception 'Reasigna tareas y subtareas antes de retirar participantes'; end if;
 delete from public.participantes_tablero where tablero_id=resultado.id and not (usuario_id=any(participantes));
 insert into public.participantes_tablero(empresa_id,equipo_id,tablero_id,usuario_id) select resultado.empresa_id,p_equipo,resultado.id,unnest(participantes) on conflict do nothing;
 return resultado;
end $$;
create function public.cambiar_estado_tablero(p_tablero uuid,p_estado public.estado_tablero) returns public.tableros
language plpgsql security definer set search_path='' as $$
declare resultado public.tableros;
begin
 select * into strict resultado from public.tableros where id=p_tablero;
 perform privado.bloquear_empresa(resultado.empresa_id);
 if not privado.gestiona_equipo(resultado.equipo_id) then raise exception 'No administras este tablero'; end if;
 update public.tableros set estado=p_estado where id=p_tablero returning * into resultado;
 return resultado;
end $$;

create function public.guardar_tarea(p_tablero uuid,p_titulo text,p_descripcion text,p_responsable uuid,p_fecha_inicio timestamptz,p_fecha_fin timestamptz,p_criticidad public.criticidad_trabajo,p_id uuid default null,p_version integer default null) returns public.tareas
language plpgsql security definer set search_path='' as $$
declare tablero public.tableros; resultado public.tareas;
begin
 select * into strict tablero from public.tableros where id=p_tablero;
 perform privado.bloquear_empresa(tablero.empresa_id);
 if not privado.gestiona_equipo(tablero.equipo_id) then raise exception 'No administras este tablero'; end if;
 if p_id is null then
   insert into public.tareas(empresa_id,equipo_id,tablero_id,titulo,descripcion,responsable_id,fecha_inicio,fecha_fin,criticidad) values(tablero.empresa_id,tablero.equipo_id,p_tablero,btrim(p_titulo),p_descripcion,p_responsable,p_fecha_inicio,p_fecha_fin,p_criticidad) returning * into resultado;
 else
   select * into strict resultado from public.tareas where id=p_id and tablero_id=p_tablero for update;
   if resultado.version is distinct from p_version then raise exception 'Versión obsoleta: recarga la tarea'; end if;
   if resultado.estado='finalizado' then raise exception 'Reabre la tarea'; end if;
   update public.tareas set titulo=btrim(p_titulo),descripcion=p_descripcion,responsable_id=p_responsable,fecha_inicio=p_fecha_inicio,fecha_fin=p_fecha_fin,criticidad=p_criticidad where id=p_id returning * into resultado;
 end if;
 perform privado.evento(resultado.id,case when p_id is null then 'tarea_creada' else 'tarea_modificada' end);
 return resultado;
end $$;
create function public.cambiar_estado_tarea(p_tarea uuid,p_version integer,p_estado public.estado_trabajo,p_comentario text default null) returns public.tareas
language plpgsql security definer set search_path='' as $$
declare resultado public.tareas; anterior public.estado_trabajo;
begin
 select * into strict resultado from public.tareas where id=p_tarea;
 perform privado.bloquear_empresa(resultado.empresa_id);
 select * into strict resultado from public.tareas where id=p_tarea for update;
 if not privado.ve_tarea(p_tarea) or resultado.version is distinct from p_version then raise exception 'Sin acceso o versión obsoleta'; end if;
 anterior:=resultado.estado;
 if anterior=p_estado then raise exception 'El estado ya es el solicitado'; end if;
 if not privado.gestiona_equipo(resultado.equipo_id) and not (resultado.responsable_id=auth.uid() and ((anterior='por_hacer' and p_estado='en_curso') or (anterior='en_curso' and p_estado='en_revision'))) then raise exception 'Transición no permitida'; end if;
 update public.tareas set estado=p_estado where id=p_tarea returning * into resultado;
 if nullif(btrim(p_comentario),'') is not null then insert into public.comentarios_tarea(empresa_id,tarea_id,contenido) values(resultado.empresa_id,p_tarea,btrim(p_comentario)); end if;
 perform privado.evento(p_tarea,'estado_modificado',jsonb_build_object('anterior',anterior,'nuevo',p_estado));
 insert into public.notificaciones(empresa_id,usuario_id,tarea_id,titulo,contenido)
 select resultado.empresa_id,m.usuario_id,p_tarea,'Estado actualizado',resultado.titulo from public.usuarios_empresas m
 where m.empresa_id=resultado.empresa_id and m.activo and m.usuario_id<>auth.uid()
 and (m.usuario_id=resultado.responsable_id or (p_estado='en_revision' and (m.rol='administrador' or exists(select 1 from public.miembros_equipo me where me.equipo_id=resultado.equipo_id and me.usuario_id=m.usuario_id and me.activo and me.rol='lider'))))
 and (p_estado<>'en_revision' or exists(select 1 from public.preferencias_usuario p where p.usuario_id=m.usuario_id and p.avisos_revision));
 return resultado;
end $$;
create function public.guardar_subtarea(p_tarea uuid,p_version integer,p_titulo text,p_responsable uuid,p_fecha_inicio timestamptz,p_fecha_fin timestamptz,p_criticidad public.criticidad_trabajo,p_estado public.estado_trabajo default 'por_hacer',p_id uuid default null) returns public.tareas
language plpgsql security definer set search_path='' as $$
declare tarea public.tareas; anterior public.subtareas; resultado public.subtareas;
begin
 select * into strict tarea from public.tareas where id=p_tarea;
 perform privado.bloquear_empresa(tarea.empresa_id);
 select * into strict tarea from public.tareas where id=p_tarea for update;
 if not privado.ve_tarea(p_tarea) or tarea.version is distinct from p_version then raise exception 'Sin acceso o versión obsoleta'; end if;
 if p_id is not null then select * into strict anterior from public.subtareas where id=p_id and tarea_id=p_tarea; end if;
 if not privado.gestiona_equipo(tarea.equipo_id) and (p_id is null or anterior.responsable_id<>auth.uid() or (anterior.titulo,anterior.responsable_id,anterior.fecha_inicio,anterior.fecha_fin,anterior.criticidad) is distinct from (p_titulo,p_responsable,p_fecha_inicio,p_fecha_fin,p_criticidad)) then raise exception 'Solo puedes cambiar el estado de tu subtarea'; end if;
 if p_id is null then insert into public.subtareas(empresa_id,tablero_id,tarea_id,titulo,responsable_id,fecha_inicio,fecha_fin,criticidad,estado) values(tarea.empresa_id,tarea.tablero_id,p_tarea,btrim(p_titulo),p_responsable,p_fecha_inicio,p_fecha_fin,p_criticidad,p_estado) returning * into resultado;
 else update public.subtareas set titulo=btrim(p_titulo),responsable_id=p_responsable,fecha_inicio=p_fecha_inicio,fecha_fin=p_fecha_fin,criticidad=p_criticidad,estado=p_estado where id=p_id returning * into resultado; end if;
 update public.tareas set fecha_modificacion=now() where id=p_tarea returning * into tarea;
 perform privado.evento(p_tarea,'subtarea_guardada',jsonb_build_object('subtarea_id',resultado.id,'estado',resultado.estado));
 return tarea;
end $$;
create function public.comentar_tarea(p_tarea uuid,p_version integer,p_contenido text) returns public.tareas
language plpgsql security definer set search_path='' as $$
declare tarea public.tareas;
begin
 select * into strict tarea from public.tareas where id=p_tarea;
 perform privado.bloquear_empresa(tarea.empresa_id);
 select * into strict tarea from public.tareas where id=p_tarea for update;
 if not privado.trabaja_tarea(p_tarea) or tarea.version is distinct from p_version then raise exception 'Sin permiso o versión obsoleta'; end if;
 insert into public.comentarios_tarea(empresa_id,tarea_id,contenido) values(tarea.empresa_id,p_tarea,btrim(p_contenido));
 update public.tareas set fecha_modificacion=now() where id=p_tarea returning * into tarea;
 perform privado.evento(p_tarea,'comentario_agregado'); return tarea;
end $$;
create function public.marcar_notificacion_leida(p_notificacion uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 update public.notificaciones set fecha_lectura=coalesce(fecha_lectura,now()) where id=p_notificacion and usuario_id=auth.uid() and privado.es_miembro(empresa_id);
 if not found then raise exception 'Notificación sin acceso'; end if;
end $$;

-- No se habilitan funciones ajenas a este paquete.
do $$ declare funcion regprocedure; begin
 for funcion in select p.oid::regprocedure from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname=any(array['guardar_mi_perfil','guardar_preferencias','guardar_empresa','asignar_usuario_empresa','guardar_area','guardar_equipo','asignar_miembro_equipo','guardar_tablero','cambiar_estado_tablero','guardar_tarea','cambiar_estado_tarea','guardar_subtarea','comentar_tarea','marcar_notificacion_leida']) loop
   execute format('revoke all on function %s from public,anon,authenticated',funcion);
   execute format('grant execute on function %s to authenticated',funcion);
 end loop;
end $$;
revoke all on function privado.bloquear_empresa(uuid),privado.exigir_administrador(uuid),privado.evento(uuid,text,jsonb) from public,anon,authenticated;
commit;
