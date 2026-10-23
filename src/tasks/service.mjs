import { operationId, uuid } from '../security/crypto.mjs';
export const stateNames = {por_hacer:'Por hacer',en_curso:'En curso',en_revision:'En revisión',finalizado:'Finalizada'};
export class Tasks {
  constructor(db, meta) { this.db=db; this.meta=meta; }
  action(ctx, action, args={}) { return this.db.rpc('wa_actor_action',{p_link:ctx.link.id,p_action:action,p_args:args}); }
  list(ctx, filter='pendientes', offset=0, now=new Date()) {
    const args={offset,pending_only:filter!=='todas',urgent:filter==='urgente'};
    if (filter==='vencidas') args.overdue=true;
    if (filter==='hoy'||filter==='semana') {
      // Convert local midnight through Intl rather than assuming UTC or fixed DST offset.
      const zone=ctx.link.timezone||ctx.config.timezone;
      const parts=new Intl.DateTimeFormat('en-CA',{timeZone:zone,year:'numeric',month:'2-digit',day:'2-digit'}).formatToParts(now);
      const get=t=>parts.find(p=>p.type===t).value;
      const day=`${get('year')}-${get('month')}-${get('day')}`;
      const endDay=new Date(day+'T00:00:00Z');const weekDay=(endDay.getUTCDay()+6)%7;
      endDay.setUTCDate(endDay.getUTCDate()+(filter==='hoy'?1:7-weekDay));
      args.after=localMidnight(day,zone).toISOString();args.before=new Date(localMidnight(endDay.toISOString().slice(0,10),zone).getTime()-1).toISOString();
    }
    return this.action(ctx,'list',args).then(rows => rows.filter(t=>filter==='todas'||t.estado!=='finalizado').sort((a,b)=>filter==='urgente'?({alta:0,media:1,baja:2}[a.criticidad]-{alta:0,media:1,baja:2}[b.criticidad])||a.fecha_fin.localeCompare(b.fecha_fin):a.fecha_fin.localeCompare(b.fecha_fin)));
  }
  async resolve(ctx, ref, candidates) {
    if (uuid(ref)) return this.action(ctx,'detail',{task_id:ref});
    const norm=s=>s.normalize('NFD').replace(/[\u0300-\u036f]/g,'').trim().toLocaleLowerCase('es');
    const found=ref?candidates.filter(t=>norm(t.titulo)===norm(ref)||t.id.startsWith(ref)):candidates;
    if (found.length===1) return this.action(ctx,'detail',{task_id:found[0].id});
    return {ambiguous:true,candidates:found.length?found:candidates};
  }
  async pending(ctx, value) { await this.db.rpc('wa_pending',{p_link:ctx.link.id,p_pending:{...value,expires_at:new Date(Date.now()+15*60000).toISOString()}}); }
  async transition(ctx, task, state, messageId) {
    if (task.estado===state) return 'La tarea ya está en ese estado.';
    await this.action(ctx,'validate',{task_id:task.id});
    const operation_id=operationId(`transition:${ctx.link.id}:${messageId}:${task.id}:${state}`);
    await this.pending(ctx,{kind:'transition',task_id:task.id,version:task.version,from:task.estado,state,operation_id});
    return state==='finalizado'?'Para finalizar, envía ahora una nueva fotografía JPEG o PNG (máximo 5 MB en WhatsApp). No se usarán imágenes anteriores.':'¿Deseas adjuntar una fotografía de inicio? Envíala ahora o responde SIN FOTO para iniciar sin imagen.';
  }
  async commit(ctx, pending, image) {
    if (pending.state==='finalizado'&&!image) throw new Error('Necesitas una nueva fotografía para finalizar.');
    let evidenceId=null;
    if (image) {
      const reservation=await this.action(ctx,'prepare',{task_id:pending.task_id,version:pending.version,state:pending.state,operation_id:pending.operation_id,name:`evidencia.${image.extension}`,extension:image.extension});
      if(reservation.transicion.estado==='confirmada') return reservation.transicion.resultado;
      if(!reservation.archivo_cargado) await this.db.upload(reservation.evidencia.ruta_archivo,image.bytes,image.mime);
      evidenceId=reservation.evidencia.id;
    }
    const result=await this.action(ctx,'commit',{task_id:pending.task_id,version:pending.version,state:pending.state,operation_id:pending.operation_id,evidence_id:evidenceId});
    return result;
  }
  async progressImage(ctx, pending, image, messageId) {
    const id=operationId(`progress:${ctx.link.id}:${messageId}`);
    const e=await this.action(ctx,'progress_prepare',{task_id:pending.task_id,operation_id:id,extension:image.extension});
    if(e.ok) return e;
    await this.db.upload(e.ruta_archivo,image.bytes,image.mime);
    return this.action(ctx,'progress_commit',{task_id:pending.task_id,operation_id:id});
  }
}
export function localMidnight(day,zone) {
  let d=new Date(day+'T00:00:00Z');
  for(let i=0;i<3;i++){const p=new Intl.DateTimeFormat('en-CA',{timeZone:zone,year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',second:'2-digit',hourCycle:'h23'}).formatToParts(d);const g=t=>p.find(x=>x.type===t).value;const wall=Date.parse(`${g('year')}-${g('month')}-${g('day')}T${g('hour')}:${g('minute')}:${g('second')}Z`);d=new Date(d.getTime()+Date.parse(day+'T00:00:00Z')-wall);}
  return d;
}
