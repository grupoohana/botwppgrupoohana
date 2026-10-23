import { config } from '../config/env.mjs';
import { Database } from '../database/supabase.mjs';
import { Meta } from '../services/meta.mjs';
import { OpenAIInterpreter } from '../ai/openai.mjs';
import { Tasks } from '../tasks/service.mjs';
import { Conversation } from '../services/conversation.mjs';
import { Messaging } from '../services/messaging.mjs';
import { Worker } from '../automations/worker.mjs';
import { webhook } from '../webhooks/meta.mjs';
import { token,hash,phone,uuid,equal } from '../security/crypto.mjs';
import { jsonBody } from '../security/body.mjs';
export function createApp(overrides={}) {
  const c=overrides.c||config(); const db=overrides.db||new Database(c);const meta=overrides.meta||new Meta(c);const tasks=overrides.tasks||new Tasks(db,meta);const ai=overrides.ai||new OpenAIInterpreter(c,db);
  const conversation=new Conversation({db,meta,tasks,ai});const messaging=new Messaging(db,meta,c);const worker=new Worker({db,conversation,messaging,c,tasks});
  async function handler(req) {
    const path=new URL(req.url).pathname.replace(/^\/\.netlify\/functions\/api/,'/api');
    if(path==='/api/webhook')return webhook(req,{c,db});
    const headers={'content-type':'application/json','cache-control':'no-store','x-content-type-options':'nosniff'};
    let appOrigin='';try{const url=new URL(c.appUrl);if(['https:','http:'].includes(url.protocol))appOrigin=url.origin;}catch{}
    const origin=req.headers.get('origin');if(origin&&origin!==c.adminOrigin&&origin!==appOrigin)return Response.json({error:'Origen no autorizado'},{status:403,headers});
    if(origin){headers['access-control-allow-origin']=origin;headers.vary='Origin';}
    if(req.method==='OPTIONS')return new Response(null,{status:204,headers:{...headers,'access-control-allow-methods':'GET,POST,OPTIONS','access-control-allow-headers':'authorization,content-type'}});
    if(path==='/api/health')return Response.json({service:'alba-flow-whatsapp',enabled:c.enabled,configured:!!(c.supabaseUrl&&c.serviceKey&&c.phoneId&&c.metaToken&&c.appSecret&&c.verifyToken&&c.graphVersion),aiConfigured:!!c.openaiKey},{headers});
    if(path==='/api/session') {
      if(req.method!=='POST')return Response.json({error:'Método no permitido'},{status:405,headers});
      try {
        const b=await jsonBody(req,4000);
        if(typeof b.email!=='string'||b.email.length>254||typeof b.password!=='string'||b.password.length>512)throw Error('Credentials');
        await db.rpc('wa_login_gate',{p_key:hash(b.email.trim().toLowerCase())});const session=await db.login(b.email.trim(),b.password);
        const companies=await db.rpc('wa_companies',{},session.access_token);
        return Response.json({access_token:session.access_token,expires_in:session.expires_in,companies},{headers});
      }catch{return Response.json({error:'No se pudo iniciar sesión. Revisa tus credenciales o espera antes de reintentar.'},{status:401,headers});}
    }
    if(path==='/api/worker') {
      if(req.method!=='POST'||!equal(req.headers.get('authorization'),`Bearer ${c.workerSecret}`)||!c.workerSecret)return Response.json({error:'No autorizado'},{status:401,headers});
      try{return Response.json(await worker.tick({schedule:true}),{headers});}catch{return Response.json({error:'Worker unavailable'},{status:503,headers});}
    }
    if(!['/api/link','/api/account','/api/admin'].includes(path))return Response.json({error:'No encontrado'},{status:404,headers});
    if(req.method!=='POST')return Response.json({error:'Método no permitido'},{status:405,headers});
    const jwt=req.headers.get('authorization')?.match(/^Bearer (.+)$/)?.[1];if(!jwt)return Response.json({error:'Inicia sesión con Supabase'},{status:401,headers});
    try {
      if(Number(req.headers.get('content-length'))>16000)return Response.json({error:'Solicitud demasiado grande'},{status:413,headers});
      const body=await jsonBody(req);if(!uuid(body.company_id))return Response.json({error:'Empresa inválida'},{status:400,headers});
      await db.user(jwt);
      if(path==='/api/link') {
        const code=token();const result=await db.rpc('wa_link_start',{p_empresa:body.company_id,p_phone:phone(body.phone),p_hash:hash(code),p_consent:body.consent===true},jwt);
        const message=`VINCULAR ${code}`;let whatsapp_url=null;
        try{whatsapp_url=`https://wa.me/${await meta.phoneNumber()}?text=${encodeURIComponent(message)}`;}catch{}
        return Response.json({...result,message,whatsapp_url},{headers});
      }
      const name=path==='/api/admin'?'wa_admin':'wa_account';
      if(path==='/api/admin'&&body.action==='retry') {if(!uuid(body.options?.job_id))throw Error('Job inválido');await db.rpc('wa_retry',{p_empresa:body.company_id,p_job:body.options.job_id,p_accept_duplicate_risk:body.options.accept_duplicate_risk===true},jwt);return Response.json({ok:true},{headers});}
      return Response.json(await db.rpc(name,{p_empresa:body.company_id,p_action:body.action||'status',p_options:body.options||{}},jwt),{headers});
    }catch{return Response.json({error:'Operación rechazada. Revisa tu sesión, permisos, empresa y configuración.'},{status:400,headers});}
  }
  return {handler,worker,c,db};
}
