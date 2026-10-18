#!/bin/zsh
set -eu
HG_PROJECT="${0:A:h:h}"
cd "$HG_PROJECT"
swift build -c release --product HabitGate
swift build -c release --product HabitGateBridge
HG_BIN="$(swift build -c release --show-bin-path)"
HG_APP="$HG_PROJECT/dist/Habit Gate.app"
mkdir -p "$HG_APP/Contents/MacOS" "$HG_APP/Contents/Resources"
cp "$HG_BIN/HabitGate" "$HG_APP/Contents/MacOS/HabitGate"
cp "$HG_BIN/HabitGateBridge" "$HG_APP/Contents/MacOS/HabitGateBridge"
cp "$HG_PROJECT/Resources/Info.plist" "$HG_APP/Contents/Info.plist"
cp "$HG_PROJECT/Resources/extension-id.txt" "$HG_APP/Contents/Resources/extension-id.txt"
cp "$HG_PROJECT/Resources/AppIcon.icns" "$HG_APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$HG_APP"
print "Built: $HG_APP"
