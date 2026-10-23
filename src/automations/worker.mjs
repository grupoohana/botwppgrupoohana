import { textPayload } from '../services/conversation.mjs';
import { businessHours } from '../services/messaging.mjs';
export class Worker {
  constructor({db,conversation,messaging,c,tasks}) {Object.assign(this,{db,conversation,messaging,c,tasks});}
  async tick({schedule=false,max=3,budgetMs=20000}={}) {
    if(!this.c.enabled)return {enabled:false,processed:0};
    const started=Date.now();let count=0;
    if(schedule)await this.db.rpc('wa_schedule',{p_limit:100});
    while(count<max&&Date.now()-started<budgetMs) {
      // One claim at a time preserves conversation ordering and bounds scheduled runtime.
      const jobs=await this.db.rpc('wa_claim',{p_limit:1});if(!jobs.length)break;
      const job=jobs[0];let status='done',error=null;
      try {
        if(job.kind==='inbound')await this.conversation.handle(job);
        else if(job.kind==='outbound') {const r=await this.messaging.send(job);if(r.defer){status='pending';error=r.reason;}}
        else await this.notification(job);
      }catch(e){
        error=e.defer?'waiting_hours':e.service?`${e.service}:${e.status}`:'action_failed';
        if(job.kind==='outbound'&&e.uncertain)status='uncertain';
        else if(e.retryable)status='pending';
        else if(job.kind==='inbound') {
          try{await this.conversation.reply(job,null,textPayload(e.service?'No se pudo completar la operación. Verifica tus permisos, conexión y la versión de la tarea. No se confirmó ningún cambio.':e.message),90);}catch{status='pending';}
        }else status='failed';
      }
      await this.db.rpc('wa_finish',{p_id:job.id,p_lease:job.lease_token,p_status:status,p_error:error});count++;
    }
    return {enabled:true,processed:count};
  }
  async notification(job) {
    const ctx=await this.db.rpc('wa_recipient',{p_empresa:job.empresa_id,p_usuario:job.usuario_id,p_task:job.payload.task_id||null});
    if(!ctx)return;
    if(!businessHours(ctx.config)) {throw Object.assign(new Error('Fuera de horario.'),{retryable:true,defer:true});}
    if(job.kind==='followup'&&!ctx.link.followups||job.kind==='reminder'&&!ctx.link.reminders)return;
    const task=ctx.task;
    if(task&&task.responsable_id!==job.usuario_id)return;
    let body;
    if(job.kind==='digest') {
      const summary=await this.tasks.action(ctx,'summary');if(!summary.length)return;
      body='ALBA FLOW — RESUMEN DE EQUIPO\n'+ctx.company+'\n'+summary.map(r=>`${r.nombre_completo}: ${r.estado} ${r.total}, vencidas ${r.vencidas}, impedimentos reportados ${r.impedimentos}`).join('\n');
      await this.db.rpc('wa_enqueue',{p_kind:'outbound',p_key:`notice:${job.id}`,p_payload:{link_id:ctx.link.id,phone:ctx.link.phone,phone_id:ctx.link.phone_id,payload:textPayload(body)},p_empresa:job.empresa_id,p_usuario:job.usuario_id});return;
    }
    if(task)body=`ALBA FLOW — ${job.kind==='assignment'?'TAREA ASIGNADA':'IMAGEN DE TAREA'}\n${ctx.company}\n${task.titulo}\n${task.descripcion}\nPrioridad: ${task.criticidad}\nVencimiento: ${task.fecha_fin}\nID: ${task.id}\nResponde DETALLE, INICIAR o IMPEDIMENTO seguido del ID. Para finalizar, se pedirá una nueva foto.`;
    else {const rows=await this.tasks.list(ctx,'pendientes');if(!rows.length)return;body=`ALBA FLOW — ${job.kind==='followup'?'SEGUIMIENTO DIARIO':'RECORDATORIO'}\n${ctx.company}\nTienes ${rows.length}${rows.length===20?' o más':''} tareas pendientes:\n`+rows.slice(0,10).map(t=>`${t.titulo} · ${t.fecha_fin}`).join('\n')+'\nEscribe TAREAS, AVANCE nombre: comentario, FINALIZAR nombre o IMPEDIMENTO nombre: motivo.';}
    await this.db.rpc('wa_enqueue',{p_kind:'outbound',p_key:`notice:${job.id}`,p_payload:{link_id:ctx.link.id,phone:ctx.link.phone,phone_id:ctx.link.phone_id,task_id:task?.id||null,payload:textPayload(body)},p_empresa:job.empresa_id,p_usuario:job.usuario_id});
    for(const image of task?.imagenes||[]) {
      if(job.kind==='evidence'&&job.payload.evidence_id!==image.id)continue;
      await this.db.rpc('wa_enqueue',{p_kind:'outbound',p_key:`media:${ctx.link.id}:${image.id}`,p_payload:{link_id:ctx.link.id,phone:ctx.link.phone,phone_id:ctx.link.phone_id,task_id:task.id,image_path:image.ruta},p_empresa:job.empresa_id,p_usuario:job.usuario_id});
    }
  }
}
