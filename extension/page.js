import {safeTarget, origins} from './policy.js';
import {syncFeedback} from './feedback.js';
import {requestedOrigins, permissionFailure} from './permissions.js';
import {randomFocusQuote} from './quotes.js';
const $ = id => document.getElementById(id);
const put = (id, text) => { const element = $(id); if (element) element.textContent = text; };
const popup = document.body.classList.contains('popup');
const minimal = document.body.classList.contains('minimal-page');
if ($('quote')) $('quote').textContent = randomFocusQuote();
let current = null, refreshing = false, lastSyncRequest = 0, syncRequest = null;
const rawTarget = location.href.includes('?target=') ? location.href.slice(location.href.indexOf('?target=') + 8) : null;

function headline(first, second) {
  if (popup) { put('title', `${first} ${second}`); return; }
  if (minimal) { put('title', [first, second].filter(Boolean).join(' ')); return; }
  const top = document.createElement('span'), accent = document.createElement('span');
  top.textContent = first; accent.textContent = second; accent.className = 'accent';
  $('title').replaceChildren(top, accent);
}
function siteInfo(target) {
  if (!target) return null;
  const host = new URL(target).hostname;
  const names = {'facebook.com':'Facebook', 'fb.com':'Facebook', 'instagram.com':'Instagram', 'x.com':'X', 'twitter.com':'Twitter', 'messenger.com':'Messenger'};
  const domain = Object.keys(names).find(domain => host === domain || host.endsWith('.' + domain));
  return {name: names[domain] || host.replace(/^www\./, ''), mark: domain === 'facebook.com' || domain === 'fb.com' ? 'f' : domain === 'instagram.com' ? '◎' : domain === 'x.com' || domain === 'twitter.com' ? '𝕏' : '↗'};
}
function habitRow(habit, index) {
  const li = document.createElement('li'), number = document.createElement('span'), copy = document.createElement('div');
  const done = habit.status === 'completed', rest = !habit.due;
  number.className = 'habit-number' + (done ? ' complete' : '');
  number.textContent = done ? '✓' : String(index + 1).padStart(2, '0'); number.setAttribute('aria-hidden', 'true');
  copy.className = 'habit-copy';
  const name = document.createElement('span'); name.className = 'habit-name'; name.textContent = habit.name;
  const detail = document.createElement('small'); detail.className = 'habit-detail';
  const labels = {completed:'Complete', inprogress:'Not finished', skipped:'Skipped · still required', failed:'Failed · still required', configuration:'Needs attention', unknown:'Not yet verified'};
  const label = rest ? 'Not scheduled for this day' : labels[habit.status] || 'Not yet verified';
  detail.textContent = rest ? 'Not scheduled for this habit date' : habit.detail && habit.detail.toLowerCase() !== label.toLowerCase() ?
    `${habit.detail}${done || habit.status !== 'inprogress' ? ' · ' + label : ''}` : label;
  const state = document.createElement('span'); state.className = 'habit-state' + (done ? ' complete' : rest ? ' rest' : '');
  state.textContent = done ? '✓' : rest ? '−' : ''; state.setAttribute('aria-hidden', 'true');
  copy.append(name, detail); li.append(number, copy, state); return li;
}
async function render() {
  if (refreshing) return; refreshing = true;
  try {
    current = await chrome.runtime.sendMessage({type: 'state'});
    const snapshot = current?.snapshot || {}, allowed = Boolean(current?.allowed);
    document.body.dataset.access = allowed ? 'allowed' : 'blocked';
    const habits = Array.isArray(snapshot.habits) ? snapshot.habits : [];
    const due = habits.filter(h => h.due), completed = due.filter(h => h.status === 'completed');
    const remaining = due.length - completed.length, restDay = allowed && !due.length;
    headline(allowed ? restDay ? 'No habits due.' : 'Essentials done.' : 'Your habits', allowed ? restDay ? 'Enjoy your day.' : 'Time for you.' : 'come first.');
    put('access-label', allowed ? 'Social sites unlocked' : 'Social sites blocked');
    put('reason', snapshot.reason || 'Open Habit Gate on your Mac to choose your essential habits.');
    put('remaining', !habits.length ? 'Connect Habitify and choose your essentials.' : restDay ? 'A verified rest day. Make it yours.' : allowed ? 'A little effort. A day well started.' : `${remaining} ${remaining === 1 ? 'habit' : 'habits'} remaining. One step at a time.`);
    const percent = due.length ? Math.round(completed.length / due.length * 100) : allowed ? 100 : 0;
    put('count', !habits.length ? 'Completion not verified' : restDay ? 'Verified rest day' : `${completed.length} of ${due.length} complete`);
    put('progress-percent', `${percent}%`);
    $('progress').max = Math.max(due.length, 1); $('progress').value = allowed ? Math.max(due.length, 1) : completed.length;
    if ($('ring')) $('ring').style.setProperty('--completion', `${percent}%`);
    if ($('ring-count')) {
      const total = document.createElement('span'); total.textContent = `/ ${due.length}`;
      $('ring-count').replaceChildren(document.createTextNode(!habits.length ? '—' : restDay ? '✓' : String(completed.length)), ...(!habits.length || restDay ? [] : [total]));
    }
    $('habits').replaceChildren(...habits.filter(h => h.due && h.status !== 'completed').map(habitRow));
    if (!habits.length) {
      const li = document.createElement('li'); li.className = 'habit-detail';
      li.textContent = current?.configured ? 'Waiting for verified habit data.' : 'Choose your essential habits in the Mac app.';
      $('habits').append(li);
    }
    const safe = rawTarget && safeTarget(rawTarget, current?.domains || []), site = siteInfo(safe);
    if ($('continue')) $('continue').hidden = !allowed || !safe;
    if (minimal) {
      headline(allowed ? restDay ? 'A day to recharge.' : 'You’re all set.' : 'Blocked for now.', '');
      const configurationProblem = habits.some(h => h.status === 'configuration');
      put('reason', allowed ? restDay ? 'Your rest day is verified. Enjoy your time.' : `Your essentials are complete.${site ? ` ${site.name} is ready for you.` : ' Enjoy your time.'}` :
        !habits.length || configurationProblem ? snapshot.reason || 'Open Habit Gate on your Mac to check your essentials.' :
        `Complete your habits to open ${site?.name || 'your selected sites'}.`);
      const empty = $('empty-message');
      empty.hidden = !allowed;
      empty.textContent = restDay ? 'No essentials are scheduled for this habit date.' : 'All scheduled essentials are complete.';
    }
    put('site', site ? `${site.name} ${allowed ? 'is ready for you' : 'is on hold'}` : 'YOUR ESSENTIALS FIRST');
    put('site-mark', site?.mark || '↗');
    put('action-note', allowed ? 'Enjoy your time. You’ve made room for what matters.' : 'Your feed will be here when you’re ready.');
    const habitDate = snapshot.habitDate || current?.activeHabitDate || 'Checking…';
    put('date', popup ? `Habit date · ${habitDate} · resets 4 AM` : habitDate);
    if ($('late-night-note')) $('late-night-note').hidden = new Date().getHours() >= 4;
    const feedback = syncFeedback(snapshot, current?.hostAvailable, syncRequest);
    put('status', feedback.message);
    if (syncRequest && !feedback.pending) syncRequest = null;
    $('sync').disabled = Boolean(syncRequest);
    $('status').classList.toggle('warning', Boolean(feedback.warning));
    $('sync-dot')?.classList.toggle('warning', Boolean(feedback.warning));
    $('permissions').hidden = current?.permissionsOK === true;
    const missing = current?.missingDomains?.join(', ');
    put('coverage', !current?.hostAvailable ? 'Native connection not verified.' :
      !current?.permissionsOK ? `Website access missing${missing ? ': ' + missing : '. Open the popup to check.'}` :
      !current?.rulesOK ? current?.ruleError || 'Network rules are not verified. Reload the extension.' :
      `Rules installed · ${current.privateAccess ? 'Private windows enabled' : 'Private windows not protected'}`);
    if ($('profile-label') && document.activeElement !== $('profile-label')) $('profile-label').value = current?.label || '';
    if ($('test')) $('test').disabled = current?.allowed || current?.setupPending || !current?.permissionsOK || !current?.rulesOK || !current?.hostAvailable;
    if (current?.testPassed != null) put('test-result', (current.testPassed ? 'Live redirect test passed at ' : 'Live redirect test did not reach the blocked page. Check this profile’s permissions. Last test: ') + new Date(current.testedAt).toLocaleTimeString() + '.');
    if (current?.setupPending) { headline('Setup ready.', 'Review in the Mac app.'); put('reason', 'Protection begins only after Review & activate in Habit Gate.'); }
    if (current?.permissionIssue) { put('status', current.permissionIssue); $('status').classList.add('warning'); }
    if (current?.error) { put('status', current.error); $('status').classList.add('warning'); }
    if ($('notice')) {
      const issue = !current?.hostAvailable ? 'Connection unavailable. Open Habit Gate on your Mac.' :
        !current?.permissionsOK || !current?.rulesOK || current?.permissionIssue ? 'Website protection needs attention. View details.' :
        current?.error || feedback.warning ? 'Sync needs attention. View details.' : '';
      put('notice', issue); $('notice').hidden = !issue;
    }
    if ($('back')) $('back').textContent = history.length > 1 ? 'Go back' : 'Open a blank tab';

  } catch {
    current = null;
    document.body.dataset.access = 'blocked';
    headline('Access needs', 'verification.');
    put('access-label', 'Verification unavailable');
    put('reason', 'Open Habit Gate on your Mac to reconnect. Access stays blocked until it can be verified.');
    put('remaining', 'Waiting for a verified connection.');
    if ($('continue')) $('continue').hidden = true;
    put('status', 'Unable to verify access. Open Habit Gate on your Mac.');
    $('status').classList.add('warning'); $('sync-dot')?.classList.add('warning');
    if ($('notice')) { put('notice', 'Connection unavailable. Open Habit Gate on your Mac.'); $('notice').hidden = false; }
  } finally { refreshing = false; }
}
$('open').addEventListener('click', async () => { await chrome.runtime.sendMessage({type: 'openHabitify'}); });
$('sync').addEventListener('click', async () => {
  if (Date.now() - lastSyncRequest < 3000) return; lastSyncRequest = Date.now();
  syncRequest = {baseline: current?.snapshot?.lastSyncedAt, started: Date.now()};
  $('sync').disabled = true; put('status', 'Sync requested. Waiting for new verification…');
  try { await chrome.runtime.sendMessage({type: 'refresh'}); await render(); }
  catch { put('status', 'Could not request a sync. Open Habit Gate on your Mac.'); $('status').classList.add('warning'); }
  finally { $('sync').disabled = Boolean(syncRequest); }
});
$('permissions').addEventListener('click', () => {
  const sites = requestedOrigins(current);
  if (!sites.length) { put('status', 'Reconnect the Mac app before requesting website access.'); return; }
  // Invoke Chrome synchronously in the click event, with explicit schemes matching
  // optional_host_permissions. Request only missing sites, never every host.
  const fail = async error => {
    const issue = permissionFailure(error?.message || error);
    put('status', issue); $('permissions').hidden = false;
    await chrome.runtime.sendMessage({type:'permissionIssue', issue});
  };
  try {
    chrome.permissions.request({origins: sites}, async granted => {
      const error = chrome.runtime.lastError;
      if (error) { await fail(error); return; }
      await chrome.runtime.sendMessage({type:'permissionIssue', issue:granted ? '' : 'Website access was not granted. You can retry the request from this popup.'});
      await chrome.runtime.sendMessage({type:'permissionsChanged'}); await render();
      if (!granted || !current?.permissionsOK) put('status', 'Website access is still missing for the named sites in this Chrome profile.');
    });
  } catch (error) { fail(error).catch(() => {}); }
});
$('save-label')?.addEventListener('click', async () => {
  await chrome.runtime.sendMessage({type:'label', label:$('profile-label').value}); await render();
});
$('test')?.addEventListener('click', async () => {
  const result = await chrome.runtime.sendMessage({type:'testProtection'}); put('test-result', result?.testMessage || 'Test could not start.');
});
$('continue')?.addEventListener('click', async () => {
  await render(); const target = safeTarget(rawTarget, current?.domains || []);
  if (current?.allowed && target) location.replace(target);
});
$('back')?.addEventListener('click', () => { if (history.length > 1) history.back(); else location.replace('about:blank'); });
$('details')?.addEventListener('click', () => $('details-dialog').showModal());
$('close-details')?.addEventListener('click', () => $('details-dialog').close());
render(); setInterval(() => { if (!document.hidden) render(); }, 5000);
window.addEventListener('focus', render);
document.addEventListener('visibilitychange', () => { if (!document.hidden) render(); });
