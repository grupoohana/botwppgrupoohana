# 03 · Supabase

## Antes de aplicar

Abre [Supabase Dashboard](https://supabase.com/dashboard), selecciona el proyecto correcto y revisa **Table Editor**: deben existir las tablas españolas del aplicativo, incluidas `transiciones_tarea` y `evidencias.transicion_id`. Este módulo no corresponde al esquema genérico de un proyecto nuevo. Las pruebas locales ejecutan las migraciones originales relevantes antes de instalar las del bot.

Haz copia de seguridad y prueba en un proyecto de ensayo. La validación de fotografía al finalizar cambia una regla global: coordina la actualización de la web y los clientes móviles antes de instalarla en producción. Los APK antiguos recibirán un rechazo si intentan finalizar sin evidencia; no pueden saltarse la nueva regla.

## Instalación

En **SQL Editor → New query**, abre y ejecuta, en este orden, el contenido completo de:

1. `whatsapp-bot/migrations/202610210101_whatsapp.sql`
2. `whatsapp-bot/migrations/202610210102_automation.sql`
3. `whatsapp-bot/migrations/202610210103_portal.sql`
4. `whatsapp-bot/migrations/202610210104_delivery_controls.sql`

No ejecutes otra vez `202610040101_modelo_espanol.sql` en el proyecto real: fue diseñado para una base vacía. Las migraciones del bot son de una sola aplicación, con transacciones; un error revierte esa migración. Si gestionas migraciones mediante CLI, copia estos cuatro archivos al directorio de migraciones de una copia de despliegue y registra el historial con el procedimiento habitual del proyecto; no los dupliques en dos procesos de instalación.

## Estructuras agregadas

`wa_config` guarda ajustes por empresa; `wa_link_codes` códigos hash de corta duración; `wa_links` identidades verificadas y preferencias; `wa_conversations` empresa activa y solicitud pendiente; `wa_jobs` cola; `wa_delivery` entregas; `wa_operations` idempotencia de avances; `wa_audit` auditoría del canal; `wa_usage` cuotas; `wa_rate_limits` límites temporales; `wa_template_slots` consolidación de plantillas. No hay copias de tareas/usuarios/equipos.

Todas las tablas nuevas tienen RLS habilitado y revocan acceso directo a usuarios anónimos y autenticados. El portal usa RPC que verifican `auth.uid()` y el rol. El puente de identidad y las funciones de cola son exclusivos de `service_role`. Nunca concedas `wa_actor_action` a `authenticated` ni permitas DML directo sobre `wa_links`.

## Storage y secretos

En **Storage → evidencias-tareas**, confirma que el bucket es **privado**. Se reutilizan las rutas `empresa/tarea/archivo`, permisos originales y metadatos de objetos. No cambies a público para que WhatsApp funcione. El trabajador descarga con la credencial de servidor y carga a Meta; si un formato no se puede enviar, genera un enlace firmado de 5 minutos. Una fotografía recibida usa la reserva de transición, se carga y solo después se confirma.

En **Project Settings → API / API Keys** copia la URL del proyecto a `SUPABASE_URL` y la clave de servidor `service_role` a `SUPABASE_SERVICE_ROLE_KEY` en **Netlify → Environment variables**, ámbito Functions. No uses la clave publishable del frontend como clave de servidor, ni copies `service_role` a `EXPO_PUBLIC_*`.

La política de finalización comprueba un objeto real y su MIME de imagen. El bot además valida bytes/tipo/hash. No considera evidencia previa de creación como evidencia de finalización. El inicio sigue permitiendo cero imágenes.

## Comprobación

En SQL Editor verifica permisos, sin consultar ni publicar secretos:

```sql
select has_function_privilege('authenticated','public.wa_actor_action(uuid,text,jsonb)','execute'); -- false
select has_table_privilege('authenticated','public.wa_jobs','select'); -- false
select tgname from pg_trigger where tgname in ('wa_completion_photo','wa_assignment','wa_image_event');
select kind,status,attempts,last_error,created_at from public.wa_jobs order by created_at desc limit 20;
```

Inicia sesión en el portal con un administrador, selecciona la empresa y guarda la configuración. Vincula un celular con código. Crea una tarea asignada a esa cuenta y comprueba que aparece `assignment`, después `outbound`, y el identificador en `wa_delivery` tras enviar. Si el responsable cambia antes de procesar, el trabajador descarta el aviso antiguo.

## Conservación y mantenimiento

Los cuerpos entrantes se borran al completar su trabajo. `wa_cleanup()` elimina códigos vencidos, límites viejos y datos de cola/entregas resueltos tras 30 días; puede ejecutarse desde una tarea administrativa de mantenimiento. Los comentarios/evidencias del negocio conservan el historial oficial y no se borran por esa limpieza. Revisa trabajos `failed`/`uncertain`, reservas de evidencia que fallaron y la cola existente `archivos_eliminados` antes de borrar objetos. No elimines fotografías confirmadas manualmente.

Fuentes: [funciones seguras](https://supabase.com/docs/guides/database/functions) y [RLS](https://supabase.com/docs/guides/database/postgres/row-level-security).
