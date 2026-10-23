> Actualización de despliegue: usar [la guía de Vercel](04_CONFIGURACION_VERCEL.md). Las referencias a Netlify de este documento corresponden al adaptador anterior. En Vercel se añade `CRON_SECRET`, no se necesita `URL` y el cron nativo por minuto requiere Pro; Hobby necesita un programador externo.

# 06 · Pruebas paso a paso

## Prueba local sin cuentas externas

En una terminal dentro de `whatsapp-bot`:

```powershell
npm ci
npm run check
npm test
```

Las pruebas de base de datos usan PostgreSQL embebido en memoria, ejecutan migraciones reales del aplicativo y las del bot, y comprueban permisos/RPC/Storage simulado en tablas de ensayo. No se conectan al Supabase real. Las peticiones Meta/OpenAI/Storage de las pruebas de servicio se simulan: no afirman entrega en un celular ni facturación real.

Desde la raíz, `npm test` ejecuta la regresión existente; `npm run typecheck` y el mismo comando dentro de `web` verifican tipos. En `web`, `npm run build` prepara la nueva interfaz. No basta compilar para afirmar un despliegue.

## Prueba con un celular autorizado de Meta

1. Usa un proyecto Supabase de ensayo con el esquema del aplicativo y aplica las cuatro migraciones del bot. En Netlify despliega el bot con los secretos de prueba. Comprueba `api/health` y el GET de verificación en Meta.
2. Inicia sesión en el portal con un administrador, elige la empresa y abre **Administración de la integración**. Configura el Phone number ID de pruebas, una zona real, horario que incluya la hora actual y días laborales. Habilita WhatsApp. No habilites aún la IA.
3. Inicia sesión con la cuenta del integrante, selecciona su empresa e introduce su celular en formato internacional. Acepta el consentimiento y genera el código. Desde ese mismo celular envía el mensaje `VINCULAR ...` al número corporativo de pruebas. Verifica confirmación y fila en `wa_links`. Un número distinto o código reutilizado debe fallar.
4. Crea una tarea en la app asignada al integrante. No hace falta imagen para crearla. Espera el procesamiento programado y comprueba tarea, responsable, prioridad y vencimiento. Para comprobar adjuntos, usa una tarea que tenga imágenes confirmadas en el almacenamiento existente: deben llegar por el canal privado cuando la ventana lo permita. El esquema actual no ofrece una entidad separada de adjuntos de creación ni de proyectos.
5. Reasigna la tarea a otro integrante vinculado. Debe recibirla el responsable actual; una notificación antigua pendiente para el responsable anterior debe descartarse.
6. Escribe `INICIAR nombre exacto`. Responde `SIN FOTO`: el estado debe ser `en_curso`. Repite con otra tarea y envía una imagen en lugar de `SIN FOTO` para verificar el inicio opcional con evidencia.
7. Escribe `AVANCE nombre: comentario de prueba`. Comprueba comentario y autor en la app. Escribe `FOTO nombre` y envía una imagen para un avance sin cambiar de estado. Escribe `IMPEDIMENTO nombre: falta de acceso` y comprueba el historial; no debe aparecer un estado inventado.
8. Escribe `FINALIZAR nombre`. Envía solo texto o `SIN FOTO`: no debe finalizar. Envía una foto nueva y comprueba `finalizado`, la evidencia confirmada y el usuario que realizó el cambio. Las imágenes anteriores no deben aceptarse como sustituto.
9. En la web, intenta finalizar sin imagen y con PDF: debe impedirlo. Arrastrar a Finalizado debe abrir el detalle para adjuntar evidencia. Finalizar con nueva imagen debe funcionar sin aprobación adicional del líder.
10. Interrumpe una carga en ensayo o simula Storage no disponible en una prueba automatizada. La tarea debe conservar el estado y una reserva pendiente recuperable; no debe confirmarse por haber reservado solamente un registro.
11. Activa la IA en Netlify y en la empresa. Pregunta por pendientes, hoy, semana, urgencia y vencidas. Si hay varias tareas posibles, debe preguntar a cuál te refieres. Selecciona la lista y comprueba el resultado real.
12. Intenta consultar una tarea de otra empresa con su UUID desde una cuenta sin membresía: debe rechazarse sin revelar información. Desactiva al integrante y comprueba que pierde acceso aunque conserve un vínculo antiguo.
13. Reenvía una misma notificación de webhook en ensayo conservando su `message.id`: una sola clave de trabajo. Reenvía la misma operación SQL: mismo resultado, sin duplicar evidencias/comentarios. No falsifiques firmas contra producción.
14. Configura seguimiento unos minutos después de la hora local actual. Comprueba un único resumen diario por integrante y que se respeten días, jornada y preferencias. Activa `leader_digest` desde la configuración administrativa para probar resumen de los equipos liderados.
15. Fuera de 24 horas, comprueba uso de la plantilla aprobada y ausencia de mensajes libres. Responde desde el celular para abrir ventana y prueba la imagen pendiente. No alteres timestamps de producción para simular la política; usa una cuenta de ensayo y pruebas locales.
16. Desvincula desde el portal o escribe `BAJA`. Deben detenerse los avisos y las acciones. Solo un nuevo proceso de vinculación debe reactivar la identidad.

## Resultados y criterios

Consulta `09_ENTREGA.md` para los resultados ejecutados. La cobertura de servicios incluye creación/asignación con y sin imagen, reasignación, inicio opcional, avance fotográfico, finalización sin/con foto, fallo de carga, IA, ambigüedad, número ajeno, permisos, otra empresa, duplicados, recordatorios, reintentos, ventana y fallos externos. La prueba SQL ejercita las reglas reales y el rollback de una finalización inválida.

La prueba real Meta/Supabase/OpenAI queda pendiente de las credenciales, registro de número y aprobación de plantillas del propietario. Antes de abrir a todos, completa esta guía con dos integrantes y un líder de prueba.
