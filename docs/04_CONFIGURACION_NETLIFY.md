> Actualización de despliegue: usar [la guía de Vercel](04_CONFIGURACION_VERCEL.md). Las referencias a Netlify de este documento corresponden al adaptador anterior. En Vercel se añade `CRON_SECRET`, no se necesita `URL` y el cron nativo por minuto requiere Pro; Hobby necesita un programador externo.

# 04 · Desplegar el bot en Netlify

El frontend existente y este bot son sitios independientes. No cambies la configuración del sitio que sirve la app.

1. Abre [Netlify](https://app.netlify.com/), **Add new project → Import an existing project**, selecciona el repositorio que contenga esta carpeta y la rama que vas a desplegar. Si la carpeta aún no está en un repositorio remoto, súbela primero sin `.env`, `node_modules`, claves Firebase ni credenciales privadas. No uses un despliegue de archivos estáticos arrastrados: hacen falta Functions.
2. En **Build settings**, usa **Base directory: `whatsapp-bot`**, **Build command: `npm run build`**, **Publish directory: `public`**, **Functions directory: `netlify/functions`**. `netlify.toml` contiene esas rutas relativas al directorio base. Confirma que Netlify está leyendo ese archivo y no uno de otra app. Node debe ser 22 o superior.
3. En **Project configuration → Environment variables → Add a variable**, introduce las variables de `08_VARIABLES_ENTORNO.md`. Marca como privadas las claves y habilita su ámbito **Functions**. No uses valores `EXPO_PUBLIC_*`. Empieza con `BOT_ENABLED=false` y `AI_ENABLED=false`.
4. Guarda y ejecuta **Deploys → Trigger deploy**. Al terminar, copia la URL HTTPS real desde **Project overview**. Configúrala como `BOT_ADMIN_ORIGIN` (sin una ruta, por ejemplo el origen real de tu sitio) y vuelve a desplegar. `APP_URL` debe apuntar a la app web real. No se ha creado ninguna URL en esta entrega.
5. Abre `URL-REAL/api/health`. Debe responder JSON del servicio. `configured` será `true` cuando estén presentes las variables del canal y Supabase; esto comprueba presencia, no aprobación de Meta ni conectividad completa. `enabled:false` es correcto antes de activar.
6. En **Functions**, comprueba las funciones `api`, `tick` y `process`. `tick` tiene horario cada minuto y dispara `process`, que corre en segundo plano. El entorno automático `URL` de Netlify identifica el propio sitio; no lo sustituyas por el dominio de la app. La llamada interna usa `BOT_WORKER_SECRET`.
7. Completa las migraciones, Meta y el portal. Cambia `BOT_ENABLED=true` y vuelve a desplegar. En **Functions → tick → Logs** debe aparecer `worker_dispatched`; en `process`, `worker_batch` con el número de trabajos procesados. La cola es duradera: no depende de mantener un proceso Node o una sesión del navegador abiertos.
8. Las funciones programadas se ejecutan en el despliegue publicado. Un servidor de desarrollo o una vista previa no demuestra que el cron de producción esté funcionando. Verifica horarios en UTC de Netlify; las jornadas de los integrantes se calculan con la zona configurada en la empresa.

## Por qué hay una función Background

La documentación actual da a las funciones programadas un límite de 30 segundos; por eso `tick` solo dispara el trabajo. `process` procesa hasta 60 trabajos por invocación con un presupuesto de 8 minutos, dentro del límite de Background. Las tareas reclaman un lease de 3 minutos y cada petición externa tiene timeout. No se ha añadido Redis, un servidor permanente ni otro proveedor de colas: se reutiliza PostgreSQL.

Revisa disponibilidad, créditos y facturación del plan real antes de publicar. Las funciones de segundo plano admiten reintentos de la plataforma, por lo que la cola y las operaciones SQL mantienen deduplicación propia. Si el volumen supera el procesamiento configurado, aumenta capacidad tras medir la cola o despliega el mismo módulo en un trabajador compatible; no quites los locks ni las claves únicas.

## Actualizaciones y errores

Antes de actualizar ejecuta `npm ci`, `npm run check`, `npm test` en `whatsapp-bot`. Publica migraciones compatibles antes de activar código que las use. Los cambios de evidencia deben coordinarse con la web y el APK. Desactiva `BOT_ENABLED` para pausar procesamiento sin borrar tareas. Las configuraciones `enabled` por empresa permiten pausar solo una empresa.

Un webhook 503 indica que no pudo persistir y Meta podrá repetirlo. Un `uncertain` indica una entrega cuyo resultado no debe adivinarse; consulta estados de Meta antes de autorizar un reenvío manual. No copies cuerpos completos de mensajes ni tokens en incidencias.

Referencias: [configuración de Functions](https://docs.netlify.com/build/functions/configuration/), [Scheduled](https://docs.netlify.com/build/functions/scheduled-functions/) y [Background](https://docs.netlify.com/build/functions/background-functions/).
