import { validSignature, equal, phone, uuid } from '../security/crypto.mjs';
export async function webhook(request, {c,db}) {
  const url=new URL(request.url);
  if(request.method==='GET') {
    if(url.searchParams.get('hub.mode')!=='subscribe'||!equal(url.searchParams.get('hub.verify_token'),c.verifyToken))return new Response('Forbidden',{status:403});
    return new Response(url.searchParams.get('hub.challenge')||'',{headers:{'content-type':'text/plain'}});
  }
  if(request.method!=='POST')return new Response('Method not allowed',{status:405});
  if(!c.enabled)return new Response('Integration disabled',{status:503});
  if(Number(request.headers.get('content-length'))>1024*1024)return new Response('Payload too large',{status:413});
  const chunks=[];let bytes=0;
  if(request.body)for await(const chunk of request.body){bytes+=chunk.length;if(bytes>1024*1024)return new Response('Payload too large',{status:413});chunks.push(Buffer.from(chunk));}
  const raw=Buffer.concat(chunks);
  if(!validSignature(raw,request.headers.get('x-hub-signature-256'),c.appSecret))return new Response('Invalid signature',{status:401});
  let data;try{data=JSON.parse(raw);}catch{return new Response('Invalid JSON',{status:400});}
  if(data.object!=='whatsapp_business_account')return new Response('Invalid object',{status:400});
  // ACK only after durable insertion. If Supabase fails return 503 so Meta can retry.
  try {
    for(const entry of data.entry||[])for(const change of entry.changes||[]) {
      const v=change.value;if(change.field!=='messages'||v?.metadata?.phone_number_id!==c.phoneId)continue;
      for(const message of v.messages||[]) {
        if(typeof message.id!=='string'||message.id.length>300)continue;
        const at=Number(message.timestamp)*1000;if(!Number.isFinite(at)||at>Date.now()+5*60000||at<Date.now()-7*86400000)continue;
        const sender=phone(message.from);
        const selection=message.interactive?.list_reply?.id||message.interactive?.button_reply?.id;
        const payload={phone:sender,phone_id:c.phoneId,message_id:message.id,timestamp:message.timestamp,text:message.text?.body?.slice(0,4000)||'',selection:typeof selection==='string'?selection.slice(0,200):null,image:message.type==='image'?{id:message.image?.id,sha256:message.image?.sha256}:null};
        await db.rpc('wa_enqueue',{p_kind:'inbound',p_key:`in:${c.phoneId}:${message.id}`,p_payload:payload,p_empresa:null,p_usuario:null});
      }
      for(const s of v.statuses||[])if(uuid(s.biz_opaque_callback_data))await db.rpc('wa_delivery_status',{p_provider:s.id,p_job:s.biz_opaque_callback_data,p_status:s.status,p_at:new Date(Number(s.timestamp)*1000).toISOString(),p_error:s.errors?.[0]?.code?.toString()||null});
    }
    return new Response('EVENT_RECEIVED');
  }catch{return new Response('Persistence unavailable',{status:503});}
}
