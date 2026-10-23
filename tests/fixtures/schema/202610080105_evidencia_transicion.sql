-- Una operación estable permite reintentar sin repetir estados, comentarios o archivos.
-- La evidencia histórica no exige un vínculo retroactivo.
begin;
create table public.transiciones_tarea (
 id uuid primary key, empresa_id uuid not null, tarea_id uuid not null,
 estado_origen public.estado_trabajo not null, estado_destino public.estado_trabajo not null,
 version_origen integer not null, estado text not null default 'pendiente' check(estado in ('pendiente','confirmada','cancelada')),
 resultado jsonb,
 usuario_creacion uuid references public.usuarios(id),fecha_creacion timestamptz not null default now(),
 usuario_modificacion uuid references public.usuarios(id),fecha_modificacion timestamptz not null default now(),
 foreign key(empresa_id,tarea_id) references public.tareas(empresa_id,id) on delete cascade,
 check(estado_origen<>estado_destino), check(version_origen>0)
);
alter table public.transiciones_tarea enable row level security;
revoke all on public.transiciones_tarea from public,anon,authenticated;
grant select on public.transiciones_tarea to authenticated;
create policy transiciones_lectura on public.transiciones_tarea for select to authenticated using(privado.ve_tarea(tarea_id));
create trigger z_sellar_auditoria before insert or update on public.transiciones_tarea for each row execute function privado.sellar_auditoria();
create trigger registrar_auditoria after insert or update or delete on public.transiciones_tarea for each row execute function privado.registrar_auditoria();
create index transiciones_tarea_fecha on public.transiciones_tarea(tarea_id,fecha_creacion desc);
alter table public.evidencias add column transicion_id uuid unique references public.transiciones_tarea(id) on delete set null;
alter table public.evidencias add column ruta_miniatura text unique;

create function public.preparar_transicion(p_tarea uuid,p_version integer,p_estado public.estado_trabajo,p_operacion uuid,
 p_nombre text,p_tipo text,p_extension text,p_miniatura boolean default false) returns jsonb
language plpgsql security definer set search_path='' as $$
declare t public.tareas; cambio public.transiciones_tarea; evidencia public.evidencias; extension text:=lower(p_extension); identificador uuid:=gen_random_uuid();
begin
 select * into strict t from public.tareas where id=p_tarea;
 perform privado.bloquear_empresa(t.empresa_id);
 select * into strict t from public.tareas where id=p_tarea for update;
 if not privado.gestiona_tarea(t.id) then raise exception 'Sin permiso sobre la tarea'; end if;
 select * into cambio from public.transiciones_tarea where id=p_operacion for update;
 if found then
  if cambio.tarea_id<>t.id or cambio.usuario_creacion<>auth.uid() or cambio.estado_destino<>p_estado then raise exception 'Operación ajena o reutilizada'; end if;
  select * into evidencia from public.evidencias where transicion_id=cambio.id;
  if evidencia.id is null or evidencia.nombre_archivo<>p_nombre or evidencia.tipo<>p_tipo then raise exception 'La operación ya tiene otro archivo'; end if;
  if cambio.estado='cancelada' then raise exception 'Operación cancelada'; end if;
  return jsonb_build_object('transicion',to_jsonb(cambio),'evidencia',to_jsonb(evidencia),'archivo_cargado',exists(select 1 from storage.objects where bucket_id='evidencias-tareas' and name=evidencia.ruta_archivo),'miniatura_cargada',evidencia.ruta_miniatura is null or exists(select 1 from storage.objects where bucket_id='evidencias-tareas' and name=evidencia.ruta_miniatura));
 end if;
 if t.version<>p_version then raise exception 'Versión obsoleta: recarga la tarea'; end if;
 if t.estado=p_estado then raise exception 'La evidencia requiere un cambio real de estado'; end if;
 if not exists(select 1 from public.tableros where id=t.tablero_id and estado='activo') then raise exception 'Reabre el tablero'; end if;
 if extension not in ('jpg','jpeg','png','webp','pdf','txt','doc','docx','xls','xlsx') or p_tipo not in ('imagen','archivo') or (p_tipo='imagen' and extension not in ('jpg','jpeg','png','webp')) or (p_miniatura and p_tipo<>'imagen') then raise exception 'Archivo inválido'; end if;
 insert into public.transiciones_tarea(id,empresa_id,tarea_id,estado_origen,estado_destino,version_origen)
 values(p_operacion,t.empresa_id,t.id,t.estado,p_estado,p_version) returning * into cambio;
 insert into public.evidencias(id,empresa_id,tarea_id,nombre_archivo,tipo,ruta_archivo,transicion_id,ruta_miniatura)
 values(identificador,t.empresa_id,t.id,p_nombre,p_tipo,t.empresa_id::text||'/'||t.id::text||'/'||identificador::text||'.'||extension,p_operacion,
 case when p_miniatura then t.empresa_id::text||'/'||t.id::text||'/'||identificador::text||'-miniatura.jpg' end) returning * into evidencia;
 return jsonb_build_object('transicion',to_jsonb(cambio),'evidencia',to_jsonb(evidencia),'archivo_cargado',exists(select 1 from storage.objects where bucket_id='evidencias-tareas' and name=evidencia.ruta_archivo),'miniatura_cargada',evidencia.ruta_miniatura is null or exists(select 1 from storage.objects where bucket_id='evidencias-tareas' and name=evidencia.ruta_miniatura));
