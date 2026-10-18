#!/bin/zsh
set -eu
HG_PROJECT="${0:A:h:h}"
cd "$HG_PROJECT"
HG_PLUGIN="$(xcrun --find swiftc | sed 's@/bin/swiftc$@/lib/swift/host/plugins/testing/libTestingMacros.dylib@')"
if [[ -f "$HG_PLUGIN" ]]; then
  swift test --disable-xctest --enable-swift-testing -Xswiftc -load-plugin-library -Xswiftc "$HG_PLUGIN"
else
  swift test --disable-xctest --enable-swift-testing
fi
node --test Tests/*.test.mjs
