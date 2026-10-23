# Publicación en Vercel

Esta guía reemplaza las instrucciones de Netlify para el despliegue actual. La cola, los permisos y los datos siguen en Supabase; no hay que reinstalar migraciones que ya estén aplicadas.

## Plan y ejecución

El `vercel.json` no registra cron nativo para permitir desplegar en Hobby. La ruta protegida `/api/cron` está disponible, pero **no se ejecuta automáticamente**: hay que configurar un programador externo. Hobby solo admite cron nativo diario; cambiar la frecuencia a diaria no sirve para un bot que responde mensajes.

### Hobby: programador externo

Después de publicar, configura en tu programador una petición **GET cada minuto** a `https://DOMINIO-REAL-DEL-BOT/api/cron`, con la cabecera **`Authorization: Bearer VALOR_DE_CRON_SECRET`**. Usa el valor exacto guardado en Vercel Production; no lo pongas en la URL ni en GitHub. El proveedor del programador guardará esta clave: utiliza una clave exclusiva para esta finalidad. No envíes claves de Supabase ni de Meta al programador.

El programador debe admitir cabeceras privadas y solicitudes de hasta 300 segundos. El límite de tiempo de una ejecución puede superar el intervalo; la cola de Supabase controla reclamaciones concurrentes. Configura avisos de fallos y revisa el resultado: 200 indica ejecución atendida, 401 clave incorrecta y 503 fallo del trabajador. Un 200 con `enabled:false` significa que no se procesó nada. Sin programador los mensajes quedan en cola aunque el webhook responda correctamente. El código no crea una cuenta ni registra un trabajo externo por sí solo.

### Pro: cron nativo opcional

Si se usa Pro, se puede añadir al nivel principal de `vercel.json` y redesplegar:

```json
"crons": [{"path": "/api/cron", "schedule": "* * * * *"}]
```

Vercel enviará automáticamente `CRON_SECRET` como Bearer. Usa un solo programador activo. No añadas esta propiedad en Hobby porque impedirá desplegar.

La función cron espera el procesamiento dentro de la solicitud, sin depender de procesos que sigan vivos después de responder. Su duración máxima es 300 segundos; cada lote comienza trabajos durante un máximo de 90 segundos, hasta 60 trabajos. Un trabajo iniciado puede continuar después de esos 90 segundos. La cola persiste el resto, conserva sus bloqueos y controla envíos inciertos. Hay que vigilar tiempos y volumen en producción.

## Repositorio exclusivo del bot

En `grupoohana/botwppgrupoohana` el bot está en la raíz y no incluye la web ni la app móvil. Al importarlo en Vercel, deja **Root Directory en `.`**, Framework Other, instalación `npm ci`, Build `npm run build`, Output `public`, Node 22.x. Sigue desde el paso 4 de abajo. Las rutas que empiezan por `whatsapp-bot/` en los otros manuales se refieren a esta misma raíz. Las pruebas traen un esquema de ejemplo en `tests/fixtures/schema`: es solo para la base de pruebas en memoria y no se instala en producción.

## Si se publica desde el proyecto completo

1. En GitHub sube el código sin `.env`, claves, `node_modules` ni credenciales de Firebase.
2. En Vercel importa el repositorio para la web. **Root Directory: `web`**, Framework: Other, instalación `npm ci`, Build `npm run build`, Output `dist`, Node 22.x. Sus variables públicas de Supabase se toman de `web/.env.example`; no agregues claves de servidor en este proyecto. La exportación de Expo incluye las páginas HTML; `cleanUrls` sirve las rutas sin `.html`. Los enlaces con identificadores de tarea, equipo y tablero vuelven al documento raíz para que Expo resuelva la ruta actual, igual que el servidor de vista previa local. Comprueba abrir y recargar esos enlaces después de publicar.
3. Importa el mismo repositorio como un segundo proyecto para el bot. **Root Directory: `whatsapp-bot`**, Framework: Other, instalación `npm ci`, Build `npm run build`, Output `public`, Node 22.x. Vercel detecta las funciones de `api/` además del portal estático.
4. Copia las variables del archivo local `whatsapp-bot/.env` a **Settings → Environment Variables**, ámbito Production. No subas el archivo a GitHub. Conserva inicialmente `BOT_ENABLED=false` y `AI_ENABLED=false`. No actives credenciales reales ni el bot en Preview.
5. Añade **`CRON_SECRET`**, una clave aleatoria privada de al menos 32 caracteres. Vercel la envía automáticamente como `Authorization: Bearer ...` al cron. Es distinta de `BOT_WORKER_SECRET`, que protege el endpoint manual `POST /api/worker`. No se necesita la variable `URL` de Netlify.
6. Copia el dominio estable de producción del bot, por ejemplo `https://nombre-bot.vercel.app`, en **`BOT_ADMIN_ORIGIN`**, sin barra final. En `APP_URL` coloca el dominio de la web. Redespliega tras cambiar variables.
7. Comprueba `https://nombre-bot.vercel.app/api/health` y abre la raíz para iniciar sesión en el portal. Health verifica presencia de configuración, no valida credenciales externas.

## Conectar Meta

En WhatsApp → Configuración → Webhooks:

- Callback URL: `https://DOMINIO-REAL-DEL-BOT/api/webhook`.
- Verify token: el valor de `META_VERIFY_TOKEN` del backend.
- Verifica y guarda; suscríbete al campo `messages`.

El dominio debe ser accesible desde Meta sin una pantalla de autenticación de Vercel. Usa el dominio estable de producción, no una URL de Preview. La verificación GET funciona con el bot apagado; los eventos POST devuelven 503 mientras siga apagado.

Cuando estén configurados Meta, el número, las plantillas y la empresa en el portal, activa `BOT_ENABLED=true` en Production y redespliega. Comprueba el programador externo (o **Cron Jobs** si usas Pro) y **Logs**: el cron debe responder 200; sin secreto debe responder 401. Prueba vinculación, una consulta y una foto con un número autorizado antes de habilitar al equipo. El procesamiento habitual puede esperar hasta la siguiente ejecución por minuto; no se promete respuesta instantánea.

## Seguridad y transición

Las peticiones pasan como `Request` original: la firma de Meta se calcula sobre los bytes recibidos, sin reconstruir JSON. Solo `public/` se publica como estático. `.vercelignore` excluye archivos locales sensibles y material que no necesita el despliegue. La protección real depende también de no versionar secretos.

Si hay un despliegue anterior en Netlify, apaga su programador y su bot antes de activar Vercel; actualiza el webhook en Meta. Los adaptadores Netlify permanecen disponibles como compatibilidad, pero no se usan en Vercel.

La adaptación está probada localmente; la publicación y la prueba con el dominio real se realizan después de importar el repositorio.

Referencias oficiales: [Node.js y handlers Web Standard](https://vercel.com/docs/functions/runtimes/node-js), [cron y límites por plan](https://vercel.com/docs/cron-jobs/usage-and-pricing), [protección con CRON_SECRET](https://vercel.com/docs/cron-jobs/manage-cron-jobs), [duración de funciones](https://vercel.com/docs/functions/configuring-functions/duration).
