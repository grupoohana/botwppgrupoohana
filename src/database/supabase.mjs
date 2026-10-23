import { request } from '../services/http.mjs';
import { requireConfig } from '../config/env.mjs';
export class Database {
  constructor(c, fetcher = fetch) { this.c = c; this.fetcher = fetcher; }
  async rpc(name, args, jwt) {
    requireConfig(this.c, ['supabaseUrl','serviceKey']);
    const r = await request(`${this.c.supabaseUrl}/rest/v1/rpc/${name}`, { method: 'POST', headers: { apikey: this.c.serviceKey, authorization: `Bearer ${jwt || this.c.serviceKey}`, 'content-type': 'application/json' }, body: JSON.stringify(args) }, { fetcher: this.fetcher, service: 'Supabase', readErrorCode:true });
    return r.json();
  }
  async user(jwt) {
    const r = await request(`${this.c.supabaseUrl}/auth/v1/user`, { headers: { apikey: this.c.serviceKey, authorization: `Bearer ${jwt}` } }, { fetcher: this.fetcher, service: 'Autenticación' }); return r.json();
  }
  async login(email,password) {
    const r=await request(`${this.c.supabaseUrl}/auth/v1/token?grant_type=password`,{method:'POST',headers:{apikey:this.c.serviceKey,'content-type':'application/json'},body:JSON.stringify({email,password})},{fetcher:this.fetcher,service:'Autenticación'});return r.json();
  }
  async upload(path, bytes, mime) {
    await request(`${this.c.supabaseUrl}/storage/v1/object/evidencias-tareas/${path.split('/').map(encodeURIComponent).join('/')}`, { method: 'POST', headers: { apikey: this.c.serviceKey, authorization: `Bearer ${this.c.serviceKey}`, 'content-type': mime, 'x-upsert': 'true' }, body: bytes }, { fetcher: this.fetcher, service: 'Storage' });
  }
  async signedImage(path) {
    const r = await request(`${this.c.supabaseUrl}/storage/v1/object/sign/evidencias-tareas/${path.split('/').map(encodeURIComponent).join('/')}`, { method: 'POST', headers: { apikey: this.c.serviceKey, authorization: `Bearer ${this.c.serviceKey}`, 'content-type': 'application/json' }, body: JSON.stringify({ expiresIn: 300 }) }, { fetcher: this.fetcher, service: 'Storage' });
    const data = await r.json(); return this.c.supabaseUrl + '/storage/v1' + data.signedURL;
  }
  async image(path) {
    const r = await request(`${this.c.supabaseUrl}/storage/v1/object/authenticated/evidencias-tareas/${path.split('/').map(encodeURIComponent).join('/')}`, { headers: { apikey: this.c.serviceKey, authorization: `Bearer ${this.c.serviceKey}` } }, { fetcher: this.fetcher, service: 'Storage' }); return r;
  }
}
