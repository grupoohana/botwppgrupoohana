import { createApp } from '../src/api/app.mjs';

// Web Standard handler: pass the original body through for Meta's HMAC check.
export default {
  async fetch(request) {
    try { return await createApp().handler(request); }
    catch { return Response.json({error:'Servicio no disponible'},{status:503,headers:{'cache-control':'no-store'}}); }
  },
};
