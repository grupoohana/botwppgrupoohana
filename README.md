# Alba Flow · Bot de WhatsApp

Módulo independiente sobre la base Supabase existente de Team's Ohana (nombre real del repositorio). No crea una segunda tabla de tareas. **Código preparado y probado localmente. Las credenciales externas se validan por separado; el despliegue público aún debe realizarse.**

## Incluye

- Cloud API oficial, webhook firmado, verificación, cola persistente y estados de entrega.
- Vinculación desde una cuenta Auth + consentimiento + código enviado desde el número autorizado. Desvinculación y comando BAJA.
- Consultas de tareas, interpretación con herramientas controladas, inicio sin foto o con foto opcional, comentarios, impedimentos y avances fotográficos.
- Finalización con nueva imagen. Migración con validación diferida en PostgreSQL, también para web/API; no requiere aprobación adicional del líder.
- Notificación de asignación/reasignación, imágenes privadas, seguimiento diario, vencimientos y resumen de equipos para líderes.
- Portal de vinculación/configuración, horarios, preferencias, cuotas de IA, deduplicación, bloqueo de conversaciones y control de reintentos.
- Vercel Functions compatible con Hobby; procesamiento por minuto mediante programador externo autenticado. El cron nativo por minuto es opcional en Pro. Desarrollo local con Node 22 o superior. Adaptadores Netlify conservados como compatibilidad.

## Ejecutar localmente

```powershell
# Desde la raíz del repositorio del bot (carpeta whatsapp-bot en el proyecto completo)
npm ci
# Solo si aún no existe .env: copiar .env.example y completar credenciales
npm run check
npm test
npm start
```

El portal abre en http://localhost:8090. `.env.example` deja el envío y la IA deshabilitados. No copies la clave de servidor a React, al navegador ni a un mensaje de WhatsApp.

Las migraciones están en `migrations/`: aplicar las cuatro, en orden, **solo después de probar en un proyecto de ensayo que tenga el esquema actual**. No ejecutar nuevamente las migraciones iniciales del proyecto en producción.

## Manuales

1. [Arquitectura y auditoría](docs/01_ARQUITECTURA.md)
2. [Meta y WhatsApp](docs/02_CONFIGURACION_META.md)
3. [Supabase](docs/03_CONFIGURACION_SUPABASE.md)
4. [Publicar web y bot en Vercel](docs/04_CONFIGURACION_VERCEL.md)
5. [OpenAI](docs/05_CONFIGURACION_OPENAI.md)
6. [Pruebas paso a paso](docs/06_PRUEBAS_PASO_A_PASO.md)
7. [Puesta en producción](docs/07_PUESTA_EN_PRODUCCION.md)
8. [Variables de entorno](docs/08_VARIABLES_ENTORNO.md)
9. [Informe de entrega y cambios](docs/09_ENTREGA.md)

## Límites operativos

El webhook responde después de persistir, y el programador despierta al trabajador cada minuto: no promete respuesta instantánea. El envío externo de WhatsApp no proporciona una transacción distribuida con PostgreSQL: si se pierde la respuesta después de enviar, se marca `uncertain` y se espera el webhook de entrega o revisión manual para evitar duplicados. La IA interpreta una acción; el texto de éxito se genera solo tras una respuesta exitosa del servicio.

El primer despliegue usa un número compartido. Los datos incluyen `phone_id` para aislamiento de canales; para varios números con tokens diferentes se necesitan despliegues/credenciales separados o ampliar el resolvedor de canales. No se almacenan tokens de Meta por empresa en tablas públicas.

Los archivos deben cumplir los límites de Meta: este canal acepta JPEG/PNG de hasta 5 MB. Ese límite no se aplica a las fotografías de la app. No se añadió un estado "bloqueado" ni un porcentaje inexistente: los impedimentos se registran como comentarios/eventos y se muestran como reportes.
