import { createApp } from '../../src/api/app.mjs';
export default async () => {
  const app=createApp();
  if(!app.c.enabled)return;
  if(!app.c.workerSecret||!process.env.URL)throw new Error('Falta URL automática de Netlify o BOT_WORKER_SECRET');
  const origin=new URL(process.env.URL);if(origin.protocol!=='https:')throw new Error('Origen de despliegue inválido');
  try {const response=await fetch(new URL('/.netlify/functions/process',origin),{method:'POST',headers:{authorization:`Bearer ${app.c.workerSecret}`},signal:AbortSignal.timeout(10000)});if(!response.ok)throw new Error('Background dispatch rejected');console.log(JSON.stringify({event:'worker_dispatched',status:response.status}));}
  catch(error){console.error(JSON.stringify({event:'worker_tick_failed',service:error.service||'internal'}));throw new Error('Worker failed');}
};
export const config={schedule:'* * * * *'};
