import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createHash,randomUUID} from 'node:crypto';
import {createApp} from '../src/api/app.mjs';
import {Meta} from '../src/services/meta.mjs';
import {Database} from '../src/database/supabase.mjs';

test('configuración ausente devuelve indicación concreta sin filtrar detalles SQL',async()=>{
  const db=new Database({supabaseUrl:'https://database.example',serviceKey:'private-key'},async url=>url.endsWith('/auth/v1/user')?Response.json({id:randomUUID()}):Response.json({code:'P0002',message:'private database detail'},{status:400}));
  const app=createApp({c:{},db,meta:{},tasks:{},ai:{}});
  const response=await app.handler(new Request('https://bot.example/api/link',{method:'POST',headers:{authorization:'Bearer session','content-type':'application/json'},body:JSON.stringify({company_id:randomUUID(),phone:'51999999999',consent:true})}));
  assert.equal(response.status,409);const result=await response.json();assert.match(result.error,/Configurar WhatsApp de la empresa/);assert.equal(result.error.includes('private database detail'),false);
});

test('app vincula con JWT y origen autorizado; entrega código y enlace sin claves',async()=>{
  const company=randomUUID();let savedHash,lookups=0;
  const c={adminOrigin:'https://bot.example',appUrl:'https://app.example',enabled:true};
  const db={async user(jwt){assert.equal(jwt,'user-session');},async rpc(name,args,jwt){assert.equal(name,'wa_link_start');assert.equal(jwt,'user-session');assert.equal(args.p_empresa,company);assert.equal(args.p_consent,true);savedHash=args.p_hash;return {expires_in:600};}};
  const app=createApp({c,db,meta:{async phoneNumber(){lookups++;return '51987654321';}},tasks:{},ai:{}});
  const make=(origin='https://app.example',auth=true)=>new Request('https://bot.example/api/link',{method:'POST',headers:{origin,'content-type':'application/json',...(auth?{authorization:'Bearer user-session'}:{})},body:JSON.stringify({company_id:company,phone:'51999999999',consent:true})});
  assert.equal((await app.handler(make('https://evil.example'))).status,403);
  assert.equal((await app.handler(make('https://app.example',false))).status,401);assert.equal(lookups,0);
  const response=await app.handler(make());assert.equal(response.status,200);
  assert.equal(response.headers.get('access-control-allow-origin'),'https://app.example');
  const result=await response.json();const code=result.message.split(' ')[1];assert.match(code,/^[a-f0-9]{48}$/);
  assert.equal(savedHash,createHash('sha256').update(code).digest('hex'));
  const url=new URL(result.whatsapp_url);assert.equal(url.hostname,'wa.me');assert.equal(url.pathname,'/51987654321');assert.equal(url.searchParams.get('text'),result.message);
  assert.equal(result.access_token,undefined);
  assert.equal((await app.handler(new Request('https://bot.example/api/link',{method:'OPTIONS',headers:{origin:'https://app.example'}}))).status,204);
});

test('normaliza teléfono de Meta; fallo de consulta conserva el código válido',async()=>{
  const meta=new Meta({metaToken:'private-token',phoneId:'123',graphVersion:'v99.0'},async url=>{assert.equal(url,'https://graph.facebook.com/v99.0/123?fields=display_phone_number');return Response.json({display_phone_number:'+51 987 654 321'});});
  assert.equal(await meta.phoneNumber(),'51987654321');
  const app=createApp({c:{adminOrigin:'https://bot.example'},db:{async user(){},async rpc(){return {expires_in:600};}},meta:{async phoneNumber(){throw Error('Meta unavailable');}},tasks:{},ai:{}});
  const response=await app.handler(new Request('https://bot.example/api/link',{method:'POST',headers:{authorization:'Bearer session','content-type':'application/json'},body:JSON.stringify({company_id:randomUUID(),phone:'51999999999',consent:true})}));
  assert.equal(response.status,200);const body=await response.json();assert.equal(body.whatsapp_url,null);assert.match(body.message,/^VINCULAR /);
});
