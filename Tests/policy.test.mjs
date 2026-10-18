import test from 'node:test';
import assert from 'node:assert/strict';
import {habitDate, isAllowed, matches, safeTarget, buildRules} from '../extension/policy.js';
process.env.TZ = 'Asia/Ho_Chi_Minh';
const now = new Date('2026-10-18T03:59:00+07:00');
const proof = {version:1, access:'allowed', habitDate:'2026-10-17', timezone:'Asia/Ho_Chi_Minh', utcOffsetMinutes:420,
  expiresAt:'2026-10-18T04:00:00+07:00', lastSyncedAt:'2026-10-18T03:58:00+07:00'};
test('4 AM and midnight use the chosen habit date', () => {
  assert.equal(habitDate(now),'2026-10-17');
  assert.equal(habitDate(new Date('2026-10-18T04:00:00+07:00')),'2026-10-18');
  assert.equal(habitDate(new Date('2026-10-18T00:00:00+07:00')),'2026-10-17');
});
test('verified offline proof expires at exactly 4 AM', () => {
  assert.equal(isAllowed(proof,now),true);
  assert.equal(isAllowed(proof,new Date('2026-10-18T04:00:00+07:00')),false);
});
test('unknown, stale, future, and wrong timezone proof stay blocked', () => {
  for (const patch of [{access:'blocked'},{version:2},{lastSyncedAt:null},{lastSyncedAt:'bad'},
    {lastSyncedAt:'2026-10-18T04:00:00+07:00'},{habitDate:'2026-10-16'},
    {utcOffsetMinutes:60},{expiresAt:'2026-10-19T04:00:00+07:00'}]) assert.equal(isAllowed({...proof,...patch},now),false);
  assert.equal(isAllowed(null,now),false);
});
test('IANA aliases do not incorrectly block identical local calendars', () => {
  assert.equal(isAllowed({...proof,timezone:'Asia/Saigon'},now),true);
});
test('host matching is bounded to the domain', () => {
  assert.equal(matches('m.facebook.com',['facebook.com']),true);
  assert.equal(matches('FACEBOOK.COM.',['facebook.com']),true);
  for (const h of ['notfacebook.com','facebook.com.evil.test','example.org']) assert.equal(matches(h,['facebook.com']),false);
});
test('continue targets reject non-web URLs, credentials, and unrelated hosts', () => {
  assert.equal(safeTarget('https://www.facebook.com/?a=1&b=2#posts',['facebook.com']),'https://www.facebook.com/');
  for (const u of ['javascript:alert(1)','chrome://settings','https://facebook.com.evil.test','https://user:password@facebook.com','not a url']) assert.equal(safeTarget(u,['facebook.com']),null);
});
test('blocked rules cover navigation and active site requests; allow rules are explicit', () => {
  const locked = buildRules(['facebook.com'],false,'chrome-extension://test/');
  assert.equal(locked.length,2); assert.equal(locked[0].action.type,'redirect');
  assert.equal(locked[1].action.type,'block'); assert.deepEqual(locked[1].condition.initiatorDomains,['facebook.com']);
  const allowed = buildRules(['facebook.com'],true,'chrome-extension://test/');
  assert.equal(allowed.length,4); assert.equal(allowed[2].action.type,'allowAllRequests');
  assert.ok(allowed[2].priority > locked[0].priority);
});
test('contradictory allowed snapshots cannot bypass remaining essentials',()=>{
  for (const status of ['inprogress','skipped','failed','unknown','configuration']) {
    assert.equal(isAllowed({...proof,habits:[{due:true,status}]},now),false);
  }
});
test('blocked redirects retain only the site origin, without private paths or queries',()=>{
  const rule=buildRules(['facebook.com'],false,'chrome-extension://test/')[0];
  const input='https://www.facebook.com/messages/private-person?token=private#draft';
  const target=input.replace(new RegExp(rule.condition.regexFilter),(_,origin)=>origin);
  assert.equal(target,'https://www.facebook.com');
  assert.equal(safeTarget(input,['facebook.com']),'https://www.facebook.com/');
});
test('browser and native use the same proof fixtures',async()=>{
  const {readFile}=await import('node:fs/promises');
  const fixtures=JSON.parse(await readFile(new URL('./proof-cases.json',import.meta.url),'utf8'));
  const prior=process.env.TZ;
  try { for(const fixture of fixtures) {
    process.env.TZ=fixture.timezone;
    assert.equal(isAllowed(fixture.snapshot,new Date(fixture.now)),fixture.allowed,fixture.name);
  }} finally {process.env.TZ=prior;}
});
