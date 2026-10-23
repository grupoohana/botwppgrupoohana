begin;
create function public.wa_unsubscribe(p_link uuid) returns void language plpgsql security definer set search_path='' as $$
declare l public.wa_links; begin
 select * into strict l from public.wa_links where id=p_link;
 with unlinked as(update public.wa_links set enabled=false,notifications=false,followups=false,reminders=false where phone=l.phone and phone_id=l.phone_id and usuario_id=l.usuario_id returning empresa_id,usuario_id)
 insert into public.wa_audit(empresa_id,usuario_id,action) select empresa_id,usuario_id,'baja_whatsapp' from unlinked;
 update public.wa_conversations set pending='{}',link_id=null where phone=l.phone and phone_id=l.phone_id;
end $$;
alter table public.wa_config add constraint wa_valid_days check(work_days<@array[0,1,2,3,4,5,6] and cardinality(work_days)>0);

create function public.wa_recipient(p_empresa uuid,p_usuario uuid,p_task uuid default null,p_interactive boolean default false) returns jsonb language plpgsql security definer set search_path='' as $$
declare l public.wa_links; detail jsonb; begin
 select * into l from public.wa_links w where w.empresa_id=p_empresa and w.usuario_id=p_usuario and w.enabled and (w.notifications or p_interactive);
 if l.id is null or not exists(select 1 from public.wa_config where empresa_id=p_empresa and enabled) then return null; end if;
 perform set_config('request.jwt.claim.sub',l.usuario_id::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',l.usuario_id,'role','authenticated')::text,true);
 if not privado.es_miembro(p_empresa) then return null; end if;
 if p_task is not null then
  if not exists(select 1 from public.tareas where id=p_task and empresa_id=p_empresa and privado.ve_tarea(id)) then return null; end if;
  detail:=public.wa_actor_action(l.id,'detail',jsonb_build_object('task_id',p_task));
 end if;
 return jsonb_build_object('link',to_jsonb(l),'task',detail,'company',(select nombre from public.empresas where id=p_empresa),
  'config',(select to_jsonb(c) from public.wa_config c where c.empresa_id=p_empresa),'conversation',(select to_jsonb(c) from public.wa_conversations c where c.phone_id=l.phone_id and c.phone=l.phone));
end $$;

create function public.wa_delivery_status(p_provider text,p_job uuid,p_status text,p_at timestamptz,p_error text default null) returns void language plpgsql security definer set search_path='' as $$
declare j public.wa_jobs; begin
 select * into j from public.wa_jobs where id=p_job and kind='outbound';
 if j.id is null or p_status not in ('sent','delivered','read','failed') then return; end if;
 insert into public.wa_delivery(provider_id,job_id,status,provider_at,error_code) values(p_provider,p_job,p_status,p_at,left(p_error,50))
 on conflict(provider_id) do update set status=excluded.status,provider_at=excluded.provider_at,error_code=excluded.error_code,updated_at=now()
 where public.wa_delivery.job_id=excluded.job_id and excluded.provider_at>=public.wa_delivery.provider_at
  and (public.wa_delivery.status not in ('delivered','read') or excluded.status in ('delivered','read')) and (public.wa_delivery.status<>'read' or excluded.status='read');
 if p_status in ('sent','delivered','read') then update public.wa_jobs set status='done',lease_until=null,updated_at=now() where id=p_job and status in ('processing','uncertain'); end if;
end $$;

create or replace function privado.wa_assignment() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if (tg_op='INSERT' or new.responsable_id is distinct from old.responsable_id) and exists(select 1 from public.wa_config c join public.wa_links l on l.empresa_id=c.empresa_id where c.empresa_id=new.empresa_id and c.enabled and l.usuario_id=new.responsable_id and l.enabled and l.notifications) then
  perform public.wa_enqueue('assignment','assignment:'||new.id||':'||new.version,jsonb_build_object('task_id',new.id,'assignee',new.responsable_id),new.empresa_id,new.responsable_id);
 end if;
 return new;
end $$;
create function privado.wa_image_event() returns trigger language plpgsql security definer set search_path='' as $$
declare t public.tareas; begin
 if new.tipo='imagen' and new.estado_carga='confirmada' and (tg_op='INSERT' or old.estado_carga is distinct from new.estado_carga) then
  select * into t from public.tareas where id=new.tarea_id;
  if new.usuario_creacion is distinct from t.responsable_id and exists(select 1 from public.wa_config c where c.empresa_id=t.empresa_id and c.enabled) then
   perform public.wa_enqueue('evidence','evidence:'||new.id,jsonb_build_object('task_id',t.id,'evidence_id',new.id),t.empresa_id,t.responsable_id);
  end if;
 end if;
 return new;
end $$;
create trigger wa_image_event after insert or update of estado_carga on public.evidencias for each row execute function privado.wa_image_event();

create function public.wa_schedule(p_limit integer default 100) returns integer language plpgsql security definer set search_path='' as $$
declare r record; local_time timestamp; daykey text; cnt integer:=0; k text;
begin
 for r in select l.*,c.timezone company_timezone,c.work_days,c.work_start,c.work_end,c.followup_time,c.due_hours,c.frequency_minutes,c.leader_digest
  from public.wa_links l join public.wa_config c on c.empresa_id=l.empresa_id and c.enabled join public.usuarios u on u.id=l.usuario_id and u.activo
  join public.usuarios_empresas m on m.usuario_id=l.usuario_id and m.empresa_id=l.empresa_id and m.activo join public.empresas e on e.id=l.empresa_id and e.activo
  where l.enabled and l.notifications and not exists(select 1 from public.preferencias_usuario p where p.usuario_id=l.usuario_id and not p.recordatorios)
   and (exists(select 1 from public.tareas t where t.empresa_id=l.empresa_id and t.responsable_id=l.usuario_id and t.estado<>'finalizado')
    or c.leader_digest and exists(select 1 from public.miembros_equipo me join public.tareas t on t.equipo_id=me.equipo_id where me.empresa_id=l.empresa_id and me.usuario_id=l.usuario_id and me.rol='lider' and me.activo and t.estado<>'finalizado'))
  order by l.last_scanned_at,l.id limit least(greatest(p_limit,1),500)
 loop
  update public.wa_links set last_scanned_at=now() where id=r.id;
  local_time:=now() at time zone coalesce(r.timezone,r.company_timezone); daykey:=local_time::date::text;
  if not extract(dow from local_time)::integer=any(r.work_days) or local_time::time<r.work_start or local_time::time>r.work_end then continue; end if;
  if exists(select 1 from public.wa_jobs j where j.usuario_id=r.usuario_id and j.empresa_id=r.empresa_id and j.kind in ('reminder','followup','digest') and j.created_at>now()-make_interval(mins=>r.frequency_minutes)) then continue; end if;
  if r.leader_digest and local_time::time>=r.followup_time and exists(select 1 from public.miembros_equipo where empresa_id=r.empresa_id and usuario_id=r.usuario_id and rol='lider' and activo) then k:='digest';
  elsif r.followups and local_time::time>=r.followup_time then k:='followup';
  elsif r.reminders and exists(select 1 from public.tareas t where t.empresa_id=r.empresa_id and t.responsable_id=r.usuario_id and t.estado<>'finalizado' and t.fecha_fin<now()+make_interval(hours=>r.due_hours)) then k:='reminder';
  else continue; end if;
  if public.wa_enqueue(k,k||':'||r.id||':'||daykey,jsonb_build_object('link_id',r.id),r.empresa_id,r.usuario_id) is not null then cnt:=cnt+1; end if;
 end loop;
 return cnt;
end $$;

create function public.wa_cleanup() returns void language plpgsql security definer set search_path='' as $$
begin
 delete from public.wa_template_slots where reserved_at<now()-interval '30 days';
 delete from public.wa_link_codes where expires_at<now()-interval '1 day';
 delete from public.wa_rate_limits where window_start<now()-interval '2 days';
 update public.wa_conversations set pending='{}' where pending<>'{}' and coalesce((pending->>'expires_at')::timestamptz,'-infinity')<now();
 -- Keep dedup keys 30 days; content is erased immediately after processing inbound messages.
 delete from public.wa_delivery where updated_at<now()-interval '30 days';
 delete from public.wa_jobs where updated_at<now()-interval '30 days' and status in ('done','failed');
end $$;
do $$ declare f record; begin
 for f in select p.oid::regprocedure signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in ('wa_recipient','wa_delivery_status','wa_schedule','wa_cleanup','wa_unsubscribe') loop
  execute format('revoke all on function %s from public,anon,authenticated',f.signature);
  execute format('grant execute on function %s to service_role',f.signature);
 end loop;
end $$;
revoke all on function privado.wa_image_event() from public,anon,authenticated;
commit;
