---
name: phone
description: Use when installing Metra on the user's Android phone, checking something on it (screenshots, files, versions), launching or tapping the app over adb, or when an install fails.
---

# Working with the phone (adb)

`adb` is `~/Library/Android/sdk/platform-tools/adb` (not on the PATH). The phone is usually connected over wireless debugging; check with `adb devices`. If nothing is listed, ask the user to turn on wireless debugging (or plug in USB).

**Install**
- Debug app (`com.dror.metra.debug`, "Metra dev", installs beside the real app): `flutter build apk --debug`, then `adb install -r build/app/outputs/flutter-apk/app-debug.apk`.
- Always `adb install -r` (keeps data). Never `flutter install` and never uninstall: both wipe the user's songs.
- Confirm: `adb shell dumpsys package com.dror.metra.debug | grep versionCode`.
- `INSTALL_FAILED_UPDATE_INCOMPATIBLE` (signatures don't match) on `com.dror.metra`: that copy came from Play (`installerPackageName=com.android.vending`, signed by Google). It can only be updated through Play; don't uninstall it.

**Before a risky install** (data format changes): copy the debug app's data off first (debug builds allow `run-as`):
`adb exec-out run-as com.dror.metra.debug cat files/library.json > <scratchpad>/library_before.json` (also `files/settings.json`). `adb shell run-as com.dror.metra.debug ls -la files/` lists what's there. Keep these copies out of the repo (they're the user's data).

**The user uses the phone while you test.** Before every tap, swipe, key event or text input, check the foreground app:
`adb shell dumpsys window | grep mCurrentFocus` must show `com.dror.metra` (the debug app is `com.dror.metra.debug`). If it shows anything else (another app, the notification shade, a dialog from the system), stop: don't act, and tell the user what's in front. Launching (`am start`) takes the screen too: check first, and if another app is in front, ask instead. Check again before each action, not once per sequence; a burst of screenshots needs no check (it reads, it doesn't touch). Tell the user before you start driving the phone.

**Look at it**
- Launch: `adb shell am start -n com.dror.metra.debug/com.dror.metra.MainActivity` (not `monkey`, which can inject random events).
- Screenshot: `adb exec-out screencap -p > <scratchpad>/s.png`, then shrink before reading it: `sips -Z 900 s.png --out s_small.png` (or crop a region: `sips -c <h> <w> --cropOffset <y> <x> in.png --out out.png`).
- Tap: `adb shell input tap <x> <y>` in physical pixels (`adb shell wm size`; the screenshot's pixels). Back: `adb shell input keyevent KEYCODE_BACK`.
- Wait ~1.5 s after a tap before a screenshot; panel motion may still be running.

The user may be holding the phone: one odd screenshot can be their touch. Reproduce before calling it a bug.