end $$;

create function public.guardar_transicion(p_tarea uuid,p_version integer,p_estado public.estado_trabajo,p_operacion uuid,
 p_comentario text default null,p_evidencia uuid default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare t public.tareas; cambio public.transiciones_tarea; evidencia public.evidencias;
begin
 select * into strict t from public.tareas where id=p_tarea;
 perform privado.bloquear_empresa(t.empresa_id);
 select * into strict t from public.tareas where id=p_tarea for update;
 if not privado.gestiona_tarea(t.id) then raise exception 'Sin permiso sobre la tarea'; end if;
 select * into cambio from public.transiciones_tarea where id=p_operacion for update;
 if found then
  if cambio.tarea_id<>t.id or cambio.usuario_creacion<>auth.uid() or cambio.estado_destino<>p_estado then raise exception 'Operación ajena o reutilizada'; end if;
  if cambio.estado='confirmada' then return cambio.resultado; end if;
  if cambio.estado='cancelada' then raise exception 'Operación cancelada'; end if;
  if cambio.version_origen<>p_version or cambio.estado_origen<>t.estado then raise exception 'Versión obsoleta: recarga la tarea'; end if;
 else
  if p_evidencia is not null then raise exception 'Reserva primero la evidencia de esta transición'; end if;
  insert into public.transiciones_tarea(id,empresa_id,tarea_id,estado_origen,estado_destino,version_origen)
   values(p_operacion,t.empresa_id,t.id,t.estado,p_estado,p_version) returning * into cambio;
 end if;
 if t.version<>p_version then raise exception 'Versión obsoleta: recarga la tarea'; end if;
 select * into evidencia from public.evidencias where transicion_id=p_operacion for update;
 if evidencia.id is distinct from p_evidencia then raise exception 'Evidencia diferente a la reservada'; end if;
 if evidencia.id is not null then
  if evidencia.usuario_creacion<>auth.uid() or evidencia.estado_carga<>'pendiente' then raise exception 'Evidencia sin acceso o ya resuelta'; end if;
  if not exists(select 1 from storage.objects where bucket_id='evidencias-tareas' and name=evidencia.ruta_archivo) then raise exception 'El archivo todavía no está registrado'; end if;
  if evidencia.ruta_miniatura is not null and not exists(select 1 from storage.objects where bucket_id='evidencias-tareas' and name=evidencia.ruta_miniatura) then raise exception 'La miniatura todavía no está registrada'; end if;
 end if;
 -- El cambio, comentario y confirmación quedan juntos en una transacción SQL.
 t:=public.cambiar_estado_tarea(t.id,p_version,p_estado,p_comentario);
 if evidencia.id is not null then
  update public.evidencias set estado_carga='confirmada' where id=evidencia.id returning * into evidencia;
  perform privado.evento(t.id,'evidencia_agregada',jsonb_build_object('evidencia_id',evidencia.id,'transicion_id',p_operacion));
 end if;
 update public.transiciones_tarea set estado='confirmada',resultado=jsonb_build_object('tarea',to_jsonb(t),'evidencia',case when evidencia.id is not null then to_jsonb(evidencia) else null end,'transicion_id',p_operacion,
 'comentarios',coalesce((select jsonb_agg(to_jsonb(c)) from public.comentarios_tarea c where c.tarea_id=t.id and c.usuario_creacion=auth.uid() and c.fecha_creacion=now()),'[]'::jsonb),
 'eventos',coalesce((select jsonb_agg(to_jsonb(e)) from public.eventos_tarea e where e.tarea_id=t.id and e.usuario_creacion=auth.uid() and e.fecha_creacion=now()),'[]'::jsonb)) where id=p_operacion returning * into cambio;
 return cambio.resultado;
end $$;

create function public.cancelar_transicion(p_operacion uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare cambio public.transiciones_tarea;
begin
 select * into cambio from public.transiciones_tarea where id=p_operacion;
 if not found then return null; end if;
 perform privado.bloquear_empresa(cambio.empresa_id);
 if cambio.usuario_creacion<>auth.uid() or not privado.gestiona_tarea(cambio.tarea_id) then raise exception 'Operación sin acceso'; end if;
 select * into strict cambio from public.transiciones_tarea where id=p_operacion for update;
 if cambio.estado='confirmada' then return cambio.resultado; end if;
 -- La eliminación encola original y miniatura para la limpieza física segura.
 delete from public.evidencias where transicion_id=p_operacion and estado_carga='pendiente';
 update public.transiciones_tarea set estado='cancelada' where id=p_operacion;
 return null;
end $$;

create or replace function privado.carga_evidencia(p_ruta text) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.evidencias e join public.transiciones_tarea c on c.id=e.transicion_id join public.tareas t on t.id=e.tarea_id join public.tableros b on b.id=t.tablero_id
 where (e.ruta_archivo=p_ruta or e.ruta_miniatura=p_ruta) and e.usuario_creacion=auth.uid() and e.estado_carga='pendiente'
 and c.estado='pendiente' and c.version_origen=t.version and c.estado_origen=t.estado and b.estado='activo' and privado.gestiona_tarea(t.id))
$$;
create or replace function privado.lee_evidencia(p_ruta text) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.evidencias e where (e.ruta_archivo=p_ruta or e.ruta_miniatura=p_ruta) and privado.ve_tarea(e.tarea_id) and (e.estado_carga='confirmada' or e.usuario_creacion=auth.uid()))
$$;
revoke all on function public.reservar_evidencia(uuid,integer,text,text,text),public.confirmar_evidencia(uuid),public.cancelar_evidencia(uuid) from public,anon,authenticated;
revoke all on function public.preparar_transicion(uuid,integer,public.estado_trabajo,uuid,text,text,text,boolean),public.guardar_transicion(uuid,integer,public.estado_trabajo,uuid,text,uuid),public.cancelar_transicion(uuid) from public,anon;
grant execute on function public.preparar_transicion(uuid,integer,public.estado_trabajo,uuid,text,text,text,boolean),public.guardar_transicion(uuid,integer,public.estado_trabajo,uuid,text,uuid),public.cancelar_transicion(uuid) to authenticated;
create or replace function privado.encolar_archivo_eliminado() returns trigger language plpgsql security definer set search_path='' as $$
begin
 insert into public.archivos_eliminados(bucket,ruta,solicitante_id)
 select case when tg_table_name='evidencias' then 'evidencias-tareas' else 'logos-empresas' end,ruta,auth.uid()
 from unnest(array[coalesce(to_jsonb(old)->>'ruta_archivo',to_jsonb(old)->>'ruta'),to_jsonb(old)->>'ruta_miniatura']) ruta
 where ruta is not null on conflict do nothing;
 return old;
end $$;
commit;
