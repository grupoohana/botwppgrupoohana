> Actualización de despliegue: usar [la guía de Vercel](04_CONFIGURACION_VERCEL.md). Las referencias a Netlify de este documento corresponden al adaptador anterior. En Vercel se añade `CRON_SECRET`, no se necesita `URL` y el cron nativo por minuto requiere Pro; Hobby necesita un programador externo.

# 09 · Informe de entrega · 21 de octubre de 2026

## Estado

Implementación local preparada. **No se aplicaron migraciones al Supabase real, no se desplegó un sitio en Netlify, no se registró un número ni se enviaron mensajes de pago.** Las credenciales de Meta/OpenAI no se han inventado ni incorporado. El servidor de revisión está en `http://localhost:8090`, con el bot y la IA deshabilitados y sin configuración privada. El frontend web se compiló localmente; no se generó APK.

## Funciones implementadas

Webhook GET/POST, firma HMAC, verificación de canal, persistencia previa al ACK, entradas duplicadas, cola con lease/orden por conversación, salidas, estados de entrega monotónicos, reintentos y revisión de entregas inciertas. Vinculación Auth más código de WhatsApp, consentimiento, preferencias, empresa activa y BAJA. Comandos, intérprete de IA desacoplado y herramientas permitidas. Consultas, inicio, comentario, impedimento, avance fotográfico y finalización con evidencia nueva. Notificaciones de asignación/reasignación, imágenes privadas, seguimiento, vencimientos y resúmenes de líderes. Portal independiente de configuración, límites de IA y protección de credenciales.

## Archivos nuevos

Todos bajo `whatsapp-bot/`, salvo los artefactos locales de comprobación:

- Raíz: `package.json`, `package-lock.json`, `.gitignore`, `.env.example`, `netlify.toml`, `README.md`.
- `src/api/`: `app.mjs`, `server.mjs`.
- `src/config/env.mjs` y `src/database/supabase.mjs`.
- `src/webhooks/meta.mjs`, `src/automations/worker.mjs`, `src/ai/openai.mjs`, `src/tasks/service.mjs`.
- `src/evidence/images.mjs`, `src/security/crypto.mjs`, `src/security/body.mjs`.
- `src/services/`: `http.mjs`, `meta.mjs`, `conversation.mjs`, `messaging.mjs`.
- `netlify/functions/`: `api.mjs`, `tick.mjs`, `process.mjs`.
- `public/`: `index.html`, `admin.mjs`, `style.css`.
- `scripts/check.mjs`.
- `tests/`: `bot.test.mjs`, `database.test.mjs`.
- `migrations/`: `202610210101_whatsapp.sql`, `202610210102_automation.sql`, `202610210103_portal.sql`, `202610210104_delivery_controls.sql`.
- `docs/`: los ocho manuales solicitados (`01` a `08`) y este informe `09`.

`artifacts/whatsapp-bot-functions/` contiene bundles generados de las tres funciones para comprobar que se empaquetan con Node 22. No sustituye un despliegue de Netlify ni contiene credenciales.

## Archivos existentes modificados y motivo

| Archivo | Cambio justificado |
|---|---|
| `.easignore` | Excluye el bot de las compilaciones móviles |
| `src/services/state-evidence.ts` | Exige fotografía nueva al finalizar; conserva inicio opcional |
| `web/src/services/state-evidence.ts` | Misma regla en el cliente web |
| `src/screens/TaskDetailScreen.tsx` | Mensaje claro y rechazo previo si falta fotografía al finalizar |
| `web/src/screens/TaskDetailScreen.tsx` | Mismo flujo de evidencia en web |
| `web/src/components/desktop/KanbanBoard.tsx` | Arrastrar a Finalizado abre el detalle en lugar de guardar sin evidencia |
| `tests/state-evidence.test.ts` | Regresión de finalización sin foto/con documento inválido |
| `web/tests/desktop-browser.cjs` | Ajusta la regresión de arrastre a la nueva regla de fotografía |

No se reemplazaron roles, estados, tareas, Auth ni las Edge Functions existentes. La regla global se incorpora con una migración independiente; las RPC originales siguen ejecutando las transiciones y su control de versión.

## Tablas nuevas y cambios de base de datos

Se añaden `wa_config`, `wa_link_codes`, `wa_links`, `wa_conversations`, `wa_jobs`, `wa_delivery`, `wa_operations`, `wa_audit`, `wa_usage`, `wa_rate_limits`, `wa_template_slots`. Tienen RLS y permisos restringidos. Las relaciones nuevas se eliminan o desvinculan con sus entidades padre para no impedir la administración existente.

Se agregan triggers de asignación, imagen confirmada y comprobación diferida de evidencia al finalizar. Se añaden RPC de cuenta, administración, identidad verificada, cola, cuotas, programación y reintento. No se crean tablas alternativas de tareas, usuarios, equipos ni empresas, ni se cambia el bucket privado a público.

## Validación ejecutada

| Comprobación | Resultado |
|---|---|
| `whatsapp-bot: npm run check` | Sintaxis de servicios, portal y funciones correcta |
| `whatsapp-bot: npm test` | 25 pruebas; incluye PostgreSQL embebido con migraciones reales, permisos, finalización atómica y aislamiento |
| Raíz: `npm test` | 84 pruebas existentes y nuevas de regresión aprobadas |
| Raíz y web: `npm run typecheck` | Ambas verificaciones aprobadas |
| Web: `npm run build` | Exportación completada, 26 rutas |
| Web: `npm run test:ui` | Chrome con Supabase/Google simulados: navegación, roles, fotos, transiciones, arrastre, requisito de fotografía, paginación y cierre de sesión aprobados |
| Bundles de Functions con esbuild/Node 22 | `api`, `tick`, `process` empaquetados |
| HTTP local del bot | `/` devuelve 200; `/api/health` confirma integración deshabilitada y sin credenciales |

Las 20 situaciones del documento están cubiertas por pruebas de servicios y/o base de datos: tareas y asignación con/sin imagen, reasignación, inicio sin/con imagen, avance fotográfico, finalizar sin/con foto, fallo Storage, IA, ambigüedad, teléfono desconocido, falta de permisos, empresa ajena, duplicados, recordatorios, reintentos, ventana de atención y fallos externos. Se comprueban además fechas con horario de verano, no reutilizar fotos antiguas, recuperación idempotente, permiso de borrado de evidencias y un webhook atrasado que no reabra artificialmente la ventana.

**No equivalen a una prueba real de conectividad de los proveedores.** La firma y los endpoints están implementados, pero entregar a un teléfono, usar una plantilla aprobada, confirmar permisos de Meta y generar una interpretación con un modelo real requieren las credenciales del propietario.

## Pendientes de activación y límites

Aplicar primero las cuatro migraciones en ensayo y coordinar clientes antes de la regla global. Obtener credenciales reales, registrar/verificar el número, aprobar la plantilla, desplegar Netlify, configurar webhook y realizar el piloto descrito en los manuales. Revisar facturación y consentimiento antes de usuarios reales.

Una entrega externa incierta requiere revisión, no un reenvío automático. Los trabajos fuera de horario/ventana esperan sin consumir el límite normal de reintentos; las plantillas se consolidan por vínculo. El primer canal utiliza un solo número corporativo; números con credenciales diferentes requieren separación de despliegues o ampliar el resolvedor. No se implementan estados/proyectos que el esquema no tiene. La validación de imágenes no sustituye antivirus ni políticas internas de datos.
