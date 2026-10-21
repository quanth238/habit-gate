# Saved interface size — 1.5.5

Settings → Interface size contains three native segmented options: Compact 90%, Standard 100% (default), and Large 110%. The lock label communicates that the selected scale stays fixed across displays; choosing another preset changes it immediately. There is no extra Save or Lock step. Selection persists across restarts independently of protection policy and the daily balance.

The main window uses a compensated layout transform, preserving scroll bounds, button hit testing and the footer. AppKit owns window sizing; the hosting view does not resize the window through intrinsic content size. Minimum sizes grow with the preset and respect available screen space. First presentation resolves the window’s current display before fitting its size. The existing centered timer composition and bounded form width remain responsive within that scale.

## Visual evidence

These are isolated previews using no API credential and an illustrative 15-minute balance. They do not show the user's actual remaining allowance.

- [Large at its minimum frame, dark](large-minimum.jpg)
- [Compact Settings, dark](compact-settings.jpg)
- [Standard countdown, 1920 × 1200 external full screen](standard-external-fullscreen.jpg)
- [Large Settings, external full screen](large-external-settings.jpg)
- [Large countdown, built-in Retina display, light](large-retina-light.jpg)

The built-in check uses a 1100 × 800-point window with 2× backing resolution. The external full-screen check uses the PA248QV at 1920 × 1200 with 1× backing resolution. Large remained selected after restarting the isolated preview on the Retina display. All preset controls were exercised, the Settings page remained selected during size changes, and minimum-frame timer controls were visually inspected. This is not a complete VoiceOver audit.

## Scope and rollback

The menu-bar panel and blocked-app dialog keep their existing sizes. Protection, daily timing, permanent app selection, Habitify and Chrome 1.1.1 code are unchanged. The original installed 1.5.4 app and private settings were backed up outside the repository. Restoring that app ignores the new appearance preference and retains the existing daily ledger. Validation is recorded in [interface-size-1.5.5.json](../../validation/interface-size-1.5.5.json).
