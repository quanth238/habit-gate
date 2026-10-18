import test from 'node:test';
import assert from 'node:assert/strict';
import {syncFeedback} from '../extension/feedback.js';
const stamp='2026-10-18T07:00:00Z';
const request={baseline:stamp,started:1000};
test('cached refresh acknowledgement never claims fresh verification',()=>{
  const state=syncFeedback({lastSyncedAt:stamp},true,request,2000);
  assert.equal(state.pending,true);assert.equal(state.fresh,undefined);assert.match(state.message,/requested/);
});
test('cloud check is distinct from requested and prior verified data',()=>{
  assert.match(syncFeedback({lastSyncedAt:stamp,syncState:'checking'},true,request,2000).message,/Checking/);
});
test('only a newer verified timestamp finishes a requested sync',()=>{
  const state=syncFeedback({lastSyncedAt:'2026-10-18T07:01:00Z'},true,request,2000);
  assert.equal(state.fresh,true);assert.equal(state.pending,false);
});
test('network failure explains cached proof without calling it fresh',()=>{
  const state=syncFeedback({lastSyncedAt:stamp,syncError:'Network unavailable'},true,request,2000);
  assert.equal(state.warning,true);assert.equal(state.pending,false);assert.equal(state.fresh,undefined);assert.match(state.message,/prior completion/);
});
test('a lost refresh gets a recovery message without a success claim',()=>{
  const state=syncFeedback({lastSyncedAt:stamp},true,request,40000);
  assert.equal(state.pending,false);assert.equal(state.warning,true);assert.match(state.message,/not finished/);
});
test('native disconnection is not confused with verified cloud progress',()=>{
  const state=syncFeedback({lastSyncedAt:stamp},false,request,2000);
  assert.equal(state.warning,true);assert.match(state.message,/Native connection unavailable/);
});
test('an unknown baseline cannot turn cached data into a fresh success',()=>{
  const state=syncFeedback({lastSyncedAt:stamp},true,{started:Date.parse(stamp)+60000},Date.parse(stamp)+61000);
  assert.equal(state.fresh,undefined);assert.equal(state.pending,true);
});
