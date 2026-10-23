import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createHmac} from 'node:crypto';
import {createCronHandler} from '../src/api/vercel-cron.mjs';
import api from '../api/index.mjs';

test('Vercel cron exige secreto y GET; no procesa previews ni expone errores',async()=>{
  let calls=0,options;
  const appFactory=()=>({worker:{async tick(o){calls++;options=o;return {enabled:true,processed:2};}}});
  const env={CRON_SECRET:'private-test-secret',VERCEL_ENV:'production'};
  const run=createCronHandler({env,appFactory});
  const req=(method='GET',secret=env.CRON_SECRET)=>new Request('https://bot.example/api/cron',{method,headers:{authorization:`Bearer ${secret}`}});
  assert.equal((await run(req('POST'))).status,405);
  assert.equal((await run(req('GET','wrong'))).status,401);
  assert.equal((await createCronHandler({env:{},appFactory})(req())).status,401);
  assert.equal(calls,0);
  assert.equal((await run(req())).status,200);
  assert.deepEqual(options,{schedule:true,max:60,budgetMs:90000});
  assert.equal(calls,1);
  await createCronHandler({env:{...env,VERCEL_ENV:'preview'},appFactory})(req());
  assert.equal(calls,1);
  const failed=await createCronHandler({env,appFactory(){throw Error('private credential');}})(req());
  assert.equal(failed.status,503);
  assert.equal((await failed.text()).includes('private credential'),false);
});

test('entrada Vercel conserva query y cuerpo firmado; persiste antes de confirmar',async()=>{
  const saved=Object.fromEntries(['META_VERIFY_TOKEN','BOT_ENABLED','META_APP_SECRET','META_PHONE_NUMBER_ID','SUPABASE_URL','SUPABASE_SERVICE_ROLE_KEY'].map(k=>[k,process.env[k]]));
  const originalFetch=globalThis.fetch;let persisted=0;
  try {
    process.env.META_VERIFY_TOKEN='test-verification';process.env.BOT_ENABLED='true';
    process.env.META_APP_SECRET='test-signing-secret';process.env.META_PHONE_NUMBER_ID='123';
    process.env.SUPABASE_URL='https://database.example';process.env.SUPABASE_SERVICE_ROLE_KEY='test-private';
    globalThis.fetch=async(url)=>{assert.equal(String(url),'https://database.example/rest/v1/rpc/wa_enqueue');persisted++;return Response.json('test-job');};
    const response=await api.fetch(new Request('https://bot.example/api/webhook?hub.mode=subscribe&hub.verify_token=test-verification&hub.challenge=12345'));
    assert.equal(response.status,200);assert.equal(await response.text(),'12345');
    const invalid=await api.fetch(new Request('https://bot.example/api/webhook',{method:'POST',body:'{ "original": true }',headers:{'x-hub-signature-256':'sha256=invalid'}}));
    assert.equal(invalid.status,401);
    assert.equal(persisted,0);
    const payload=JSON.stringify({object:'whatsapp_business_account',entry:[{changes:[{field:'messages',value:{metadata:{phone_number_id:'123'},messages:[{id:'wamid.vercel-test',timestamp:String(Math.floor(Date.now()/1000)),from:'51987654321',type:'text',text:{body:'TAREAS'}}]}}]}]},null,2);
    const signature='sha256='+createHmac('sha256',process.env.META_APP_SECRET).update(payload).digest('hex');
    const accepted=await api.fetch(new Request('https://bot.example/api/webhook',{method:'POST',body:payload,headers:{'x-hub-signature-256':signature}}));
    assert.equal(accepted.status,200);assert.equal(persisted,1);
    assert.equal((await api.fetch(new Request('https://bot.example/api/not-found'))).status,404);
  }finally{globalThis.fetch=originalFetch;for(const [key,value] of Object.entries(saved))if(value===undefined)delete process.env[key];else process.env[key]=value;}
});
