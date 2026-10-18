import {DEFAULT_DOMAINS, habitDate, matches, isAllowed, safeTarget, origins, buildRules} from './policy.js';
const HOST = 'me.habitgate.bridge';
let state = null, busy = null, booted = false, applied = '', queue = Promise.resolve(), rulesOK = false, ruleError = null;
let liveTest = null, testedAt = null, testPassed = null, profileLabel = '', permissionIssue = '';
const ready = (async () => {
  const saved = await chrome.storage.local.get(['gateState', 'clientID', 'profileLabel']);
  state = saved.gateState || {snapshot: {domains: DEFAULT_DOMAINS, access: 'blocked'}};
  profileLabel = saved.profileLabel || '';
  if (!saved.clientID) await chrome.storage.local.set({clientID: crypto.randomUUID()});
  booted = true;
  await updateRules();
})();
function domains() { return state?.snapshot?.domains?.length ? state.snapshot.domains : DEFAULT_DOMAINS; }
function enforcing() { return state?.configured !== false; }
function allows() { return !enforcing() || isAllowed(state?.snapshot); }
async function permittedDomains() {
  const result = [];
  for (const domain of domains()) if (await chrome.permissions.contains({origins: origins([domain])})) result.push(domain);
  return result;
}
function finishTest(id, url) {
  if (!liveTest || liveTest.tabID !== id || !url?.startsWith(chrome.runtime.getURL('blocked.html') + '?target=')) return;
  if (safeTarget(url.split('?target=')[1], [liveTest.domain])) {
    testedAt = new Date().toISOString().replace(/\.\d{3}Z$/, 'Z'); testPassed = true; liveTest = null;
    native().catch(() => {});
  }
}
async function coverage() {
  if (liveTest && Date.now() - liveTest.started >= 15000) {
    testedAt = new Date().toISOString().replace(/\.\d{3}Z$/, 'Z'); testPassed = false; liveTest = null;
  }
  const {clientID} = await chrome.storage.local.get('clientID');
  const granted = await permittedDomains();
  return {clientID, label: profileLabel || `Chrome profile ${clientID.slice(0, 6)}`,
    privateAccess: await chrome.extension.isAllowedIncognitoAccess(), permissionsOK: granted.length === domains().length,
    missingDomains: domains().filter(d => !granted.includes(d)), checkedDomains: [...domains()],
    extensionVersion: chrome.runtime.getManifest().version, rulesOK, testedAt, testPassed, permissionIssue};
}
function view() {
  return {...state, allowed: isAllowed(state?.snapshot) && enforcing(), domains: domains(), setupPending: !enforcing(),
    activeHabitDate: habitDate(), hostAvailable: Boolean(state?.hostAvailable), rulesOK, ruleError};
}
async function updateRules() {
  const execute = async () => {
    const allowed = allows(), ds = [...domains()], granted = await permittedDomains();
    const stamp = JSON.stringify([allowed, enforcing(), ds, granted]);
    if (stamp === applied && rulesOK) return;
    rulesOK = false;
    try {
      const old = await chrome.declarativeNetRequest.getDynamicRules();
      await chrome.declarativeNetRequest.updateDynamicRules({removeRuleIds: old.map(x => x.id), addRules: buildRules(ds, allowed, chrome.runtime.getURL(''))});
      await chrome.declarativeNetRequest.updateEnabledRulesets({disableRulesetIds: ['default_block']});
      const scripts = await chrome.scripting.getRegisteredContentScripts();
      if (scripts.length) await chrome.scripting.unregisterContentScripts({ids: scripts.map(s => s.id)});
      if (granted.length && enforcing()) await chrome.scripting.registerContentScripts([{id: 'habit-gate', matches: origins(granted),
        js: ['content.js'], runAt: 'document_start', persistAcrossSessions: true}]);
      if (granted.length && enforcing()) {
        for (const tab of await chrome.tabs.query({url: origins(granted)})) {
          if (!tab.id) continue;
          try {
            if (!allowed && safeTarget(tab.url, ds)) await chrome.tabs.update(tab.id, {url: blockedURL(tab.url)});
            else await chrome.tabs.sendMessage(tab.id, {type: 'gateState', state: {...view(), allowed, targeted: true}});
          } catch { /* Tabs may close during a policy transition. */ }
        }
      }
      applied = stamp; rulesOK = true; ruleError = null;
    } catch {
      applied = ''; ruleError = 'Website rules could not be installed. Reload Habit Gate in Chrome, then check permissions.';
    }
    await chrome.action.setBadgeText({text: !rulesOK || granted.length !== ds.length ? '!' : allowed ? '' : '•'});
    await chrome.action.setBadgeBackgroundColor({color: '#2563eb'});
    scheduleBoundary();
  };
  queue = queue.catch(() => {}).then(execute);
  return queue;
}
function blockedURL(input) { return chrome.runtime.getURL('blocked.html') + '?target=' + (safeTarget(input, domains()) || ''); }
function scheduleBoundary() {
  const next = new Date(); next.setHours(4, 0, 0, 0);
  if (next <= new Date()) next.setDate(next.getDate() + 1);
  chrome.alarms.create('boundary', {when: next.getTime()});
}
async function native(command = 'getState') {
  await ready;
  // A read already in flight must not swallow a user's explicit refresh.
  if (busy) { await busy; if (command === 'getState') return {...view(), ...await coverage()}; }
  busy = (async () => {
    const before = await coverage();
    try {
      const received = await chrome.runtime.sendNativeMessage(HOST, {command, ...before});
      if (!received?.snapshot || received.snapshot.version !== 1 || !Array.isArray(received.snapshot.domains)) throw new Error('Invalid host response');
      state = {...received, hostAvailable: true};
    } catch {
      state = {...state, hostAvailable: false, hostError: 'Open Habit Gate on your Mac to reconnect. Only previously verified access remains usable until its expiry.'};
    }
    await updateRules();
    const after = await coverage();
    if (state.hostAvailable && JSON.stringify(before) !== JSON.stringify(after)) {
      try { await chrome.runtime.sendNativeMessage(HOST, {command: 'report', ...after}); } catch { state.hostAvailable = false; }
    }
    await chrome.storage.local.set({gateState: state});
    return {...view(), ...after};
  })();
  try { return await busy; } finally { busy = null; }
}
chrome.runtime.onMessage.addListener((message, sender, respond) => {
  (async () => {
    await ready;
    const internal = sender.url?.startsWith(chrome.runtime.getURL(''));
    if (message.type === 'guard') {
      await updateRules();
      return {allowed: allows(), snapshot: state?.snapshot, targeted: enforcing() && Boolean(safeTarget(message.url, domains()))};
    }
    if (!internal) throw new Error('Unsupported request');
    if (message.type === 'state') return await native();
    if (message.type === 'refresh') return await native('refresh');
    if (message.type === 'openHabitify') return await native('openHabitify');
    if (message.type === 'permissionIssue') { permissionIssue = String(message.issue || '').slice(0, 240); return await native(); }
    if (message.type === 'permissionsChanged') { applied = ''; return await native(); }
    if (message.type === 'label') {
      profileLabel = String(message.label || '').replace(/[\r\n\t]/g, ' ').trim().slice(0, 60);
      await chrome.storage.local.set({profileLabel}); return await native();
    }
    if (message.type === 'testProtection') {
      const current = await native();
      if (!enforcing() || allows() || !current.permissionsOK || !current.rulesOK || !current.hostAvailable) {
        return {testMessage: 'A live blocking test needs active, locked rules, a native connection and all website permissions.'};
      }
      liveTest = {domain: domains()[0], started: Date.now()}; testPassed = null; testedAt = null;
      const tab = await chrome.tabs.create({url: `https://${liveTest.domain}/`});
      if (liveTest) {
        liveTest.tabID = tab.id;
        try { const latest = await chrome.tabs.get(tab.id); finishTest(tab.id, latest.url); } catch { }
      }
      return {testMessage: 'Test site opened. A pass is recorded only if Chrome reaches Habit Gate’s blocked page.'};
    }
    throw new Error('Unsupported request');
  })().then(respond).catch(() => respond({...view(), permissionsOK: false, rulesOK: false, error: 'Protection could not be verified. Reopen the extension and check the native connection.'}));
  return true;
});
chrome.alarms.onAlarm.addListener(() => { native().catch(() => {}); });
chrome.runtime.onStartup.addListener(() => { native().catch(() => {}); });
chrome.runtime.onInstalled.addListener(() => { chrome.alarms.create('sync', {periodInMinutes: 0.5}); native().catch(() => {}); });
chrome.permissions.onAdded.addListener(() => { applied = ''; native().catch(() => {}); });
chrome.permissions.onRemoved.addListener(() => { applied = ''; native().catch(() => {}); });
chrome.tabs.onUpdated.addListener((id, change, tab) => {
  if (!booted || !tab.url) return;
  finishTest(id, tab.url);
  try {
    const url = new URL(tab.url);
    if (enforcing() && ['http:', 'https:'].includes(url.protocol) && matches(url.hostname, domains()) && !allows()) {
      chrome.tabs.update(id, {url: blockedURL(tab.url)}).catch(() => {});
    }
  } catch { /* Only HTTP(S) URLs are in scope. */ }
});
ready.then(async () => {
  if (!(await chrome.alarms.get('sync'))) await chrome.alarms.create('sync', {periodInMinutes: 0.5});
  scheduleBoundary(); await native();
}).catch(() => {});
