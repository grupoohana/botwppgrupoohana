> Actualización de despliegue: usar [la guía de Vercel](04_CONFIGURACION_VERCEL.md). Las referencias a Netlify de este documento corresponden al adaptador anterior. En Vercel se añade `CRON_SECRET`, no se necesita `URL` y el cron nativo por minuto requiere Pro; Hobby necesita un programador externo.

# 02 · Configurar Meta y WhatsApp

Necesitas acceso administrativo al negocio y un número controlado por tu organización. Meta puede exigir verificación empresarial, revisión de permisos y un método de pago según el uso. No se presupone aprobación. Algunas páginas técnicas de Meta devolvieron 429 durante esta implementación; confirma los nombres actuales del panel en tu cuenta. No cambies valores copiando identificadores de ejemplos.

## Preparar cuenta y pruebas

1. Abre [Meta Business](https://business.facebook.com/) con tu cuenta empresarial. En **Configuración del negocio / Información del negocio**, crea o selecciona el portafolio propietario y comprueba sus datos. Conserva su identificador para la administración en Meta; no es el UUID de empresa de Alba Flow.
2. Abre [Meta for Developers: aplicaciones](https://developers.facebook.com/apps/). Selecciona **Crear aplicación**, el caso de uso de WhatsApp y el portafolio correspondiente. Si tu aplicación ya tiene WhatsApp, úsala. Los asistentes y nombres del caso de uso pueden variar por cuenta.
3. Dentro de la aplicación abre **WhatsApp → Configuración de la API / API Setup**. Usa el número de prueba y agrega tu celular como destinatario de pruebas, completando el código que Meta envíe. Verifica un mensaje de prueba desde ese panel antes de involucrar al bot.
4. Copia el **Phone number ID / Identificador del número de teléfono** en `META_PHONE_NUMBER_ID` del sitio Netlify del bot. No copies el número visible ni el identificador de WhatsApp Business Account en esa variable.
5. Copia el token temporal de pruebas en `META_ACCESS_TOKEN`. Es temporal: revisa su caducidad. En producción reemplázalo por el token de un usuario del sistema con acceso al activo WhatsApp. Nunca lo envíes al chat del bot.
6. En **Configuración de la aplicación → Básica**, revela el secreto de aplicación y guárdalo como `META_APP_SECRET` en las variables privadas de Functions. No es el token de acceso.
7. Revisa en el panel o [documentación de Graph](https://developers.facebook.com/docs/graph-api/) la versión habilitada para la app y configura `META_GRAPH_VERSION` con el formato `vN.N`. El módulo no fija una versión supuestamente vigente.

## Webhook

1. Primero despliega el sitio del bot y copia su URL HTTPS real en Netlify. Ejemplo de patrón, **no un despliegue existente**: `https://TU-SITIO.netlify.app`.
2. Genera un secreto aleatorio diferente del secreto de aplicación. Desde una terminal local puedes usar `node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"`. Guarda el valor en `META_VERIFY_TOKEN` de Netlify. No lo publiques en capturas ni en Git.
3. En **WhatsApp → Configuración → Webhooks → Editar**, introduce `https://TU-SITIO.netlify.app/api/webhook` como **Callback URL** y exactamente el mismo valor de `META_VERIFY_TOKEN` como **Verify token**. Pulsa **Verificar y guardar**. El GET de verificación funciona aunque el envío todavía esté deshabilitado.
4. En los campos del webhook, suscribe **messages**: este campo incluye mensajes entrantes y estados de entrega. Si el panel solicita suscribir la aplicación a la cuenta de WhatsApp Business, completa esa asociación; no basta guardar una URL sin suscribir la cuenta.
5. Configura `BOT_ENABLED=true`, vuelve a desplegar y manda un mensaje desde el celular autorizado. En Netlify **Functions → api → Logs**, comprueba ejecución sin errores. En Supabase debe aparecer una fila `inbound` en `wa_jobs` y después una salida. La función `process` procesa el trabajo; un ACK del webhook no significa que la respuesta ya se haya enviado.

## Plantilla aprobada

En [WhatsApp Manager](https://business.facebook.com/wa/manage/), elige la cuenta correcta y abre **Administrar plantillas de mensajes**. Crea una plantilla **utilitaria**, por ejemplo `alba_actualizacion_tareas`, idioma Español, con texto fijo y **sin variables, botones obligatorios ni cabecera multimedia**:

> Tienes actualizaciones de tus tareas en Alba Flow. Responde TAREAS para consultar los detalles y registrar tu avance. Si no deseas recibir avisos, responde BAJA.

Espera aprobación real. En el portal del bot, configura ese nombre exacto y el código de idioma exacto de Meta (`es`, `es_PE` u otro realmente aprobado). El código envía la plantilla sin componentes. Si usas otra estructura, debes adaptar sus componentes antes de habilitarla. Fuera de la ventana de atención no se envía libremente el detalle ni una imagen: la plantilla invita al usuario a responder.

## Número definitivo y permisos

En WhatsApp Manager agrega el número definitivo y verifica su posesión por SMS o llamada, según lo permita Meta. Comprueba requisitos si ese número ya se utiliza en WhatsApp/WhatsApp Business: no presupongas que puede migrarse o coexistir sin un procedimiento de Meta. Revisa nombre para mostrar y registro del número; si Meta requiere registro adicional de API o PIN de verificación en dos pasos, sigue su asistente oficial antes de probar mensajes.

En **Configuración del negocio → Usuarios → Usuarios del sistema**, asigna los activos necesarios y genera el token para la aplicación. Revisa `whatsapp_business_messaging` para mensajería y `whatsapp_business_management` para administración de activos; la disponibilidad depende de los permisos aprobados. Copia el token solo a Netlify y configura rotación. Cambia `META_PHONE_NUMBER_ID` al identificador del número definitivo y actualiza `phone_id` en cada empresa del portal. No reutilices vínculos del número de prueba sin volver a verificar el nuevo canal.

Revisa el modo de la aplicación, la verificación empresarial, permisos efectivos, número registrado y facturación. La prueba final debe salir desde el número real hacia un integrante que haya aceptado y verificado la vinculación.

## Costos y referencias

Consulta [tarifas oficiales](https://business.whatsapp.com/products/platform-pricing) antes de activar destinatarios reales: los cargos varían por mercado/categoría, y no se garantiza gratuidad. [Colección oficial de Meta en Postman](https://www.postman.com/meta/whatsapp-business-platform/overview) y [descarga multimedia](https://www.postman.com/meta/whatsapp-business-platform/request/zsq66eh/download-media) permiten contrastar los endpoints. Usa también la [documentación oficial de WhatsApp](https://developers.facebook.com/documentation/business-messaging/whatsapp/overview) desde tu sesión empresarial si el acceso público está limitado.
