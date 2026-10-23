-- 01. Modelo nuevo. SOLO proyecto vacío. No borra ni convierte el modelo anterior.
begin;
do $$ begin
  if to_regclass('public.companies') is not null or to_regclass('public.empresas') is not null then
    raise exception 'El proyecto ya tiene un modelo. Use un proyecto vacío; no mezcle scripts anteriores y nuevos.';
  end if;
end $$;
create schema if not exists privado;
revoke all on schema privado from public;
create type public.estado_trabajo as enum ('por_hacer','en_curso','en_revision','finalizado');
create type public.criticidad_trabajo as enum ('baja','media','alta');
create type public.estado_tablero as enum ('activo','finalizado');
create type public.rol_empresa as enum ('administrador','miembro');
create type public.rol_equipo as enum ('lider','miembro');

create table public.usuarios (
  id uuid primary key references auth.users(id) on delete restrict,
  nombre_completo text not null check(length(btrim(nombre_completo)) between 1 and 120),
  nombre_usuario text unique check(nombre_usuario ~ '^[a-z0-9._-]{3,50}$'),
  telefono text check(length(telefono)<=30), cargo text check(length(cargo)<=120),
  biografia text check(length(biografia)<=1000), ruta_foto_perfil text,
  activo boolean not null default true
);
create table public.empresas (
  id uuid primary key default gen_random_uuid(), nombre text not null check(length(btrim(nombre)) between 1 and 120),
  identificador text not null unique check(identificador ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  zona_horaria text not null default 'America/Bogota', activo boolean not null default true
);
create table public.usuarios_empresas (
  id uuid primary key default gen_random_uuid(), empresa_id uuid not null references public.empresas(id),
  usuario_id uuid not null references public.usuarios(id), rol public.rol_empresa not null default 'miembro',
  activo boolean not null default true, unique(empresa_id,usuario_id)
);
create table public.areas (
  id uuid primary key default gen_random_uuid(), empresa_id uuid not null references public.empresas(id),
  nombre text not null check(length(btrim(nombre)) between 1 and 120), descripcion text not null default '',
  activo boolean not null default true, unique(empresa_id,id), unique(empresa_id,nombre)
);
create table public.equipos (
  id uuid primary key default gen_random_uuid(), empresa_id uuid not null references public.empresas(id), area_id uuid not null,
  nombre text not null check(length(btrim(nombre)) between 1 and 120), descripcion text not null default '', activo boolean not null default true,
  foreign key(empresa_id,area_id) references public.areas(empresa_id,id), unique(empresa_id,id), unique(empresa_id,area_id,nombre)
);
create table public.miembros_equipo (
  id uuid primary key default gen_random_uuid(), empresa_id uuid not null, equipo_id uuid not null, usuario_id uuid not null,
  rol public.rol_equipo not null default 'miembro', activo boolean not null default true,
  foreign key(empresa_id,equipo_id) references public.equipos(empresa_id,id),
  foreign key(empresa_id,usuario_id) references public.usuarios_empresas(empresa_id,usuario_id),
  unique(empresa_id,equipo_id,usuario_id)
);
create unique index un_lider_activo_por_equipo on public.miembros_equipo(equipo_id) where activo and rol='lider';
create table public.tableros (
  id uuid primary key default gen_random_uuid(), empresa_id uuid not null, equipo_id uuid not null,
  nombre text not null check(length(btrim(nombre)) between 1 and 120), descripcion text not null default '',
  estado public.estado_tablero not null default 'activo',
  foreign key(empresa_id,equipo_id) references public.equipos(empresa_id,id), unique(empresa_id,equipo_id,id), unique(empresa_id,id)
);
create table public.participantes_tablero (
  id uuid primary key default gen_random_uuid(), empresa_id uuid not null, equipo_id uuid not null, tablero_id uuid not null, usuario_id uuid not null,
  foreign key(empresa_id,equipo_id,tablero_id) references public.tableros(empresa_id,equipo_id,id),
  foreign key(empresa_id,equipo_id,usuario_id) references public.miembros_equipo(empresa_id,equipo_id,usuario_id),
  unique(empresa_id,tablero_id,usuario_id)
);
create table public.tareas (
  id uuid primary key default gen_random_uuid(), empresa_id uuid not null, equipo_id uuid not null, tablero_id uuid not null,
  titulo text not null check(length(btrim(titulo)) between 1 and 200), descripcion text not null default '', responsable_id uuid not null,
  fecha_inicio timestamptz not null, fecha_fin timestamptz not null, criticidad public.criticidad_trabajo not null default 'media',
  estado public.estado_trabajo not null default 'por_hacer', version integer not null default 1 check(version>0),
  fecha_finalizacion timestamptz, usuario_finalizacion uuid references public.usuarios(id),
  foreign key(empresa_id,equipo_id,tablero_id) references public.tableros(empresa_id,equipo_id,id),
  foreign key(empresa_id,tablero_id,responsable_id) references public.participantes_tablero(empresa_id,tablero_id,usuario_id),
  check(fecha_fin>=fecha_inicio), check((estado='finalizado')=(fecha_finalizacion is not null and usuario_finalizacion is not null)),
  unique(empresa_id,tablero_id,id), unique(empresa_id,id)
);
create table public.subtareas (
  id uuid primary key default gen_random_uuid(), empresa_id uuid not null, tablero_id uuid not null, tarea_id uuid not null,
  titulo text not null check(length(btrim(titulo)) between 1 and 200), responsable_id uuid not null,
  fecha_inicio timestamptz not null, fecha_fin timestamptz not null, criticidad public.criticidad_trabajo not null default 'media',
  estado public.estado_trabajo not null default 'por_hacer', fecha_finalizacion timestamptz, usuario_finalizacion uuid references public.usuarios(id),
  posicion integer not null default 0 check(posicion>=0),
  foreign key(empresa_id,tablero_id,tarea_id) references public.tareas(empresa_id,tablero_id,id),
  foreign key(empresa_id,tablero_id,responsable_id) references public.participantes_tablero(empresa_id,tablero_id,usuario_id),
  check(fecha_fin>=fecha_inicio), check((estado='finalizado')=(fecha_finalizacion is not null and usuario_finalizacion is not null))
);
create table public.evidencias (
  id uuid primary key default gen_random_uuid(), empresa_id uuid not null, tarea_id uuid not null,
  nombre_archivo text not null check(length(btrim(nombre_archivo)) between 1 and 200),
  tipo text not null check(tipo in ('imagen','archivo')), ruta_archivo text not null unique,
  estado_carga text not null default 'pendiente' check(estado_carga in ('pendiente','confirmada','cancelada')),
  foreign key(empresa_id,tarea_id) references public.tareas(empresa_id,id)
);
create table public.comentarios_tarea (
  id uuid primary key default gen_random_uuid(), empresa_id uuid not null, tarea_id uuid not null,
  contenido text not null check(length(btrim(contenido)) between 1 and 5000),
  foreign key(empresa_id,tarea_id) references public.tareas(empresa_id,id)
);
create table public.eventos_tarea (
  id uuid primary key default gen_random_uuid(), empresa_id uuid not null, tarea_id uuid not null,
  accion text not null, detalles jsonb not null default '{}',
  foreign key(empresa_id,tarea_id) references public.tareas(empresa_id,id)
);
create table public.preferencias_usuario (
  id uuid primary key default gen_random_uuid(), usuario_id uuid not null unique references public.usuarios(id),
  recordatorios boolean not null default true, avisos_revision boolean not null default true
);
create table public.notificaciones (
  id uuid primary key default gen_random_uuid(), empresa_id uuid not null, usuario_id uuid not null, tarea_id uuid,
  titulo text not null, contenido text not null default '', fecha_lectura timestamptz,
  foreign key(empresa_id,usuario_id) references public.usuarios_empresas(empresa_id,usuario_id),
  foreign key(empresa_id,tarea_id) references public.tareas(empresa_id,id)
);
create table public.historial_auditoria (
  id uuid primary key default gen_random_uuid(), empresa_id uuid references public.empresas(id),
  tabla text not null, registro_id uuid not null, operacion text not null check(operacion in ('INSERT','UPDATE','DELETE')),
  datos_anteriores jsonb, datos_nuevos jsonb,
  usuario_creacion uuid references auth.users(id), fecha_creacion timestamptz not null default now(),
  usuario_modificacion uuid references auth.users(id), fecha_modificacion timestamptz not null default now()
);
-- Todos los datos de negocio comparten auditoría; referencias a Auth preservan identidad.
do $$ declare nombre text; begin
  foreach nombre in array array['usuarios','empresas','usuarios_empresas','areas','equipos','miembros_equipo','tableros','participantes_tablero','tareas','subtareas','evidencias','comentarios_tarea','eventos_tarea','preferencias_usuario','notificaciones'] loop
    execute format('alter table public.%I add usuario_creacion uuid references auth.users(id), add fecha_creacion timestamptz not null default now(), add usuario_modificacion uuid references auth.users(id), add fecha_modificacion timestamptz not null default now()',nombre);
    execute format('alter table public.%I enable row level security',nombre);
    execute format('revoke all on public.%I from anon, authenticated',nombre);
  end loop;
end $$;
alter table public.historial_auditoria enable row level security;
revoke all on public.historial_auditoria from anon,authenticated;
create index usuarios_empresas_usuario on public.usuarios_empresas(usuario_id,empresa_id) where activo;
create index miembros_equipo_usuario on public.miembros_equipo(usuario_id,equipo_id) where activo;
create index participantes_tablero_usuario on public.participantes_tablero(usuario_id,tablero_id);
create index tareas_tablero_estado on public.tareas(tablero_id,estado,fecha_fin);
create index tareas_responsable on public.tareas(responsable_id,fecha_fin);
create index subtareas_tarea on public.subtareas(tarea_id,posicion);
create index subtareas_responsable on public.subtareas(responsable_id,estado);
create index evidencias_tarea on public.evidencias(tarea_id);
create index comentarios_tarea_fecha on public.comentarios_tarea(tarea_id,fecha_creacion);
create index eventos_tarea_fecha on public.eventos_tarea(tarea_id,fecha_creacion);
create index notificaciones_usuario on public.notificaciones(usuario_id,fecha_creacion desc);
create index historial_empresa_fecha on public.historial_auditoria(empresa_id,fecha_creacion desc);
create index historial_registro on public.historial_auditoria(tabla,registro_id,fecha_creacion desc);
create index equipos_area on public.equipos(area_id);
create index tableros_equipo on public.tableros(equipo_id);
create index miembros_equipo_equipo on public.miembros_equipo(equipo_id,usuario_id);
create index participantes_tablero_tablero on public.participantes_tablero(tablero_id,usuario_id);
commit;
