#!/bin/zsh
# Restore a locally backed-up app. Personal habits, rules and Chrome stay intact.
set -eu
HG_BACKUP_APP="${1:?Pass the full path to the backed-up Habit Gate.app}"
HG_INSTALLED_APP='/Applications/Habit Gate.app'
[[ -x "$HG_BACKUP_APP/Contents/MacOS/HabitGate" ]] || { print -u2 'Backup app is missing.'; exit 1; }
codesign --verify --strict "$HG_BACKUP_APP"
# End access before restoring the earlier app, which has no allowance support.
pkill -x HabitGate || true
# Retain the daily ledger so rollback never replenishes spent time.
HG_OLD_SESSION="$HOME/Library/Application Support/HabitGate/temporary-access.json"
if [[ -f "$HG_OLD_SESSION" ]]; then
  mv "$HG_OLD_SESSION" "${HG_OLD_SESSION}.rollback-$(date +%Y%m%dT%H%M%S)"
fi
ditto "$HG_BACKUP_APP" "$HG_INSTALLED_APP"
codesign --verify --strict "$HG_INSTALLED_APP"
print 'Previous app restored. Open Habit Gate from Applications to resume ordinary protection.'
