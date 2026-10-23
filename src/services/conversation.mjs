import { hash, operationId, uuid } from '../security/crypto.mjs';
import { stateNames } from '../tasks/service.mjs';
export const textPayload=text=>({type:'text',text:{body:text.slice(0,4000),preview_url:false}});
export function choices(body, rows) {
  if(!rows.length)return textPayload(body);
  return {type:'interactive',interactive:{type:'list',body:{text:body.slice(0,1024)},action:{button:'Seleccionar tarea',sections:[{title:'Tareas',rows:rows.slice(0,10).map(t=>({id:'task:'+t.id,title:t.titulo.slice(0,24),description:(stateNames[t.estado]||'')+' · '+t.id.slice(0,8)}))}]}}};
}
export class Conversation {
  constructor({db,meta,tasks,ai}) { Object.assign(this,{db,meta,tasks,ai}); }
  async reply(job,ctx,payload,index=0) {
    await this.db.rpc('wa_enqueue',{p_kind:'outbound',p_key:`reply:${job.id}:${index}`,p_payload:{link_id:ctx?.link?.id||null,phone:job.payload.phone,phone_id:job.payload.phone_id,payload,inbound_reply:true},p_empresa:ctx?.link?.empresa_id||null,p_usuario:ctx?.link?.usuario_id||null});
  }
  async handle(job) {
    const m=job.payload;
    let ctx=await this.db.rpc('wa_context',{p_phone:m.phone,p_phone_id:m.phone_id,p_inbound:true,...(m.timestamp?{p_at:new Date(Number(m.timestamp)*1000).toISOString()}:{})});
    const text=(m.text||'').trim();
    if(/^VINCULAR\s+[a-f0-9]{48}$/i.test(text)) {
      try { const link=await this.db.rpc('wa_link_complete',{p_phone:m.phone,p_phone_id:m.phone_id,p_hash:hash(text.split(/\s+/)[1])});ctx.link=link;await this.reply(job,ctx,textPayload('Número verificado y vinculado. Escribe TAREAS para empezar. BAJA desactiva los avisos y la vinculación.')); }
      catch { await this.reply(job,null,textPayload('Código inválido, vencido o número diferente al autorizado. Genera un nuevo código desde tu cuenta de Alba Flow.')); }
      return;
    }
    if(!ctx.link?.id) {
      if(ctx.companies?.length) await this.reply(job,null,textPayload('Selecciona tu empresa escribiendo EMPRESA y su identificador:\n'+ctx.companies.map(c=>`${c.nombre}: ${c.empresa_id}`).join('\n')));
      // Unknown numbers get one rate-limited generic response; no personal/company data.
      else await this.reply(job,null,textPayload('Vincula tu número desde tu cuenta autenticada de Alba Flow. Necesitas un código de verificación.'));
      if(/^EMPRESA\s+/i.test(text)&&uuid(text.split(/\s+/)[1])) { ctx=await this.db.rpc('wa_context',{p_phone:m.phone,p_phone_id:m.phone_id,p_company:text.split(/\s+/)[1]});await this.reply(job,ctx,textPayload('Empresa seleccionada. Escribe TAREAS.'),1); }
      return;
    }
    if(/^EMPRESA\s+/i.test(text)&&uuid(text.split(/\s+/)[1])) { await this.db.rpc('wa_context',{p_phone:m.phone,p_phone_id:m.phone_id,p_company:text.split(/\s+/)[1]});await this.reply(job,ctx,textPayload('Empresa seleccionada. Escribe TAREAS.'));return; }
    if(/^BAJA$/i.test(text)) { await this.db.rpc('wa_unsubscribe',{p_link:ctx.link.id}); await this.reply(job,null,textPayload('Vinculación y avisos desactivados. Puedes volver a vincular desde tu cuenta.'));return; }
    if(/^CANCELAR$/i.test(text)){await this.tasks.pending(ctx,{});await this.reply(job,ctx,textPayload('Solicitud cancelada.'));return;}
    const pending=ctx.conversation?.pending||{};
    const validPending=pending.expires_at&&Date.parse(pending.expires_at)>Date.now();
    if(m.image) {
      if(!validPending||!['transition','progress'].includes(pending.kind)){await this.reply(job,ctx,textPayload('Primero indica la tarea: FINALIZAR nombre, INICIAR nombre o FOTO nombre.'));return;}
      if(pending.image_message_id&&pending.image_message_id!==m.message_id)throw new Error('Esta solicitud ya tiene una fotografía. Consulta la tarea o inicia un nuevo avance con FOTO y su nombre.');
      const image=await this.meta.download(m.image.id,m.image.sha256);
      await this.tasks.pending(ctx,{...pending,image_message_id:m.message_id});
      if(pending.kind==='transition') await this.tasks.commit(ctx,pending,image);
      else await this.tasks.progressImage(ctx,pending,image,m.message_id);
      await this.reply(job,ctx,textPayload(pending.kind==='transition'?`Cambio guardado: ${stateNames[pending.state]}. Fotografía registrada.`:'Fotografía de avance guardada.'));return;
    }
    if(validPending&&pending.kind==='transition'&&/^SIN FOTO$/i.test(text)) { await this.tasks.commit(ctx,pending);await this.reply(job,ctx,textPayload('Tarea iniciada sin fotografía.'));return; }
    const rows=await this.tasks.list(ctx,'pendientes');
    let intent;
    if(m.selection?.startsWith('task:')) {
      const id=m.selection.slice(5);
      if(!validPending||pending.kind!=='choose'||!pending.candidates.includes(id)) throw new Error('La selección venció. Consulta tus tareas nuevamente.');
      intent={name:pending.action,args:{...pending.args,task:id}};
    } else if(/^MAS\s+\d+$/i.test(text)) {const offset=Math.min(Number(text.split(/\s+/)[1]),10000);const more=await this.tasks.list(ctx,'pendientes',offset);await this.showList(job,ctx,more,offset);return;}
    else intent=await this.ai.interpret(text,ctx,rows);
    if(intent.name==='budget'){await this.reply(job,ctx,textPayload('Límite diario de IA alcanzado. Puedes consultar con TAREAS, HOY o VENCIDAS cuando se reactive, o usar la aplicación.'));return;}
    if(intent.name==='help'){await this.reply(job,ctx,textPayload('Puedes escribir: TAREAS, HOY, SEMANA, VENCIDAS, INICIAR nombre, FINALIZAR nombre, AVANCE nombre: comentario, IMPEDIMENTO nombre: motivo, FOTO nombre, RESUMEN EQUIPO, CANCELAR o BAJA.'));return;}
    if(['consultar_mis_tareas','consultar_tareas_vencidas'].includes(intent.name)){const list=await this.tasks.list(ctx,intent.name==='consultar_tareas_vencidas'?'vencidas':intent.args.filter);await this.showList(job,ctx,list);return;}
    if(intent.name==='resumen_equipo'){const data=await this.tasks.action(ctx,'summary');await this.reply(job,ctx,textPayload('Resumen del equipo (hasta 100 grupos):\n'+data.map(r=>`${r.nombre_completo}: ${stateNames[r.estado]} ${r.total}, vencidas ${r.vencidas}, con impedimentos reportados ${r.impedimentos}`).join('\n')));return;}
    const task=await this.tasks.resolve(ctx,intent.args.task,rows);
    if(task.ambiguous){await this.tasks.pending(ctx,{kind:'choose',action:intent.name,args:intent.args,candidates:task.candidates.map(t=>t.id)});await this.reply(job,ctx,choices(task.candidates.length?'¿A qué tarea te refieres? Selecciona una o escribe la acción con su identificador completo.':'No encontré tareas asignadas que coincidan.',task.candidates));return;}
    if(intent.name==='consultar_detalle_tarea') {
      await this.reply(job,ctx,textPayload(`${task.titulo}\n${task.descripcion}\n${stateNames[task.estado]} · ${task.criticidad}\nVence: ${task.fecha_fin}\nID: ${task.id}`));
      for(const [index,image]of(task.imagenes||[]).entries())await this.queueImage(job,ctx,{...image,task_id:task.id},index+1);return;
    }
    if(['iniciar_tarea','solicitar_finalizacion','finalizar_tarea'].includes(intent.name)){const response=await this.tasks.transition(ctx,task,intent.name==='iniciar_tarea'?'en_curso':'finalizado',m.message_id);await this.reply(job,ctx,textPayload(response));return;}
    if(intent.name==='adjuntar_evidencia'){await this.tasks.action(ctx,'validate',{task_id:task.id,kind:'progress'});await this.tasks.pending(ctx,{kind:'progress',task_id:task.id});await this.reply(job,ctx,textPayload('Envía ahora una fotografía JPEG o PNG de avance (máximo 5 MB).'));return;}
    if(['registrar_avance','registrar_impedimento'].includes(intent.name)) {
      if(!intent.args.comment){await this.reply(job,ctx,textPayload(`Escribe ${intent.name==='registrar_impedimento'?'IMPEDIMENTO':'AVANCE'} ${task.id}: y tu comentario. Para una foto usa FOTO ${task.id}.`));return;}
      await this.tasks.action(ctx,intent.name==='registrar_impedimento'?'blocker':'comment',{task_id:task.id,comment:intent.args.comment,operation_id:operationId('comment:'+m.message_id)});await this.reply(job,ctx,textPayload('Registro guardado en el historial de la tarea.'));return;
    }
    throw new Error('Acción no disponible. Escribe AYUDA.');
  }
  async showList(job,ctx,rows,offset=0) {
    const body=rows.length?'Tus tareas:\n'+rows.map(t=>`${t.id.slice(0,8)} · ${t.titulo} · ${stateNames[t.estado]} · ${t.fecha_fin}`).join('\n')+(rows.length===20?`\nPara más resultados: MAS ${offset+20}`:''):'No hay tareas asignadas para esta consulta.';
    await this.tasks.pending(ctx,{kind:'choose',action:'consultar_detalle_tarea',args:{},candidates:rows.map(t=>t.id)});
    if(body.length<=1024)await this.reply(job,ctx,choices(body,rows));else{await this.reply(job,ctx,textPayload(body));await this.reply(job,ctx,choices('Selecciona una tarea (primeras 10) o escribe DETALLE y su identificador.',rows),1);}
  }
  async queueImage(job,ctx,image,index) {await this.db.rpc('wa_enqueue',{p_kind:'outbound',p_key:`media:${ctx.link.id}:${image.id}`,p_payload:{link_id:ctx.link.id,phone:job.payload.phone,phone_id:job.payload.phone_id,image_path:image.ruta,task_id:image.task_id,inbound_reply:true},p_empresa:ctx.link.empresa_id,p_usuario:ctx.link.usuario_id});}
}
