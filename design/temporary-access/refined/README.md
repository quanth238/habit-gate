# Refined temporary access — 1.5.3

The design was generated with the built-in imagegen tool, then implemented using native SwiftUI text, shapes and existing app icons. The generated image is a design reference with illustrative data. The app renders its actual balance; no generated bitmap is loaded by the interface.

- [Generated concept](imagegen-concept.png)
- [Exact generation prompt](imagegen-prompt.txt)
- [Installed app](installed-ready.png)
- [Dark ready state, 880 × 680](preview-dark-880x680.png)
- [Light ready state, 880 × 680](preview-light-880x680.png)
- [Running countdown](preview-active-880x680.png)
- [One-minute warning](preview-warning-880x680.png)
- [Exhausted allowance](preview-exhausted-880x680.png)

The open canvas, thin dial, tabular digits and compact action replace the large enclosing card and full-width button. The daily limit appears once in the header. App icons, reset time and website coverage form a separate strip. Flexible vertical space balances the timer and strip in taller windows, while minimum-size layouts retain all essential controls without scrolling. State text accompanies the colors, app icons expose accessible names, and the settings gear has a text accessibility label and tooltip.

Daily accounting, Start/End behavior, stored settings, Habitify verification, Chrome 1.1.1 and permanent app coverage are unchanged. No new background timer, network request, per-second storage write or process scan was introduced. The clock's existing visible one-second schedule remains active only while counting.

The small previews use isolated state and a vault that returns no credential. Their balances are illustrative and do not spend the user's time. Installed screenshots show the actual local app. See [validation evidence](../../../validation/refined-access-1.5.3.json).
