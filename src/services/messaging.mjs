import { textPayload } from './conversation.mjs';
import { boundedBytes, validateImage } from '../evidence/images.mjs';
export function inWindow(last, now=Date.now()) { const at=Date.parse(last||'');return Number.isFinite(at)&&at<=now&&now-at<24*3600000; }
export function businessHours(config, now=new Date()) {
  const p=new Intl.DateTimeFormat('en-US',{timeZone:config.timezone,weekday:'short',hour:'2-digit',minute:'2-digit',hourCycle:'h23'}).formatToParts(now);const g=t=>p.find(x=>x.type===t)?.value;
  const day=['Sun','Mon','Tue','Wed','Thu','Fri','Sat'].indexOf(g('weekday'));const time=g('hour')+':'+g('minute');
  return config.work_days.includes(day)&&time>=config.work_start.slice(0,5)&&time<=config.work_end.slice(0,5);
}
export function policyPayload(payload, ctx, now=Date.now()) {
  if(inWindow(ctx.conversation?.last_inbound,now))return payload;
  if(!ctx.link?.enabled||!ctx.link?.notifications||!ctx.config?.template_name)return null;
  // Fixed, approved utility template. Task/media details are available after the user replies.
  return {type:'template',template:{name:ctx.config.template_name,language:{code:ctx.config.template_language},components:[]}};
}
export class Messaging {
  constructor(db,meta,c) {Object.assign(this,{db,meta,c});}
  async send(job) {
    const p=job.payload;
    if(p.phone_id!==this.c.phoneId)throw new Error('Canal no configurado en este despliegue.');
    let ctx;
    if(job.empresa_id&&job.usuario_id){ctx=await this.db.rpc('wa_recipient',{p_empresa:job.empresa_id,p_usuario:job.usuario_id,p_task:p.task_id||null,p_interactive:p.inbound_reply===true});if(!ctx||ctx.link.id!==p.link_id||ctx.link.phone!==p.phone)return {skipped:true};}
    else {ctx=await this.db.rpc('wa_context',{p_phone:p.phone,p_phone_id:p.phone_id});ctx.link=null;}
    if(!p.inbound_reply&&ctx.task&&ctx.task.responsable_id!==job.usuario_id)return {skipped:true};
    if(!p.inbound_reply&&ctx.config&&!businessHours(ctx.config))return {defer:true,reason:'waiting_hours'};
    if(p.image_path&&!inWindow(ctx.conversation?.last_inbound)) {
      // Keep this media job until the recipient reopens the window. Do not replace an image with a template and mark it sent.
      return {defer:true,reason:'waiting_window'};
    }
    let payload=policyPayload(p.payload||textPayload('Tienes una actualización de Alba Flow.'),ctx);
    if(!payload)return {skipped:true};
    if(payload.type==='template'&&!await this.db.rpc('wa_template_gate',{p_link:ctx.link.id,p_job:job.id}))return {skipped:true};
    if(p.image_path) {
      try {const response=await this.db.image(p.image_path);const image=validateImage(await boundedBytes(response),response.headers.get('content-type'));const id=await this.meta.upload(image);payload={type:'image',image:{id}};}
      catch(error){if(error.retryable)throw error;const url=await this.db.signedImage(p.image_path);payload=textPayload('La imagen no pudo enviarse en el formato de WhatsApp. Enlace privado temporal (5 minutos): '+url);}
    }
    const result=await this.meta.send(p.phone,payload,job.id);
    const id=result.messages?.[0]?.id;
    if(!id)throw Object.assign(new Error('Meta no confirmó un identificador.'),{uncertain:true});
    try{await this.db.rpc('wa_delivery_status',{p_provider:id,p_job:job.id,p_status:'sent',p_at:new Date().toISOString(),p_error:null});}catch(error){error.uncertain=true;throw error;}return {id};
  }
}
