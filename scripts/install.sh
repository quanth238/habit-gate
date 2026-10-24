#!/bin/zsh
set -eu
HG_PROJECT="${0:A:h:h}"
HG_DEST="/Applications/Habit Gate.app"
HG_SUPPORT="$HOME/Library/Application Support/HabitGate"
HG_BUILD_APP="$HG_PROJECT/dist.noindex/Habit Gate.app"
if [[ ! -x "$HG_BUILD_APP/Contents/MacOS/HabitGate" ]]; then
  "$HG_PROJECT/scripts/build.sh"
fi
if pgrep -x HabitGate >/dev/null; then
  print -u2 "Quit Habit Gate before updating the installed bundle."
  exit 1
fi
mkdir -p "$HG_SUPPORT/ChromeExtension"
chmod 700 "$HG_SUPPORT"
ditto "$HG_BUILD_APP" "$HG_DEST"
ditto "$HG_PROJECT/extension" "$HG_SUPPORT/ChromeExtension"
python3 - "$HG_DEST" <<'PY'
import json,pathlib,sys
app=pathlib.Path(sys.argv[1])
identity=(app/'Contents/Resources/extension-id.txt').read_text().strip()
directory=pathlib.Path.home()/'Library/Application Support/Google/Chrome/NativeMessagingHosts'
directory.mkdir(parents=True,exist_ok=True)
manifest={'name':'me.habitgate.bridge','description':'Habit Gate read-only browser bridge',
 'path':str(app/'Contents/MacOS/HabitGateBridge'),'type':'stdio',
 'allowed_origins':['chrome-extension://'+identity+'/']}
path=directory/'me.habitgate.bridge.json'
path.write_text(json.dumps(manifest,indent=2)+'\n');path.chmod(0o600)
print('Native messaging host registered.')
PY
HG_REGISTER='/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister'
if [[ -x "$HG_REGISTER" ]]; then
  "$HG_REGISTER" -u "$HG_BUILD_APP" >/dev/null 2>&1 || true
  "$HG_REGISTER" -f "$HG_DEST" >/dev/null 2>&1 || print -u2 'macOS app registration could not be refreshed automatically.'
fi
print "Installed: $HG_DEST"
print "Load unpacked Chrome extension from: $HG_SUPPORT/ChromeExtension"
