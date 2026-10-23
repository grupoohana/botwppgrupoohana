import { readFileSync, writeFileSync } from 'node:fs';
import { parseEnv } from 'node:util';
const envPath=new URL('../.env',import.meta.url);
let raw;try{raw=readFileSync(envPath,'utf8');}catch{console.log(JSON.stringify({error:'No existe whatsapp-bot/.env'}));process.exit(1);}
let env=parseEnv(raw);
let app={};try{app=parseEnv(readFileSync(new URL('../../.env',import.meta.url),'utf8'));}catch{}
if(!env.SUPABASE_URL&&app.EXPO_PUBLIC_SUPABASE_URL){
 const url=app.EXPO_PUBLIC_SUPABASE_URL;
 if(/^https:\/\/[a-z0-9]+\.supabase\.co\/?$/.test(url)){
  raw=/^SUPABASE_URL\s*=/m.test(raw)?raw.replace(/^SUPABASE_URL\s*=.*$/m,`SUPABASE_URL=${url}`):`SUPABASE_URL=${url}\n${raw}`;
  writeFileSync(envPath,raw);env=parseEnv(raw);console.log(JSON.stringify({url_reutilizada_desde_app:true}));
 }
}
const url=env.SUPABASE_URL?.replace(/\/$/,'');const key=env.SUPABASE_SERVICE_ROLE_KEY;
const local={url_configurada:!!url,clave_servidor_configurada:!!key,mismo_proyecto_app:app.EXPO_PUBLIC_SUPABASE_URL?!!url&&url===app.EXPO_PUBLIC_SUPABASE_URL.replace(/\/$/,''):null,bot_habilitado:env.BOT_ENABLED==='true'};
if(key?.split('.').length===3){try{const claims=JSON.parse(Buffer.from(key.split('.')[1],'base64url'));local.tipo_clave=claims.role==='service_role'?'service_role': 'rol_incorrecto';local.proyecto_clave_coincide=!claims.ref||claims.ref===new URL(url).hostname.split('.')[0];}catch{local.tipo_clave='formato_invalido';}}
else if(key)local.tipo_clave=key.startsWith('sb_secret_')?'secret_key_nueva':'formato_no_reconocido';
console.log(JSON.stringify({configuracion:local}));
if(!url||!key||local.mismo_proyecto_app===false||local.tipo_clave==='rol_incorrecto'||local.proyecto_clave_coincide===false){process.exitCode=1;process.exit();}
if(!/^https:\/\/[a-z0-9]+\.supabase\.co$/.test(url)){console.log(JSON.stringify({error:'URL fuera del proyecto esperado'}));process.exit(1);}
const headers={apikey:key,authorization:`Bearer ${key}`};
async function get(path,accept){try{const r=await fetch(url+path,{headers:{...headers,...(accept?{accept}:{})},signal:AbortSignal.timeout(15000),redirect:'error'});let data;try{data=await r.json();}catch{}return {status:r.status,data};}catch{return {status:'conexion_no_disponible'};}}
const [core,schema,bucket,...tables]=await Promise.all([
 get('/rest/v1/tareas?select=id&limit=0'),get('/rest/v1/','application/openapi+json'),get('/storage/v1/bucket/evidencias-tareas'),
 ...['wa_config','wa_links','wa_jobs','wa_template_slots'].map(t=>get(`/rest/v1/${t}?select=*&limit=0`))
]);
const names=['wa_config','wa_links','wa_jobs','wa_template_slots'];
const functions=['wa_actor_action','wa_link_start','wa_login_gate','wa_companies','wa_schedule','wa_template_gate','wa_retry'];
console.log(JSON.stringify({conexion:{tareas_http:core.status,catalogo_http:schema.status},tablas:Object.fromEntries(names.map((n,i)=>[n,tables[i].status])),funciones:Object.fromEntries(functions.map(n=>[n,!!schema.data?.paths?.['/rpc/'+n]])),storage:{http:bucket.status,privado:bucket.status===200?bucket.data?.public===false:null}}));
if(core.status!==200)process.exitCode=1;
