> Actualización de despliegue: usar [la guía de Vercel](04_CONFIGURACION_VERCEL.md). Las referencias a Netlify de este documento corresponden al adaptador anterior. En Vercel se añade `CRON_SECRET`, no se necesita `URL` y el cron nativo por minuto requiere Pro; Hobby necesita un programador externo.

# 08 · Variables de entorno

En local: copia `.env.example` a `.env` dentro de `whatsapp-bot`. En producción: **Netlify → Project configuration → Environment variables**, ámbito Functions, después redespliega. No se necesitan variables nuevas en React ni en el APK. Las claves de servidor no llevan prefijo público.

| Nombre exacto | Uso / dónde obtenerla | Obligatoria | Verificación |
|---|---|---|---|
| `CRON_SECRET` | Secreto privado aleatorio, configurado en Vercel Production; distinto de `BOT_WORKER_SECRET` | Sí en Vercel | `GET /api/cron` sin Bearer correcto devuelve 401; el cron de Vercel lo envía automáticamente |
| `SUPABASE_URL` | URL del proyecto en Supabase → Project Settings → API | Sí | El portal puede autenticar y consultar empresas |
| `SUPABASE_SERVICE_ROLE_KEY` | Clave de servidor `service_role` del mismo proyecto; privada | Sí | RPC del trabajador y Storage funcionan; nunca se muestra en el navegador |
| `META_APP_SECRET` | Meta Developers → Aplicación → Configuración → Básica → Secreto | Sí para webhook | Las notificaciones auténticas pasan firma; una firma falsa devuelve 401 |
| `META_VERIFY_TOKEN` | Secreto aleatorio creado por el propietario; igual en Meta y Netlify | Sí | Meta acepta Verificar y guardar |
| `META_ACCESS_TOKEN` | Token de sistema con activo y permiso de mensajería; temporal solo en pruebas | Sí para enviar/recibir media | Mensaje y descarga de pruebas aceptados por Meta |
| `META_PHONE_NUMBER_ID` | WhatsApp → API Setup → Phone number ID | Sí | Coincide con `metadata.phone_number_id` y con el canal de la empresa |
| `META_GRAPH_VERSION` | Versión de Graph habilitada y vigente para tu aplicación; formato `vN.N` | Sí | Meta acepta la URL versionada; no inventar versión |
| `OPENAI_API_KEY` | OpenAI Platform → API keys del proyecto del bot; privada | Solo si se activa IA | Pregunta natural selecciona una herramienta autorizada |
| `OPENAI_MODEL` | Modelo con Responses/function calling disponible en tu proyecto | Con IA | Valor inicial `gpt-5-mini`; verifica disponibilidad real antes de activar |
| `OPENAI_MAX_OUTPUT_TOKENS` | Máximo de salida por interpretación; inicial `1500` | No, tiene valor inicial | Las peticiones incluyen ese máximo |
| `OPENAI_DAILY_CALL_LIMIT` | Cuota por empresa/día; inicial `200` | No | `wa_usage.calls` aumenta; el exceso no llama al proveedor |
| `OPENAI_DAILY_TOKEN_BUDGET` | Reserva conservadora de tokens por empresa/día; inicial `300000` | No | La siguiente reserva que supera el presupuesto se rechaza |
| `BOT_ADMIN_ORIGIN` | Origen exacto del portal; local `http://localhost:8090`, producción URL HTTPS real del sitio | Sí para portal en navegador | Peticiones del propio portal permitidas; origen ajeno devuelve 403 |
| `APP_URL` | URL real de la app web, para referencia del despliegue | Recomendada | No se inventa una URL pública; no autoriza acceso por sí misma |
| `PORT` | Puerto del servidor local; inicial `8090` | Solo local | `npm start` sirve el portal en localhost |
| `BOT_WORKER_SECRET` | Secreto aleatorio diferente de los de Meta | Sí en Netlify | `tick` dispara `process`; llamada sin secreto no procesa trabajos |
| `BOT_ENABLED` | Interruptor global, `true` o `false`; inicial `false` | Sí para activar | `/api/health` informa estado; con false no se envía ni procesa |
| `AI_ENABLED` | Interruptor global de interpretación, inicial `false` | Solo para IA | Con false se usan comandos deterministas |
| `URL` | Variable automática de Netlify con el propio sitio | Automática en Netlify | `tick` la utiliza para invocar `process`; no configurarla con un origen ajeno |

Además hay ajustes por empresa en `wa_config`: habilitación, canal, zona, jornada, días, seguimiento, anticipación de vencimientos, frecuencia, plantilla, idioma y resumen de líderes. Las preferencias del integrante son diferentes de las variables del servidor.

Genera secretos con `node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"` en una terminal privada. Usa un valor diferente para verificación y trabajador. Nunca incluyas el resultado en una incidencia, captura, commit o mensaje público. Si se filtra una clave, revócala en el proveedor; editar un archivo local no la revoca.
