> Actualización de despliegue: usar [la guía de Vercel](04_CONFIGURACION_VERCEL.md). Las referencias a Netlify de este documento corresponden al adaptador anterior. En Vercel se añade `CRON_SECRET`, no se necesita `URL` y el cron nativo por minuto requiere Pro; Hobby necesita un programador externo.

# 07 · Puesta en producción

## Secuencia de activación

1. **Ensayo y copia de seguridad.** Verifica esquema español y respaldo de Supabase. Ejecuta primero las migraciones del bot en ensayo y la guía `06`. Comprueba que el nombre de empresa y los usuarios usados no sean los de un cliente real sin consentimiento.
2. **Clientes actualizados.** Publica la web con la fotografía obligatoria y distribuye una versión móvil que contenga el mismo cambio antes de instalar la regla global. Esta entrega no construye un APK ni publica una web. La base rechazará la finalización sin fotografía también desde clientes antiguos.
3. **Credenciales.** Configura claves privadas únicamente en Netlify Functions. Comprueba que no estén en Git ni en archivos del frontend. Usa un token de sistema de Meta, no un token de pruebas a punto de vencer. Registra responsables de rotación y revocación.
4. **Número y plantilla.** Comprueba registro/validación del número real, nombre del negocio, permisos, facturación y plantilla aprobada sin variables. Verifica los costos actuales con el propietario y que cada destinatario haya consentido.
5. **Sitio y funciones.** Publica el bot como sitio separado, configura `BOT_ADMIN_ORIGIN` con su origen HTTPS real y verifica `api`, `tick` y `process`. Confirma que la función programada está activa en el despliegue publicado. No actives si el plan no permite el procesamiento Background necesario.
6. **Empresa piloto.** Con `BOT_ENABLED=true`, habilita solo una empresa desde el portal. Vincula dos integrantes y un líder mediante código. Deja `AI_ENABLED=false` hasta que los comandos y evidencias funcionen.
7. **IA controlada.** Activa IA en una empresa piloto, con cuotas pequeñas, presupuesto del proyecto y revisiones de uso. Si falla el proveedor, el módulo no confirma cambios inventados. Conserva acceso a la app como alternativa.
8. **Observación.** Durante el piloto revisa errores, cola pendiente, tiempos de respuesta, consentimientos y entregas. Comprueba especialmente cambios de responsable, usuario desactivado, empresa equivocada, fotografía inválida y pérdida de respuesta de Meta.
9. **Apertura gradual.** Habilita más integrantes/empresas solo tras completar la guía. La programación inicial procesa lotes limitados y prioriza no duplicar operaciones; mide acumulación de trabajos antes de ampliar volumen.

## Incidencias y reintentos

Un error 429 o una caída recuperable se reintenta con espera. Un resultado de envío incierto queda en `uncertain`; revisa primero `wa_delivery`, los webhooks y Meta. Para un reintento manual usa la API administrativa `POST /api/admin` con tu JWT y cuerpo `{"company_id":"UUID_REAL","action":"retry","options":{"job_id":"UUID_REAL","accept_duplicate_risk":false}}`. No pegues el JWT en un manual ni en una captura. Los `uncertain` exigen `accept_duplicate_risk:true`: úsalo solo tras revisión consciente, porque el proveedor pudo haber entregado el mensaje.

Para pausar una empresa, desactívala en su configuración del portal. Para una pausa global pon `BOT_ENABLED=false` en Netlify y redespliega. No borres vínculos ni tareas como método de pausa. Para un incidente de credenciales, revoca y rota las claves desde el proveedor antes de reactivar.

Programa o ejecuta periódicamente `select public.wa_cleanup();` como administrador de base de datos. Revisa retención de auditoría y políticas internas de datos personales. Los números y mensajes son datos privados incluso aunque no se impriman en logs.

## Límites explícitos

- No se promete entrega exactamente una vez en una API externa que no comparte transacción con PostgreSQL. La cola evita duplicados internos y conserva los casos inciertos para revisión.
- Un número de WhatsApp compartido está preparado; múltiples tokens/números requieren separar despliegues o ampliar el resolvedor de credenciales por canal.
- No hay estado "bloqueado" ni porcentaje de avance en el esquema: se registran impedimentos, comentarios y fotos.
- No se han inventado proyectos ni adjuntos iniciales inexistentes. Se envían las imágenes confirmadas que realmente estén asociadas a la tarea.
- El portal es independiente: las cuentas son las mismas de Supabase, no una base alternativa de usuarios.
