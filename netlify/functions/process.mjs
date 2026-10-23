import { createApp } from '../../src/api/app.mjs';
import { equal } from '../../src/security/crypto.mjs';
export default async request => {
  const app=createApp();
  if(request.method!=='POST'||!app.c.workerSecret||!equal(request.headers.get('authorization'),`Bearer ${app.c.workerSecret}`))return;
  try {const result=await app.worker.tick({schedule:true,max:60,budgetMs:8*60000});console.log(JSON.stringify({event:'worker_batch',...result}));}
  catch(error){console.error(JSON.stringify({event:'worker_batch_failed',service:error.service||'internal'}));throw new Error('Worker batch failed');}
};
export const config={background:true};
