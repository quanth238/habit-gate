import {origins} from './policy.js';
export function requestedOrigins(current) {
  const missing = current?.missingDomains?.length ? current.missingDomains : current?.domains || [];
  return origins(missing);
}
export function permissionFailure(message = '') {
  const text = String(message).toLowerCase();
  if (text.includes('user gesture') || text.includes('user activation')) return 'Click Grant access directly in the Habit Gate popup to show Chrome’s permission request.';
  if (text.includes('manifest') || text.includes('optional permission') || text.includes('not specified')) return 'Chrome rejected the permission declaration. Load the current Habit Gate extension folder, then retry.';
  if (text.includes('policy') || text.includes('administrator')) return 'Chrome’s administrator policy prevents this website permission. Contact your browser administrator.';
  return 'Chrome rejected website access. Open Habit Gate’s extension Details → Site access and check the configured sites. No access was granted.';
}
