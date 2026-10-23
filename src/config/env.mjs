export function config(env = process.env) {
  const number = (name, fallback) => { const value = Number(env[name] || fallback); if (!Number.isSafeInteger(value) || value < 1) throw new Error(`Variable inválida: ${name}`); return value; };
  return {
    supabaseUrl: (env.SUPABASE_URL || '').replace(/\/$/, ''), serviceKey: env.SUPABASE_SERVICE_ROLE_KEY || '',
    appSecret: env.META_APP_SECRET || '', verifyToken: env.META_VERIFY_TOKEN || '', metaToken: env.META_ACCESS_TOKEN || '', phoneId: env.META_PHONE_NUMBER_ID || '', graphVersion: env.META_GRAPH_VERSION || '',
    openaiKey: env.OPENAI_API_KEY || '', model: env.OPENAI_MODEL || 'gpt-5-mini', maxOutput: number('OPENAI_MAX_OUTPUT_TOKENS', 1500), dailyCalls: number('OPENAI_DAILY_CALL_LIMIT', 200), dailyTokens: number('OPENAI_DAILY_TOKEN_BUDGET', 300000),
    adminOrigin: env.BOT_ADMIN_ORIGIN || '', appUrl: env.APP_URL || '', workerSecret: env.BOT_WORKER_SECRET || '', enabled: env.BOT_ENABLED === 'true', aiEnabled: env.AI_ENABLED === 'true', port: number('PORT', 8090),
  };
}
export function requireConfig(c, names) { for (const name of names) if (!c[name]) throw new Error(`Falta configuración de ${name}`); }
