begin;
create table public.wa_template_slots(link_id uuid primary key references public.wa_links(id) on delete cascade,job_id uuid not null references public.wa_jobs(id) on delete cascade,reserved_at timestamptz not null default now());
alter table public.wa_template_slots enable row level security;
revoke all on public.wa_template_slots from public,anon,authenticated;
grant all on public.wa_template_slots to service_role;
create function public.wa_template_gate(p_link uuid,p_job uuid) returns boolean language plpgsql security definer set search_path='' as $$
declare r public.wa_template_slots; begin
 insert into public.wa_template_slots(link_id,job_id) values(p_link,p_job) on conflict do nothing;
 select * into strict r from public.wa_template_slots where link_id=p_link for update;
 if r.job_id=p_job then return true; end if;
 if r.reserved_at>now()-interval '24 hours' then return false; end if;
 update public.wa_template_slots set job_id=p_job,reserved_at=now() where link_id=p_link;
 return true;
end $$;
revoke all on function public.wa_template_gate(uuid,uuid) from public,anon,authenticated;
grant execute on function public.wa_template_gate(uuid,uuid) to service_role;

create or replace function public.wa_finish(p_id uuid,p_lease uuid,p_status text,p_error text default null) returns void language plpgsql security definer set search_path='' as $$
begin
 if p_status not in ('done','pending','failed','uncertain') then raise exception 'Estado de cola inválido'; end if;
 update public.wa_jobs set status=case when p_status='pending' and attempts>=6 and coalesce(p_error,'') not in ('waiting_window','waiting_hours') then 'failed' else p_status end,
  last_error=left(p_error,100),lease_until=null,attempts=case when p_error in ('waiting_window','waiting_hours') then greatest(attempts-1,0) else attempts end,
  available_at=case when p_error in ('waiting_window','waiting_hours') then now()+interval '15 minutes' else now()+make_interval(secs=>least(3600,power(2,attempts)::integer*15)) end,
  updated_at=now(),payload=case when kind='inbound' and p_status='done' then '{}'::jsonb else payload end
 where id=p_id and lease_token=p_lease and status='processing';
end $$;

-- Explicit admin retry; uncertain messages require an affirmative duplicate-risk acknowledgement.
create function public.wa_retry(p_empresa uuid,p_job uuid,p_accept_duplicate_risk boolean default false) returns void language plpgsql security definer set search_path='' as $$
declare j public.wa_jobs; begin
 perform privado.exigir_administrador(p_empresa);
 select * into strict j from public.wa_jobs where id=p_job and empresa_id=p_empresa for update;
 if j.status not in ('failed','uncertain') or j.status='uncertain' and not p_accept_duplicate_risk then raise exception 'Revisa el resultado del proveedor antes de reintentar'; end if;
 update public.wa_jobs set status='pending',attempts=0,available_at=now(),last_error=null where id=j.id;
 insert into public.wa_audit(empresa_id,usuario_id,action,details) values(p_empresa,auth.uid(),'reintento_manual',jsonb_build_object('job_id',j.id,'uncertain',j.status='uncertain'));
end $$;
revoke all on function public.wa_retry(uuid,uuid,boolean) from public,anon,authenticated;
grant execute on function public.wa_retry(uuid,uuid,boolean) to authenticated,service_role;
commit;
