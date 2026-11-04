#!/usr/bin/env bash
# Installs the APK, opens each screen (labelled demo data), captures screenshots and fails on any crash.
set -u
APK="$1"; OUT="$2"; PKG=com.vainraich.finance
mkdir -p "$OUT"
adb install -r "$APK"
adb shell settings put system system_locales he-IL || true
# The emulator's own launcher sometimes ANRs on slow CI machines; hide system error dialogs so they do not cover the app.
adb shell settings put global hide_error_dialogs 1 || true
adb shell am broadcast -a android.intent.action.CLOSE_SYSTEM_DIALOGS > /dev/null || true
adb logcat -c
shot() { adb exec-out screencap -p > "$OUT/$1.png"; }
# -S force-stops first so every launch is a cold start that reads the extras (otherwise the task is only brought to front).
start() { adb shell am broadcast -a android.intent.action.CLOSE_SYSTEM_DIALOGS > /dev/null 2>&1 || true; adb shell am start -S -W -n $PKG/.MainActivity "$@" > /dev/null; sleep 4; }

start; sleep 2; shot 00-onboarding
for s in home calendar transactions debts more accounts reports settings ai import forecast review newExpense newEvent chat; do
  start --ez uiDemo true --es startScreen "$s"
  shot "$s"
done
adb shell cmd uimode night yes; sleep 1
start --ez uiDemo true --es startScreen home; shot home-dark
start --ez uiDemo true --es startScreen calendar; shot calendar-dark
adb shell cmd uimode night no

adb logcat -d > "$OUT/logcat.txt"
if grep -E "FATAL EXCEPTION|AndroidRuntime: .*Exception" "$OUT/logcat.txt" | grep -q .; then
  echo "App crashed:"; grep -A 30 "FATAL EXCEPTION" "$OUT/logcat.txt" | head -80
  exit 1
fi
echo "No crashes."
