import { request } from './http.mjs';
import { requireConfig } from '../config/env.mjs';
import { boundedBytes, validateImage } from '../evidence/images.mjs';
export class Meta {
  constructor(c, fetcher = fetch) { this.c = c; this.fetcher = fetcher; }
  async phoneNumber() {
    if(!/^\d+$/.test(this.c.phoneId))throw new Error('Canal inválido');
    const data=await this.api(`${this.c.phoneId}?fields=display_phone_number`);
    const value=String(data.display_phone_number||'').replace(/[^0-9]/g,'');
    if(!/^[1-9]\d{7,14}$/.test(value))throw new Error('Número del bot no disponible');
    return value;
  }
  async api(path, options = {}) {
    requireConfig(this.c, ['metaToken','graphVersion']);
    if (!/^v\d+\.\d+$/.test(this.c.graphVersion)) throw new Error('Versión Graph inválida.');
    const r = await request(`https://graph.facebook.com/${this.c.graphVersion}/${path}`, { ...options, headers: { authorization: `Bearer ${this.c.metaToken}`, ...(options.body instanceof FormData ? {} : { 'content-type': 'application/json' }) } }, { fetcher: this.fetcher, service: 'Meta' }); return r.json();
  }
  async download(id, expectedHash) {
    if (!/^\d+$/.test(id)) throw new Error('Identificador multimedia inválido.');
    const data = await this.api(`${id}?phone_number_id=${encodeURIComponent(this.c.phoneId)}`);
    const url = new URL(data.url); // Only Meta's HTTPS media host; redirects forbidden and size bounded while streaming.
    if (url.protocol !== 'https:' || !(url.hostname === 'lookaside.fbsbx.com' || url.hostname === 'lookaside.facebook.com') || url.port || url.username || url.password) throw new Error('Origen multimedia no permitido.');
    if (data.file_size > 5*1024*1024) throw new Error('Fotografía superior a 5 MB.');
    const r = await request(url, { headers: { authorization: `Bearer ${this.c.metaToken}` } }, { fetcher: this.fetcher, service: 'Meta multimedia' });
    return validateImage(await boundedBytes(r), data.mime_type, expectedHash || data.sha256);
  }
  async upload(image) { const form = new FormData(); form.set('messaging_product','whatsapp'); form.set('type',image.mime); form.set('file',new Blob([image.bytes],{type:image.mime}),`evidencia.${image.extension}`); return (await this.api(`${this.c.phoneId}/media`,{method:'POST',body:form})).id; }
  async send(to, payload, tracking) { try { return await this.api(`${this.c.phoneId}/messages`, { method: 'POST', body: JSON.stringify({ messaging_product: 'whatsapp', recipient_type: 'individual', to, ...payload, biz_opaque_callback_data: tracking }) }); } catch(error) { if(Number(error.status)>=500)error.uncertain=true;throw error; } }
}
