export const DEFAULT_DOMAINS = ['facebook.com', 'instagram.com', 'x.com', 'twitter.com', 'fb.com'];
export function habitDate(now = new Date()) {
  const date = new Date(now); if (date.getHours() < 4) date.setDate(date.getDate() - 1);
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
}
export function matches(host, domains) {
  host = host.toLowerCase().replace(/\.$/, '');
  return domains.some(domain => host === domain || host.endsWith('.' + domain));
}
export function isAllowed(snapshot, now = new Date()) {
  if (!snapshot || snapshot.version !== 1 || snapshot.access !== 'allowed') return false;
  if (Array.isArray(snapshot.habits) && snapshot.habits.some(h => h.status === 'configuration' || (h.due && h.status !== 'completed'))) return false;
  const expiry = new Date(snapshot.expiresAt), synced = new Date(snapshot.lastSyncedAt);
  const maxExpiry = new Date(now); maxExpiry.setHours(4, 0, 0, 0);
  if (now.getHours() >= 4) maxExpiry.setDate(maxExpiry.getDate() + 1);
  return snapshot.habitDate === habitDate(now) && snapshot.utcOffsetMinutes === -now.getTimezoneOffset() &&
    Boolean(snapshot.lastSyncedAt) && Number.isFinite(synced.getTime()) && synced <= new Date(now.getTime() + 5000) &&
    expiry > now && expiry <= maxExpiry;
}
export function safeTarget(input, domains) {
  try {
    const url = new URL(input);
    return ['http:', 'https:'].includes(url.protocol) && !url.username && !url.password && matches(url.hostname, domains) ? url.origin + "/" : null;
  } catch { return null; }
}
export function origins(domains) { return domains.flatMap(d => [`https://*.${d}/*`, `http://*.${d}/*`]); }
export function buildRules(domains, allowed, extensionBase) {
  const navigation = {id: 100, priority: 2, action: {type: 'redirect', redirect: {regexSubstitution: `${extensionBase}blocked.html?target=\\1`}},
    condition: {regexFilter: '^(https?://[^/@?#]+)(?:[/?#].*)?$', requestDomains: domains, resourceTypes: ['main_frame']}};
  const resources = {id: 101, priority: 2, action: {type: 'block'}, condition: {initiatorDomains: domains,
    resourceTypes: ['sub_frame', 'stylesheet', 'script', 'image', 'font', 'object', 'xmlhttprequest', 'ping', 'media', 'websocket', 'other']}};
  const rules = [navigation, resources];
  if (allowed) {
    rules.push({id: 102, priority: 10, action: {type: 'allowAllRequests'}, condition: {requestDomains: domains, resourceTypes: ['main_frame', 'sub_frame']}});
    rules.push({id: 103, priority: 10, action: {type: 'allow'}, condition: {initiatorDomains: domains}});
  }
  return rules;
}
