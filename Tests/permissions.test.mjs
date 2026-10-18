import test from 'node:test';
import assert from 'node:assert/strict';
import {requestedOrigins, permissionFailure} from '../extension/permissions.js';
import manifest from '../extension/manifest.json' with {type:'json'};
test('custom website request uses declared explicit schemes and only missing domains',()=>{
  const result=requestedOrigins({domains:['facebook.com','messenger.com'],missingDomains:['messenger.com']});
  assert.deepEqual(result,['https://*.messenger.com/*','http://*.messenger.com/*']);
  for(const pattern of result) assert.ok(manifest.optional_host_permissions.some(p=>p.split('://')[0]===pattern.split('://')[0]));
});
test('permission errors give a recovery action without repeating a blind reload loop',()=>{
  assert.match(permissionFailure('This function must be called during a user gesture'),/Click Grant access directly/);
  assert.match(permissionFailure('Only permissions specified in the manifest may be requested'),/permission declaration/);
  assert.match(permissionFailure('Blocked by administrator policy'),/administrator/);
  assert.doesNotMatch(permissionFailure('unexpected private details'),/unexpected private details/);
});
