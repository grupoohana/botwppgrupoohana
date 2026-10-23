import { createApp } from './app.mjs';
import { equal } from '../security/crypto.mjs';

export function createCronHandler({env=process.env,appFactory=createApp}={}) {
  return async request => {
    const headers={'cache-control':'no-store'};
    if(request.method!=='GET')return new Response('Method not allowed',{status:405,headers:{...headers,allow:'GET'}});
    if(!env.CRON_SECRET||!equal(request.headers.get('authorization'),`Bearer ${env.CRON_SECRET}`))
      return Response.json({error:'No autorizado'},{status:401,headers});
    if(env.VERCEL_ENV&&env.VERCEL_ENV!=='production')
      return Response.json({enabled:false,processed:0},{headers});
    try {
      // Keep each batch below the 3-minute job lease and the function duration.
      const result=await appFactory().worker.tick({schedule:true,max:60,budgetMs:90000});
      return Response.json(result,{headers});
    }catch{return Response.json({error:'Worker unavailable'},{status:503,headers});}
  };
}
