# WhatsApp desde la app

La app móvil y la web tienen la sección **Configuración → WhatsApp**. No hace falta iniciar sesión nuevamente en el portal del bot. Las tareas consultadas o modificadas por WhatsApp son las mismas de la app en Supabase, con los permisos existentes.

## Preparación

- Instala o publica la versión de la app que incluye esta sección; un APK anterior no la contiene.
- El backend del bot debe tener desplegados los cambios de vinculación desde la app.
- `EXPO_PUBLIC_WHATSAPP_BOT_URL` en la app es solo una dirección pública HTTPS. Por defecto se usa `https://botwppgrupoohana.vercel.app`. No contiene tokens ni claves de servidor.
- Para la web, configura `APP_URL` en las variables Production del bot con el dominio real de la web y redespliega. El backend permite únicamente el origen de ese dominio y el del portal (`BOT_ADMIN_ORIGIN`); no utiliza CORS abierto. La app nativa no necesita configurar un origen de navegador.
- Deben estar activos el webhook, la suscripción `messages`, `BOT_ENABLED=true` y el programador que llama a `/api/cron`. Esto no se configura automáticamente desde la app.

## Administrador

Abre Configuración → WhatsApp → Configurar WhatsApp de la empresa. Carga la configuración actual al abrirla y conserva sus valores. Configura el identificador de número de Meta, los horarios de avisos y la plantilla aprobada si se necesitan avisos fuera de la ventana de conversación. Habilita WhatsApp para la empresa y guarda. Las claves de Meta, Supabase de servidor y OpenAI permanecen en Vercel. La IA requiere habilitación tanto en el servidor como en la empresa.

## Cualquier usuario con acceso a la empresa

1. Abre Configuración → WhatsApp y escribe su propio número con código de país.
2. Acepta recibir avisos y pulsa Vincular mi WhatsApp.
3. Pulsa Abrir WhatsApp para verificar y envía el mensaje prellenado desde ese mismo número. La app abre la conversación del número de Meta; no envía el mensaje por sí sola. Si no se puede consultar el número público en Meta, el código queda disponible para copiar y enviar al bot.
4. Regresa a la app y pulsa Comprobar vinculación. Solo se muestra como vinculado después de que el backend haya procesado el mensaje de verificación.
5. Envía TAREAS en WhatsApp para ver sus tareas asignadas. Desde la app se pueden guardar preferencias y desvincular el número de la empresa actual.

Los códigos vencen en diez minutos y no se guardan en almacenamiento persistente de la app. Cambiar de empresa o cuenta limpia el estado del formulario. No hay consultas de WhatsApp mientras su sección está cerrada. La configuración administrativa se solicita solo al abrir su formulario; los RPC existentes aplican los permisos en Supabase.

La prueba de interfaz usa Supabase y WhatsApp simulados: no acredita entrega real de mensajes, apertura nativa de WhatsApp ni funcionamiento del programador en producción. Esas comprobaciones requieren la versión instalada, una cuenta y un número de prueba autorizados.
