export class ExternalError extends Error { constructor(service, status, retryable = false, uncertain = false) { super(`${service}: respuesta ${status}`); this.service = service; this.status = status; this.retryable = retryable; this.uncertain = uncertain; } }
export async function request(url, options = {}, { fetcher = fetch, service = 'Servicio', timeout = 15000 } = {}) {
  let response;
  try { response = await fetcher(url, { ...options, signal: options.signal || AbortSignal.timeout(timeout), redirect: 'error' }); }
  catch { throw new ExternalError(service, 'sin conexión', true, options.method === 'POST'); }
  if (!response.ok) { await response.body?.cancel(); throw new ExternalError(service, response.status, response.status === 429 || response.status >= 500); }
  return response;
}
