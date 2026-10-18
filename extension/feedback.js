export function syncFeedback(snapshot = {}, hostAvailable, request, now = Date.now()) {
  const stamp = snapshot.lastSyncedAt;
  const prior = stamp ? ` Last verified ${new Date(stamp).toLocaleTimeString([], {hour:'2-digit',minute:'2-digit'})}.` : '';
  if (!hostAvailable) return {message:'Native connection unavailable. Open Habit Gate on your Mac.' + prior, warning:true, pending:false};
  if (snapshot.syncError) return {message:'Unable to sync. ' + snapshot.syncError + prior + ' Only valid prior completion can permit access.', warning:true, pending:false};
  if (request && stamp && Number.isFinite(Date.parse(request.baseline)) && Date.parse(stamp) > Date.parse(request.baseline)) return {message:'Successfully verified at ' + new Date(stamp).toLocaleTimeString([], {hour:'2-digit',minute:'2-digit'}) + '.', fresh:true, pending:false};
  if (snapshot.syncState === 'checking') return {message:'Checking Habitify…' + prior, pending:Boolean(request)};
  if (request) return now - request.started < 30000 ? {message:'Sync requested. Waiting for new verification…' + prior, pending:true} :
    {message:'A new verification has not finished. Check the Mac app or retry.' + prior, warning:true, pending:false};
  return {message:stamp ? 'Previously verified at ' + new Date(stamp).toLocaleTimeString([], {hour:'2-digit',minute:'2-digit'}) + '. Checks normally run every minute.' : 'Waiting for verified habit data.', pending:false};
}
