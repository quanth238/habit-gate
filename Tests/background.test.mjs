import test from 'node:test';
import assert from 'node:assert/strict';

test('browser adapter integrates native state, permissions, redirects and expiry', async () => {
  const RealDate = Date; let clock = new RealDate('2026-10-18T10:00:00+07:00').getTime();
  process.env.TZ = 'Asia/Ho_Chi_Minh';
  globalThis.Date = class extends RealDate { constructor(...args) { super(...(args.length ? args : [clock])); } static now() { return clock; } };
  const event = () => ({listeners: [], addListener(f) {this.listeners.push(f);}});
  const storage = {}; let rules = [], scripts = [], disabled = [], calls = 0, failHost = false;
  let denied = new Set(), failScripts = false; const requests = [];
  let answer = {configured:true,hostAvailable:true,snapshot:{version:1,access:'blocked',domains:['facebook.com'],
    habitDate:'2026-10-18',timezone:'Asia/Ho_Chi_Minh',utcOffsetMinutes:420,expiresAt:'2026-10-19T04:00:00+07:00',lastSyncedAt:'2026-10-18T10:00:00+07:00',habits:[]}};
  globalThis.chrome = {
    storage:{local:{get:async () => storage,set:async value => Object.assign(storage,value)}},
    permissions:{contains:async ({origins}) => !origins.some(p => [...denied].some(d => p.includes(d))),onAdded:event(),onRemoved:event()},
    scripting:{getRegisteredContentScripts:async () => scripts,unregisterContentScripts:async () => {scripts=[];},registerContentScripts:async list => {if(failScripts)throw Error('fixture script failure');scripts=list;}},
    tabs:{query:async () => [],update:async () => {},sendMessage:async () => {},onUpdated:event()},
    extension:{isAllowedIncognitoAccess:async () => false},
    declarativeNetRequest:{getDynamicRules:async () => rules,updateDynamicRules:async ({addRules}) => {rules=addRules;},updateEnabledRulesets:async ({disableRulesetIds}) => {disabled=disableRulesetIds;}},
    action:{setBadgeText:async () => {},setBadgeBackgroundColor:async () => {}},
    alarms:{create:async () => {},get:async () => true,onAlarm:event()},
    runtime:{getManifest:()=>({version:'1.1.0'}),getURL:path => 'chrome-extension://test/'+path,onMessage:event(),onStartup:event(),onInstalled:event(),
      sendNativeMessage:async (_,request) => {calls++;requests.push(request);assert.equal(request.privateAccess,false);if(failHost)throw Error('unavailable');return structuredClone(answer);}}
  };
  try {
    await import('../extension/background.js');
    const listener = chrome.runtime.onMessage.listeners[0];
    const message = (body,sender={url:'chrome-extension://test/blocked.html'}) => new Promise(resolve => listener(body,sender,resolve));
    let result = await message({type:'state'});
    assert.equal(result.allowed,false);assert.equal(rules.some(r=>r.action.type==='allowAllRequests'),false);
    assert.deepEqual(disabled,['default_block']);assert.equal(scripts[0].runAt,'document_start');
    answer.snapshot.access='allowed';
    result=await message({type:'state'});assert.equal(result.allowed,true);assert.ok(rules.some(r=>r.action.type==='allowAllRequests'));
    failHost=true;result=await message({type:'state'});assert.equal(result.hostAvailable,false);assert.equal(result.allowed,true);
    clock=new RealDate('2026-10-19T04:00:00+07:00').getTime();
    result=await message({type:'guard',url:'https://facebook.com/'},{url:'https://facebook.com/'});
    assert.equal(result.allowed,false);assert.equal(rules.some(r=>r.action.type==='allowAllRequests'),false);
    // A new domain is reported immediately, not one polling cycle later.
    clock=new RealDate('2026-10-18T10:00:00+07:00').getTime(); failHost=false;
    answer.snapshot.access='blocked'; answer.snapshot.domains=['facebook.com','messenger.com']; denied.add('messenger.com');
    result=await message({type:'state'});assert.deepEqual(result.missingDomains,['messenger.com']);assert.equal(result.permissionsOK,false);
    assert.deepEqual(requests.at(-1).checkedDomains,answer.snapshot.domains);
    denied.clear();await message({type:'permissionsChanged'});
    result=await message({type:'state'});assert.equal(result.permissionsOK,true);assert.equal(result.rulesOK,true);
    // Failed rule application stays visible and retries, rather than caching success.
    failScripts=true;answer.snapshot.domains.push('instagram.com');
    result=await message({type:'state'});assert.equal(result.rulesOK,false);assert.ok(result.ruleError);
    failScripts=false;result=await message({type:'state'});assert.equal(result.rulesOK,true);
    answer.configured=false;result=await message({type:'state'});assert.equal(result.setupPending,true);
    result=await message({type:'guard',url:'https://facebook.com/'},{url:'https://facebook.com/'});assert.equal(result.targeted,false);
    answer.configured=true;
    const prior=calls;
    await message({type:'refresh'},{url:'https://facebook.com/'});assert.equal(calls,prior,'content cannot trigger privileged native commands');
    result=await message({type:'guard',url:'https://notfacebook.com/'},{url:'https://notfacebook.com/'});assert.equal(result.targeted,false);
  } finally { globalThis.Date=RealDate;delete globalThis.chrome; }
});
