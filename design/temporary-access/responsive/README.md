# Balanced window and full-screen layout — 1.5.4

The timer, primary action, caption, app icons and reset/coverage line form one centered group. They share a vertical axis in the main content area, with balanced free space above and below. The clock adapts between 220 and 340 points; full screen does not stretch it beyond that limit. App icons are centered rather than left-aligned across a long strip. The action uses a readable 14-point label in the main page.

The Temporary access page uses the available content width. Its full-screen button and Control-Command-F call the owning window through the app delegate. The native green button also supports full screen and tiling. The main window remembers its frame; its first opening fills the current screen's visible area. Launch at login remains quiet in the menu bar.

- [Installed full-screen app](installed-fullscreen.jpg)
- [Minimum window — isolated preview](preview-minimum.jpg)
- [Light appearance — isolated preview](preview-light.jpg)
- [Active state — isolated preview](preview-active.jpg)
- [One-minute warning — isolated preview](preview-warning.jpg)
- [Large window — isolated preview](preview-large.jpg)

Preview windows use isolated storage and no Habitify credential. Their balances are illustrative. Only installed screenshots show the user's real app. The generated concept and prompt remain in [the prior design folder](../refined/README.md); version 1.5.4 corrects window sizing and alignment in native code.

Daily counting, app enforcement, permanent policy and browser behavior are unchanged. See [the flow specification](../../../docs/DAILY-ACCESS.md) and [validation](../../../validation/responsive-access-1.5.4.json).
