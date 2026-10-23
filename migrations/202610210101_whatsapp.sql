begin;
create table public.wa_config (
 empresa_id uuid primary key references public.empresas(id) on delete cascade, enabled boolean not null default false, ai_enabled boolean not null default false,
 phone_id text not null, timezone text not null default 'America/Bogota', work_start time not null default '08:00', work_end time not null default '18:00',
 work_days integer[] not null default array[1,2,3,4,5], followup_time time not null default '17:30', due_hours integer not null default 24 check(due_hours between 1 and 168),
 frequency_minutes integer not null default 60 check(frequency_minutes between 15 and 1440), template_name text, template_language text not null default 'es',
 leader_digest boolean not null default false, updated_at timestamptz not null default now(), check(work_start<work_end)
);
create table public.wa_link_codes (
 id uuid primary key default gen_random_uuid(), empresa_id uuid not null references public.empresas(id) on delete cascade, usuario_id uuid not null references public.usuarios(id) on delete cascade,
 phone text not null check(phone ~ '^[1-9][0-9]{7,14}$'), phone_id text not null, code_hash text not null unique, expires_at timestamptz not null, consumed_at timestamptz,
 created_at timestamptz not null default now()
);
create table public.wa_links (
 id uuid primary key default gen_random_uuid(), empresa_id uuid not null references public.empresas(id) on delete cascade, usuario_id uuid not null references public.usuarios(id) on delete cascade,
 phone text not null check(phone ~ '^[1-9][0-9]{7,14}$'), phone_id text not null, verified_at timestamptz not null default now(), consent_at timestamptz not null default now(),
 consent_version text not null default 'whatsapp-v1', enabled boolean not null default true, notifications boolean not null default true,
 followups boolean not null default true, reminders boolean not null default true, timezone text,
 last_scanned_at timestamptz not null default '-infinity',
 unique(empresa_id,usuario_id), unique(empresa_id,phone_id,phone)
);
create table public.wa_conversations (
 phone_id text not null, phone text not null, link_id uuid references public.wa_links(id) on delete set null, last_inbound timestamptz,
 pending jsonb not null default '{}', primary key(phone_id,phone)
);
create table public.wa_jobs (
 id uuid primary key default gen_random_uuid(), kind text not null check(kind in ('inbound','assignment','evidence','reminder','followup','digest','outbound')),
 dedup_key text not null unique, empresa_id uuid references public.empresas(id) on delete cascade, usuario_id uuid references public.usuarios(id) on delete cascade, payload jsonb not null default '{}',
 status text not null default 'pending' check(status in ('pending','processing','done','failed','uncertain')), attempts integer not null default 0,
 available_at timestamptz not null default now(), lease_until timestamptz, lease_token uuid, last_error text, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index wa_jobs_pending on public.wa_jobs(available_at,created_at) where status in ('pending','processing');
create index wa_jobs_tenant on public.wa_jobs(empresa_id,created_at desc);
create table public.wa_delivery (
 provider_id text primary key, job_id uuid references public.wa_jobs(id) on delete cascade, status text not null, provider_at timestamptz not null,
 error_code text, updated_at timestamptz not null default now()
);
create table public.wa_operations (
 id uuid primary key, link_id uuid not null references public.wa_links(id) on delete cascade, tarea_id uuid not null references public.tareas(id) on delete cascade, kind text not null,
 evidencia_id uuid references public.evidencias(id) on delete set null, result jsonb, created_at timestamptz not null default now()
);
create table public.wa_audit (
 id bigint generated always as identity primary key, empresa_id uuid references public.empresas(id) on delete cascade, usuario_id uuid references public.usuarios(id) on delete cascade,
 action text not null, operation_id uuid, details jsonb not null default '{}', created_at timestamptz not null default now()
);
create table public.wa_usage (
 empresa_id uuid not null references public.empresas(id) on delete cascade, day date not null default current_date, calls integer not null default 0, reserved_tokens integer not null default 0,
 primary key(empresa_id,day)
);
create table public.wa_rate_limits (key text primary key, window_start timestamptz not null default now(), count integer not null default 0);
do $$ declare n text; begin
 foreach n in array array['wa_config','wa_link_codes','wa_links','wa_conversations','wa_jobs','wa_delivery','wa_operations','wa_audit','wa_usage','wa_rate_limits'] loop
  execute format('alter table public.%I enable row level security',n);
  execute format('revoke all on public.%I from public,anon,authenticated',n);
  execute format('grant all on public.%I to service_role',n);
 end loop;
end $$;
grant usage,select on sequence public.wa_audit_id_seq to service_role;

create function privado.wa_rate(p_key text,p_max integer,p_seconds integer) returns void language plpgsql security definer set search_path='' as $$
declare r public.wa_rate_limits; begin
 insert into public.wa_rate_limits(key) values(p_key) on conflict do nothing;
 select * into r from public.wa_rate_limits where key=p_key for update;
 if r.window_start<now()-make_interval(secs=>p_seconds) then update public.wa_rate_limits set count=0,window_start=now() where key=p_key returning * into r; end if;
 if r.count>=p_max then raise exception 'Límite temporal alcanzado'; end if;
 update public.wa_rate_limits set count=count+1 where key=p_key;
end $$;

create function public.wa_link_start(p_empresa uuid,p_phone text,p_hash text,p_consent boolean) returns jsonb language plpgsql security definer set search_path='' as $$
declare c public.wa_config; begin
 if auth.uid() is null or not privado.es_miembro(p_empresa) or not p_consent or p_phone !~ '^[1-9][0-9]{7,14}$' or p_hash !~ '^[a-f0-9]{64}$' then raise exception 'Vinculación sin acceso o consentimiento'; end if;
 perform privado.wa_rate('link:'||auth.uid()::text,5,3600);
 select * into strict c from public.wa_config where empresa_id=p_empresa and enabled;
 insert into public.wa_link_codes(empresa_id,usuario_id,phone,phone_id,code_hash,expires_at) values(p_empresa,auth.uid(),p_phone,c.phone_id,p_hash,now()+interval '10 minutes');
 return jsonb_build_object('expires_in',600,'phone_id',c.phone_id);
end $$;

create function public.wa_link_complete(p_phone text,p_phone_id text,p_hash text) returns jsonb language plpgsql security definer set search_path='' as $$
declare code public.wa_link_codes; l public.wa_links; begin
 perform pg_advisory_xact_lock(hashtextextended(p_phone_id||p_phone,0));
 perform privado.wa_rate('verify:'||p_phone_id||p_phone,10,600);
 select * into strict code from public.wa_link_codes where phone=p_phone and phone_id=p_phone_id and code_hash=p_hash and consumed_at is null and expires_at>now() for update;
 if not exists(select 1 from public.usuarios u join public.usuarios_empresas m on m.usuario_id=u.id join public.empresas e on e.id=m.empresa_id where u.id=code.usuario_id and u.activo and m.empresa_id=code.empresa_id and m.activo and e.activo) then raise exception 'Usuario sin acceso'; end if;
 if exists(select 1 from public.wa_links where phone_id=p_phone_id and phone=p_phone and enabled and usuario_id<>code.usuario_id) then raise exception 'Número ya vinculado a otra cuenta'; end if;
 insert into public.wa_links(empresa_id,usuario_id,phone,phone_id) values(code.empresa_id,code.usuario_id,p_phone,p_phone_id)
 on conflict(empresa_id,usuario_id) do update set phone=excluded.phone,phone_id=excluded.phone_id,enabled=true,verified_at=now(),consent_at=now() returning * into l;
 update public.wa_link_codes set consumed_at=now() where id=code.id;
 insert into public.wa_conversations(phone_id,phone,link_id,last_inbound) values(p_phone_id,p_phone,l.id,now()) on conflict(phone_id,phone) do update set link_id=l.id,last_inbound=now(),pending='{}';
 insert into public.wa_audit(empresa_id,usuario_id,action) values(l.empresa_id,l.usuario_id,'numero_verificado');
 return to_jsonb(l);
end $$;

create function public.wa_account(p_empresa uuid,p_action text default 'status',p_options jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare l public.wa_links; begin
 if auth.uid() is null or not privado.es_miembro(p_empresa) then raise exception 'Empresa sin acceso'; end if;
 if p_action='unlink' then
  update public.wa_links set enabled=false where empresa_id=p_empresa and usuario_id=auth.uid();
  update public.wa_conversations set pending='{}',link_id=null where link_id in(select id from public.wa_links where empresa_id=p_empresa and usuario_id=auth.uid());
 elsif p_action='preferences' then
  update public.wa_links set notifications=coalesce((p_options->>'notifications')::boolean,notifications),followups=coalesce((p_options->>'followups')::boolean,followups),reminders=coalesce((p_options->>'reminders')::boolean,reminders) where empresa_id=p_empresa and usuario_id=auth.uid();
 elsif p_action<>'status' then raise exception 'Acción no permitida'; end if;
 select * into l from public.wa_links where empresa_id=p_empresa and usuario_id=auth.uid();
 return case when l.id is null then '{}'::jsonb else to_jsonb(l)-'phone_id' end;
end $$;

create function public.wa_admin(p_empresa uuid,p_action text,p_options jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare c public.wa_config; begin
 perform privado.exigir_administrador(p_empresa);
 if p_action='configure' then
  if not exists(select 1 from pg_timezone_names where name=p_options->>'timezone') or p_options->>'phone_id' !~ '^[0-9]+$' then raise exception 'Zona o número de canal inválido'; end if;
  insert into public.wa_config(empresa_id,phone_id) values(p_empresa,p_options->>'phone_id') on conflict do nothing;
  update public.wa_config set phone_id=p_options->>'phone_id',enabled=coalesce((p_options->>'enabled')::boolean,false),ai_enabled=coalesce((p_options->>'ai_enabled')::boolean,false),timezone=p_options->>'timezone',
   work_start=coalesce((p_options->>'work_start')::time,work_start),work_end=coalesce((p_options->>'work_end')::time,work_end),followup_time=coalesce((p_options->>'followup_time')::time,followup_time),
   work_days=case when p_options?'work_days' then array(select jsonb_array_elements_text(p_options->'work_days')::integer) else work_days end,
   due_hours=coalesce((p_options->>'due_hours')::integer,due_hours),frequency_minutes=coalesce((p_options->>'frequency_minutes')::integer,frequency_minutes),template_name=nullif(p_options->>'template_name',''),
   template_language=coalesce(p_options->>'template_language','es'),leader_digest=coalesce((p_options->>'leader_digest')::boolean,false),updated_at=now() where empresa_id=p_empresa;
 elsif p_action='unlink' then update public.wa_links set enabled=false where empresa_id=p_empresa and id=(p_options->>'link_id')::uuid;
 elsif p_action<>'status' then raise exception 'Acción no permitida'; end if;
 select * into c from public.wa_config where empresa_id=p_empresa;
 return jsonb_build_object('config',to_jsonb(c),'links',coalesce((select jsonb_agg(to_jsonb(l)-'phone_id') from public.wa_links l where l.empresa_id=p_empresa),'[]'::jsonb),
  'jobs',coalesce((select jsonb_agg(x) from(select id,kind,status,attempts,last_error,created_at from public.wa_jobs where empresa_id=p_empresa order by created_at desc limit 50)x),'[]'::jsonb));
end $$;

create function public.wa_enqueue(p_kind text,p_key text,p_payload jsonb,p_empresa uuid default null,p_usuario uuid default null) returns uuid language plpgsql security definer set search_path='' as $$
declare result uuid; begin
 insert into public.wa_jobs(kind,dedup_key,payload,empresa_id,usuario_id) values(p_kind,p_key,p_payload,p_empresa,p_usuario) on conflict(dedup_key) do nothing returning id into result; return result;
end $$;
create function public.wa_claim(p_limit integer default 5) returns setof public.wa_jobs language plpgsql security definer set search_path='' as $$
begin
 -- A crash during a non-idempotent Meta send is ambiguous. Never auto-send it twice.
 update public.wa_jobs set status='uncertain',last_error='lease_expired_after_send',updated_at=now() where kind='outbound' and status='processing' and lease_until<now();
 update public.wa_jobs set status='failed',last_error='attempt_limit',updated_at=now() where kind<>'outbound' and status='processing' and lease_until<now() and attempts>=6;
 return query with picked as (
  select j.id from public.wa_jobs j where (j.status='pending' and j.available_at<=now() or j.status='processing' and j.lease_until<now() and j.kind<>'outbound')
   and j.attempts<6 and not exists(select 1 from public.wa_jobs busy where busy.status='processing' and busy.lease_until>now() and j.kind='inbound' and busy.kind='inbound' and busy.payload->>'phone'=j.payload->>'phone' and busy.payload->>'phone_id'=j.payload->>'phone_id')
   and (j.kind<>'inbound' or not exists(select 1 from public.wa_jobs prior where prior.kind='inbound' and prior.status in ('pending','processing') and prior.payload->>'phone'=j.payload->>'phone' and prior.payload->>'phone_id'=j.payload->>'phone_id' and (prior.created_at,prior.id)<(j.created_at,j.id)))
   order by j.created_at,j.id for update skip locked limit least(greatest(p_limit,1),10)
 ) update public.wa_jobs j set status='processing',attempts=attempts+1,lease_token=gen_random_uuid(),lease_until=now()+interval '3 minutes',updated_at=now() from picked where j.id=picked.id returning j.*;
end $$;
create function public.wa_finish(p_id uuid,p_lease uuid,p_status text,p_error text default null) returns void language plpgsql security definer set search_path='' as $$
begin
 if p_status not in ('done','pending','failed','uncertain') then raise exception 'Estado de cola inválido'; end if;
 update public.wa_jobs set status=case when p_status='pending' and attempts>=6 then 'failed' else p_status end,last_error=left(p_error,100),lease_until=null,
  available_at=now()+make_interval(secs=>least(3600,power(2,attempts)::integer*15)),updated_at=now(),payload=case when kind='inbound' and p_status='done' then '{}'::jsonb else payload end
 where id=p_id and lease_token=p_lease and status='processing';
end $$;

create function public.wa_context(p_phone text,p_phone_id text,p_inbound boolean default false,p_company uuid default null,p_at timestamptz default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare l public.wa_links; conv public.wa_conversations; available jsonb; begin
 perform pg_advisory_xact_lock(hashtextextended(p_phone_id||p_phone,0));
 if p_inbound then
  perform privado.wa_rate('in:'||p_phone_id||p_phone,30,60);
  insert into public.wa_conversations(phone,phone_id,last_inbound) values(p_phone,p_phone_id,least(coalesce(p_at,now()),now())) on conflict(phone_id,phone) do update set last_inbound=greatest(public.wa_conversations.last_inbound,excluded.last_inbound);
 end if;
 select * into conv from public.wa_conversations where phone=p_phone and phone_id=p_phone_id;
 select coalesce(jsonb_agg(jsonb_build_object('id',w.id,'empresa_id',w.empresa_id,'nombre',e.nombre)),'[]'::jsonb) into available
 from public.wa_links w join public.usuarios u on u.id=w.usuario_id and u.activo join public.usuarios_empresas m on m.usuario_id=w.usuario_id and m.empresa_id=w.empresa_id and m.activo join public.empresas e on e.id=w.empresa_id and e.activo join public.wa_config c on c.empresa_id=w.empresa_id and c.enabled
 where w.phone=p_phone and w.phone_id=p_phone_id and w.enabled;
 if p_company is not null then select * into l from public.wa_links where id in(select (x->>'id')::uuid from jsonb_array_elements(available)x) and empresa_id=p_company;
 elsif conv.link_id is not null then select * into l from public.wa_links where id=conv.link_id and id in(select (x->>'id')::uuid from jsonb_array_elements(available)x);
 elsif jsonb_array_length(available)=1 then select * into l from public.wa_links where id=(available->0->>'id')::uuid; end if;
 if l.id is not null and conv.link_id is distinct from l.id then update public.wa_conversations set link_id=l.id,pending='{}' where phone=p_phone and phone_id=p_phone_id returning * into conv; end if;
 if p_company is not null and l.id is null then raise exception 'Empresa no vinculada'; end if;
 return jsonb_build_object('link',to_jsonb(l),'companies',available,'conversation',to_jsonb(conv),'config',(select to_jsonb(c) from public.wa_config c where c.empresa_id=l.empresa_id));
end $$;

create function public.wa_pending(p_link uuid,p_pending jsonb) returns void language plpgsql security definer set search_path='' as $$
begin update public.wa_conversations set pending=p_pending where link_id=p_link; end $$;

create function public.wa_actor_action(p_link uuid,p_action text,p_args jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
<<actor>>
declare l public.wa_links; t public.tareas; e public.evidencias; op public.wa_operations; result jsonb; task_id uuid:=(p_args->>'task_id')::uuid; operation uuid:=(p_args->>'operation_id')::uuid;
begin
 select * into strict l from public.wa_links w where w.id=p_link and w.enabled and exists(select 1 from public.wa_config c where c.empresa_id=w.empresa_id and c.enabled);
 perform set_config('request.jwt.claim.sub',l.usuario_id::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',l.usuario_id,'role','authenticated')::text,true);
 if not privado.es_miembro(l.empresa_id) then raise exception 'Usuario sin acceso'; end if;
 if p_action='list' then
  select coalesce(jsonb_agg(x),'[]'::jsonb) into result from (
   select t.id,t.titulo,t.estado,t.fecha_inicio,t.fecha_fin,t.criticidad,t.version,b.nombre tablero from public.tareas t join public.tableros b on b.id=t.tablero_id
   where t.empresa_id=l.empresa_id and t.responsable_id=l.usuario_id and privado.ve_tarea(t.id)
    and (not coalesce((p_args->>'pending_only')::boolean,false) or t.estado<>'finalizado')
    and (nullif(p_args->>'status','') is null or t.estado::text=p_args->>'status')
    and (not coalesce((p_args->>'overdue')::boolean,false) or t.fecha_fin<now() and t.estado<>'finalizado')
    and (nullif(p_args->>'before','') is null or t.fecha_inicio<=(p_args->>'before')::timestamptz)
    and (nullif(p_args->>'after','') is null or t.fecha_fin>=(p_args->>'after')::timestamptz)
   order by case when coalesce((p_args->>'urgent')::boolean,false) then case t.criticidad when 'alta' then 0 when 'media' then 1 else 2 end end,t.fecha_fin,t.id limit 20 offset least(greatest(coalesce((p_args->>'offset')::integer,0),0),10000)
  )x;
 elsif p_action='summary' then
  if not privado.es_administrador(l.empresa_id) and not privado.lider_en_empresa(l.empresa_id) then raise exception 'Resumen reservado a administradores y líderes'; end if;
  select coalesce(jsonb_agg(x),'[]'::jsonb) into result from(select t.responsable_id,u.nombre_completo,t.estado,count(*) total,count(*) filter(where t.estado<>'finalizado' and t.fecha_fin<now()) vencidas,
   count(*) filter(where exists(select 1 from public.wa_audit a where a.action='impedimento' and a.details->>'task_id'=t.id::text and a.created_at>coalesce(t.fecha_finalizacion,'-infinity'::timestamptz))) impedimentos
   from public.tareas t join public.usuarios u on u.id=t.responsable_id where t.empresa_id=l.empresa_id and privado.ve_tarea(t.id) and privado.gestiona_equipo(t.equipo_id) group by t.responsable_id,u.nombre_completo,t.estado order by u.nombre_completo limit 100)x;
 else
  select * into strict t from public.tareas where id=task_id and empresa_id=l.empresa_id;
  perform privado.bloquear_empresa(t.empresa_id);
  if not privado.ve_tarea(t.id) then raise exception 'Tarea sin acceso'; end if;
  if p_action='detail' then
   result:=to_jsonb(t)||jsonb_build_object('tablero',(select nombre from public.tableros where id=t.tablero_id),'equipo',(select nombre from public.equipos where id=t.equipo_id),'imagenes',coalesce((select jsonb_agg(jsonb_build_object('id',e.id,'ruta',e.ruta_archivo)) from (select * from public.evidencias where tarea_id=t.id and estado_carga='confirmada' and tipo='imagen' order by fecha_creacion desc limit 5)e),'[]'::jsonb));
  else
   if not privado.gestiona_tarea(t.id) then raise exception 'Acción sin permisos'; end if;
   if p_action='validate' then
    if not exists(select 1 from public.tableros where id=t.tablero_id and estado='activo') then raise exception 'Tablero finalizado'; end if;
    if p_args->>'kind'='progress' and not privado.trabaja_tarea(t.id) then raise exception 'La tarea no permite avances'; end if;
    result:=jsonb_build_object('ok',true);
   elsif p_action='prepare' then
    result:=public.preparar_transicion(t.id,(p_args->>'version')::integer,(p_args->>'state')::public.estado_trabajo,operation,p_args->>'name','imagen',p_args->>'extension',false);
   elsif p_action='commit' then
    result:=public.guardar_transicion(t.id,(p_args->>'version')::integer,(p_args->>'state')::public.estado_trabajo,operation,p_args->>'comment',(p_args->>'evidence_id')::uuid);
   elsif p_action in ('comment','blocker','progress_prepare','progress_commit') then
    if not privado.trabaja_tarea(t.id) then raise exception 'La tarea no permite avances'; end if;
    select * into op from public.wa_operations where id=operation for update;
    if found and (op.link_id<>l.id or op.tarea_id<>t.id) then raise exception 'Operación ajena'; end if;
    if op.result is not null then return op.result; end if;
    if op.id is null then insert into public.wa_operations(id,link_id,tarea_id,kind) values(operation,l.id,t.id,p_action) returning * into op; end if;
    if p_action='progress_prepare' then
     if op.evidencia_id is null then
      if p_args->>'extension' not in ('jpg','png') then raise exception 'Formato inválido'; end if;
      insert into public.evidencias(empresa_id,tarea_id,nombre_archivo,tipo,ruta_archivo) values(t.empresa_id,t.id,'avance.'||(p_args->>'extension'),'imagen',t.empresa_id||'/'||t.id||'/'||operation||'.'||(p_args->>'extension')) returning * into e;
      update public.wa_operations set evidencia_id=e.id where id=operation;
     else select * into e from public.evidencias where id=op.evidencia_id; end if;
     return to_jsonb(e);
    elsif p_action='progress_commit' then
     select * into strict e from public.evidencias where id=op.evidencia_id and estado_carga='pendiente';
     if not exists(select 1 from storage.objects where bucket_id='evidencias-tareas' and name=e.ruta_archivo) then raise exception 'Fotografía sin guardar'; end if;
     update public.evidencias set estado_carga='confirmada' where id=e.id;
     perform privado.evento(t.id,'avance_fotografico',jsonb_build_object('evidencia_id',e.id,'canal','whatsapp'));
    else
     if length(btrim(coalesce(p_args->>'comment','')))=0 then raise exception 'Escribe un comentario'; end if;
     insert into public.comentarios_tarea(empresa_id,tarea_id,contenido) values(t.empresa_id,t.id,case when p_action='blocker' then '[Impedimento] ' else '' end||left(p_args->>'comment',4500));
     perform privado.evento(t.id,case when p_action='blocker' then 'impedimento_reportado' else 'avance_registrado' end,jsonb_build_object('canal','whatsapp'));
    end if;
    result:=jsonb_build_object('ok',true,'task_id',t.id);
    update public.wa_operations set result=actor.result where id=operation;
   else raise exception 'Herramienta no permitida'; end if;
  end if;
 end if;
 insert into public.wa_audit(empresa_id,usuario_id,action,operation_id,details) values(l.empresa_id,l.usuario_id,case when p_action='blocker' then 'impedimento' else p_action end,operation,jsonb_build_object('task_id',task_id));
 return result;
end $$;

create function public.wa_budget(p_empresa uuid,p_calls integer,p_tokens integer,p_reserve integer) returns boolean language plpgsql security definer set search_path='' as $$
declare r public.wa_usage; begin
 insert into public.wa_usage(empresa_id) values(p_empresa) on conflict do nothing;
 select * into strict r from public.wa_usage where empresa_id=p_empresa and day=current_date for update;
 if r.calls>=p_calls or r.reserved_tokens+p_reserve>p_tokens then return false; end if;
 update public.wa_usage set calls=calls+1,reserved_tokens=reserved_tokens+p_reserve where empresa_id=p_empresa and day=current_date;
 return true;
end $$;

create function privado.wa_assignment() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_op='INSERT' or new.responsable_id is distinct from old.responsable_id then
  perform public.wa_enqueue('assignment','assignment:'||new.id||':'||new.version,jsonb_build_object('task_id',new.id,'assignee',new.responsable_id),new.empresa_id,new.responsable_id);
 end if;
 return new;
end $$;
create trigger wa_assignment after insert or update of responsable_id on public.tareas for each row execute function privado.wa_assignment();

-- Validate at COMMIT: guardar_transicion confirms the image after updating the task.
-- Old attachments, a pending reservation, a different version or a direct state API cannot satisfy this.
create function privado.wa_require_completion_photo() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.estado='finalizado' and (tg_op='INSERT' or old.estado is distinct from new.estado) and not exists(
  select 1 from public.transiciones_tarea c join public.evidencias e on e.transicion_id=c.id join storage.objects o on o.bucket_id='evidencias-tareas' and o.name=e.ruta_archivo
  where c.tarea_id=new.id and c.empresa_id=new.empresa_id and c.estado='confirmada' and c.estado_destino='finalizado'
   and (c.resultado->'tarea'->>'version')::integer=new.version and c.version_origen=new.version-1
   and e.estado_carga='confirmada' and e.tipo='imagen' and e.usuario_creacion=new.usuario_finalizacion
   and coalesce(o.metadata->>'mimetype','') in ('image/jpeg','image/png','image/webp','image/heic','image/heif')
 ) then raise exception 'Para finalizar adjunta una nueva fotografía de evidencia y guarda la transición completa'; end if;
 return null;
end $$;
create constraint trigger wa_completion_photo after insert or update on public.tareas deferrable initially deferred for each row execute function privado.wa_require_completion_photo();

-- Only service_role may impersonate the verified account or operate the queue.
do $$ declare f record; begin
 for f in select p.oid::regprocedure signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname like 'wa_%' loop
  execute format('revoke all on function %s from public,anon,authenticated',f.signature);
  execute format('grant execute on function %s to service_role',f.signature);
 end loop;
 for f in select p.oid::regprocedure signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='privado' and p.proname like 'wa_%' loop
  execute format('revoke all on function %s from public,anon,authenticated',f.signature);
 end loop;
end $$;
grant execute on function public.wa_link_start(uuid,text,text,boolean),public.wa_account(uuid,text,jsonb),public.wa_admin(uuid,text,jsonb) to authenticated;
commit;
