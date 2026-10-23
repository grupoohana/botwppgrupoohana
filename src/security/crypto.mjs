import { createHash, createHmac, randomBytes, timingSafeEqual } from 'node:crypto';
export const hash = value => createHash('sha256').update(value).digest('hex');
export const token = () => randomBytes(24).toString('hex');
export function equal(a, b) { const x = Buffer.from(a || ''); const y = Buffer.from(b || ''); return x.length > 0 && x.length === y.length && timingSafeEqual(x, y); }
export function validSignature(raw, signature, secret) { return !!secret && equal(signature, 'sha256=' + createHmac('sha256', secret).update(raw).digest('hex')); }
export function operationId(value) { const h = hash(value); return `${h.slice(0,8)}-${h.slice(8,12)}-4${h.slice(13,16)}-a${h.slice(17,20)}-${h.slice(20,32)}`; }
export const uuid = value => typeof value === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
export function phone(value) { const n = String(value || '').replace(/^\+/, ''); if (!/^[1-9]\d{7,14}$/.test(n)) throw new Error('Número inválido; usa formato internacional.'); return n; }
