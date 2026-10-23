-- 04. Buckets privados, permisos de archivos y vistas para la app.
begin;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values ('fotos-perfil','fotos-perfil',false,5242880,array['image/jpeg','image/png','image/webp']),
       ('evidencias-tareas','evidencias-tareas',false,20971520,array['image/jpeg','image/png','image/webp','application/pdf','text/plain','application/msword','application/vnd.openxmlformats-officedocument.wordprocessingml.document','application/vnd.ms-excel','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'])
on conflict(id) do update set public=excluded.public,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;

create function privado.lee_foto(p_ruta text) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.usuarios where ruta_foto_perfil=p_ruta and privado.ve_usuario(id)) or (storage.foldername(p_ruta))[1]=auth.uid()::text
$$;
create function privado.carga_evidencia(p_ruta text) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.evidencias e where e.ruta_archivo=p_ruta and e.usuario_creacion=auth.uid() and e.estado_carga='pendiente' and privado.trabaja_tarea(e.tarea_id))
$$;
create function privado.lee_evidencia(p_ruta text) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.evidencias e where e.ruta_archivo=p_ruta and privado.ve_tarea(e.tarea_id) and (e.estado_carga='confirmada' or e.usuario_creacion=auth.uid()))
$$;
revoke all on function privado.lee_foto(text),privado.carga_evidencia(text),privado.lee_evidencia(text) from public,anon,authenticated;
grant execute on function privado.lee_foto(text),privado.carga_evidencia(text),privado.lee_evidencia(text) to authenticated;
create policy ohana_fotos_lectura on storage.objects for select to authenticated using(bucket_id='fotos-perfil' and privado.lee_foto(name));
create policy ohana_fotos_carga on storage.objects for insert to authenticated with check(bucket_id='fotos-perfil' and (storage.foldername(name))[1]=auth.uid()::text and exists(select 1 from public.usuarios where id=auth.uid() and activo));
-- Usar nombres UUID nuevos; no upsert ni sobrescrituras de evidencias.
create policy ohana_fotos_borrado on storage.objects for delete to authenticated using(bucket_id='fotos-perfil' and (storage.foldername(name))[1]=auth.uid()::text and not exists(select 1 from public.usuarios where ruta_foto_perfil=name));
create policy ohana_evidencias_lectura on storage.objects for select to authenticated using(bucket_id='evidencias-tareas' and privado.lee_evidencia(name));
create policy ohana_evidencias_carga on storage.objects for insert to authenticated with check(bucket_id='evidencias-tareas' and privado.carga_evidencia(name));
-- No hay DELETE ni UPDATE cliente en evidencias: archivos confirmados son inmutables.

create function public.reservar_evidencia(p_tarea uuid,p_version integer,p_nombre_archivo text,p_tipo text,p_extension text) returns public.evidencias
language plpgsql security definer set search_path='' as $$
declare tarea public.tareas; resultado public.evidencias; identificador uuid:=gen_random_uuid(); extension text:=lower(p_extension);
begin
 select * into strict tarea from public.tareas where id=p_tarea;
 perform privado.bloquear_empresa(tarea.empresa_id);
 select * into strict tarea from public.tareas where id=p_tarea for update;
 if not privado.trabaja_tarea(p_tarea) or tarea.version is distinct from p_version then raise exception 'Sin permiso o versión obsoleta'; end if;
 if extension not in ('jpg','jpeg','png','webp','pdf','txt','doc','docx','xls','xlsx') or p_tipo not in ('imagen','archivo') or (p_tipo='imagen' and extension not in ('jpg','jpeg','png','webp')) then raise exception 'Tipo de archivo no permitido'; end if;
 insert into public.evidencias(id,empresa_id,tarea_id,nombre_archivo,tipo,ruta_archivo)
 values(identificador,tarea.empresa_id,p_tarea,p_nombre_archivo,p_tipo,tarea.empresa_id::text||'/'||p_tarea::text||'/'||identificador::text||'.'||extension) returning * into resultado;
 update public.tareas set fecha_modificacion=now() where id=p_tarea;
 return resultado;
end $$;
create function public.confirmar_evidencia(p_evidencia uuid) returns public.evidencias
language plpgsql security definer set search_path='' as $$
declare resultado public.evidencias;
begin
 select * into strict resultado from public.evidencias where id=p_evidencia;
 perform privado.bloquear_empresa(resultado.empresa_id);
 select * into strict resultado from public.evidencias where id=p_evidencia for update;
 if resultado.usuario_creacion<>auth.uid() or not privado.trabaja_tarea(resultado.tarea_id) or resultado.estado_carga<>'pendiente' then raise exception 'Carga sin acceso o ya resuelta'; end if;
 if not exists(select 1 from storage.objects where bucket_id='evidencias-tareas' and name=resultado.ruta_archivo) then raise exception 'Primero carga el archivo en Storage'; end if;
 update public.evidencias set estado_carga='confirmada' where id=p_evidencia returning * into resultado;
 update public.tareas set fecha_modificacion=now() where id=resultado.tarea_id;
 perform privado.evento(resultado.tarea_id,'evidencia_agregada',jsonb_build_object('evidencia_id',resultado.id));
 return resultado;
end $$;
create function public.cancelar_evidencia(p_evidencia uuid) returns void language plpgsql security definer set search_path='' as $$
declare evidencia public.evidencias;
begin
 select * into strict evidencia from public.evidencias where id=p_evidencia;
 perform privado.bloquear_empresa(evidencia.empresa_id);
 select * into strict evidencia from public.evidencias where id=p_evidencia for update;
 if evidencia.usuario_creacion<>auth.uid() or not privado.trabaja_tarea(evidencia.tarea_id) or evidencia.estado_carga<>'pendiente' then raise exception 'Carga sin acceso o ya resuelta'; end if;
 update public.evidencias set estado_carga='cancelada' where id=p_evidencia;
 -- No borrar storage.objects por SQL: limpieza física por Storage API desde servidor.
end $$;
revoke all on function public.reservar_evidencia(uuid,integer,text,text,text),public.confirmar_evidencia(uuid),public.cancelar_evidencia(uuid) from public,anon,authenticated;
grant execute on function public.reservar_evidencia(uuid,integer,text,text,text),public.confirmar_evidencia(uuid),public.cancelar_evidencia(uuid) to authenticated;

-- security_invoker conserva RLS de las tablas subyacentes. PostgreSQL 15+.
create view public.vista_tareas with (security_invoker=true) as
select t.*,a.id area_id,a.nombre nombre_area,e.nombre nombre_equipo,b.nombre nombre_tablero,u.nombre_completo nombre_responsable,
 case when t.estado='finalizado' then case when t.fecha_finalizacion>t.fecha_fin then 'finalizada_fuera_de_plazo' else 'finalizada_en_plazo' end
      when now()>t.fecha_fin then 'vencida' when now()<t.fecha_inicio then 'programada' else 'en_plazo' end estado_vencimiento,
 (select count(*) from public.subtareas s where s.tarea_id=t.id) cantidad_subtareas,
 (select count(*) from public.subtareas s where s.tarea_id=t.id and s.estado='finalizado') subtareas_finalizadas
from public.tareas t join public.tableros b on b.id=t.tablero_id join public.equipos e on e.id=t.equipo_id join public.areas a on a.id=e.area_id join public.usuarios u on u.id=t.responsable_id;
create view public.vista_subtareas with (security_invoker=true) as
select s.*,u.nombre_completo nombre_responsable,
 case when s.estado='finalizado' then case when s.fecha_finalizacion>s.fecha_fin then 'finalizada_fuera_de_plazo' else 'finalizada_en_plazo' end
      when now()>s.fecha_fin then 'vencida' when now()<s.fecha_inicio then 'programada' else 'en_plazo' end estado_vencimiento
from public.subtareas s join public.usuarios u on u.id=s.responsable_id;
create view public.vista_tableros with (security_invoker=true) as
select b.*,e.area_id,a.nombre nombre_area,e.nombre nombre_equipo from public.tableros b join public.equipos e on e.id=b.equipo_id join public.areas a on a.id=e.area_id;
revoke all on public.vista_tareas,public.vista_subtareas,public.vista_tableros from anon;
grant select on public.vista_tareas,public.vista_subtareas,public.vista_tableros to authenticated;
commit;
