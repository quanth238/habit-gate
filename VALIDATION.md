# Validation — 18 October 2026

**Current baseline: macOS 1.4.5 (15), Chrome 1.1.1.** This file preserves chronological results; older sections are historical. Current requirement mapping and screenshots: [UI/UX implementation review](docs/UI-UX-REVIEW.md).

## Delivered

- Redesigned the Chrome blocked page and popup with a responsive two-column desktop layout, larger headline, numbered habit rows, progress ring, local shield branding, clearer habit-date/reset facts and a compact sync footer. Installed frontend files were verified byte-for-byte against the source. Browser enforcement and native policy files are unchanged.
- Version 1.1.0 (build 4) added Mac app selection and a native blocked-app notice. Its five saved apps became active at **18 October 2026 at 04:00 local time**. The later 1.2.0 checks below reflect the current seven selected essentials and five active apps.
- Includes the installed blue shield-and-check application icon, with 16–1024 px representations and `CFBundleIconFile=AppIcon`. The installed bundle's signature and native messaging checks passed after the update; the relaunched app loaded its saved Keychain connection and successfully synced with Habitify. Existing habit policy and launch-at-login setting were retained.
- Release build of the native SwiftUI menu-bar app and native messaging helper completed successfully on this M1 Pro Mac running macOS 27.0.1.
- Installed `/Applications/Habit Gate.app`, registered the owner-only Chrome native messaging manifest, and copied the unpacked extension into `~/Library/Application Support/HabitGate/ChromeExtension`.
- Verified the installed app's ad-hoc code signature and executable dependencies. The app and helper depend on system frameworks and Swift runtime libraries, with no dependency on the build directory. The version 1.1.0 app bundle is approximately 2.1 MB.
- Opened and visually inspected the real native connection screen. Native Quiet is the implemented style, with automatic system appearance.
- Generated and reviewed three illustrative concept boards using the built-in image-generation tool: Native Quiet (`native-quiet-v2.png`), Focus Dark, and Paper Study. The final Native Quiet board corrects the initial board's unrelated browser address to Facebook.

## Automated checks passed

**28 Swift tests and 8 JavaScript tests — 36 total.**

- Daily gates: complete, incomplete, partial progress, skipped, failed, unknown, undone, missing and duplicate journal entries.
- Multiple essential habits, confirmed rest days, missing/archived habits, unsupported weekly goals and bad habits.
- Midnight and the exact 03:59:59 → 04:00 boundary, expiration of offline proof, clock rollback, timezone changes, and 23/25-hour daylight-saving days.
- Daily, weekday, month-date and interval schedules; malformed schedules; domain normalization, subdomains and lookalikes.
- Atomic snapshot roundtrip, file permissions, invalid cache rejection, deferred policy edits and pending-policy rebasing after timezone changes.
- Mock API transport: GET-only requests, authentication header, paginated habit retrieval, explicit journal date, partial progress, 401/403/429/500 errors, Retry-After, sanitized error messages, malformed responses and duplicate entries.
- Mock browser adapter: native state → declarative rules, script registration at document start, replacement of installation defaults, allow/block transitions, offline proof expiry, and rejection of privileged commands from content scripts.
- Mac app policy migration and persistence, exact bundle identity, protected system/Habitify apps, deferred additions/removals, and preservation of habit/website rules.
- App guard: selected apps only, foreground notice versus quiet background hiding, verified unlock and expiry, repeated activation, terminated apps, failed hide reporting, independent per-app failures, and concurrent hide/activation races.

Additional installed-protocol checks passed: fixed extension identity, native host registration, native message framing, unauthorized-origin rejection, oversized-message rejection and no credential fields in the snapshot response. These checks run the installed helper directly; they do not establish that Chrome loaded the extension.

Reproduce with `./scripts/test.sh`. After installation, run `python3 scripts/check-install.py` for the installed protocol checks.

## Real Mac app guard check

A disposable, empty native app was used to exercise the actual macOS application events and hide API, without touching the user's five selected apps or changing any Habitify data. All five integration checks passed: launch hidden, verified proof permits the window, an undo hides the open window, trying to unhide it is intercepted, and the fixture process/session remains alive. Four foreground notices were observed with no protection errors. The verified proof in this isolated harness was synthetic; this is not a live Habitify completion/unlock test.

The first integration run found a launch race in which macOS rejected an early hide request before later hiding the window. The final guard waits for foreground activation to explain a launch and makes two bounded retries before reporting a failure. The corrected integration run and full automated suite passed.

## Measured resource use

One **60.14-second** sample, with the native setup window open and the app unconfigured:

| Measurement | Result |
|---|---:|
| Average CPU, percent of one core | 0.050% |
| Mean resident memory | 95.66 MB |
| Peak sampled resident memory | 99.94 MB |
| Samples | 58 |

This first sample covered setup only. A second 65.24-second sample taken while activating the app and interacting with settings measured 0.521% CPU, 85.99 MB mean RSS and 88.16 MB peak RSS; its CPU narrowly exceeded the idle target during interaction.

After activation, with settings closed, three populated essentials, authenticated periodic sync, and one loaded Chrome profile, a **65.32-second** idle sample measured:

| Measurement | Result |
|---|---:|
| Sampled average native CPU, percent of one core | 0.367% |
| Mean resident memory | 86.67 MB |
| Peak sampled resident memory | 87.41 MB |
| Samples | 63 |

Chrome launches the native helper only briefly. A separate real `getState` exchange measured with `/usr/bin/time -l` completed in 0.01 seconds and peaked at 10.78 MB RSS. Adding this helper peak to the sampled app peak gives 98.19 MB; this is a sum of separately measured peaks, not a continuous simultaneous measurement. The one-second profiler can miss a short-lived helper's CPU and memory. The observed app idle CPU and this memory estimate fall within the requested budgets, but these short samples do not establish a sustained combined-process guarantee. Reproduce the idle sample with `python3 scripts/profile.py --seconds 65`.

### Version 1.1.0 with Mac app support

With application event observers registered, settings closed, Habitify connected and the five Mac apps saved for the next boundary, a 65.40-second sample measured **0.596% sampled CPU**, **83.19 MB mean RSS**, and **85.46 MB peak RSS** across 63 samples. This CPU sample is above the requested 0.5% target. The helper separately peaked at **10.75 MB RSS**; adding separately measured peaks gives **96.21 MB**, subject to the same sampling limits above. Native app enforcement was exercised in the disposable integration test; the user's five-app policy was still pending during idle profiling.

Raw integration and profile results are saved in `validation/`.

A longer pre-fix sample then measured **4.628% CPU**, **92.10 MB mean RSS**, and **136.18 MB peak RSS** over 125.53 seconds. A five-second process sample showed hidden SwiftUI views doing repeated layout and live relative-time formatting. Build 4 creates the Today view only when opened, releases its hosting controller on close, releases closed settings/blocked windows, and displays a static last-successful-sync time. These changes remove UI work while no panel is open. The saved app selection and Habitify connection were verified again after installation.

After this fix, a **65.79-second** sample following opening and closing Mac app settings measured **0.289% sampled CPU**, **48.79 MB mean RSS**, and **55.69 MB peak RSS** across 63 samples. Adding the separately measured helper peak of 10.75 MB gives **66.44 MB**. These observations are within the requested idle targets, subject to the transient-helper sampling limits and the five-app policy still being pending. The real enforcement path was verified using the disposable fixture. Raw final measurements are in `validation/native-app-idle-final-65s.json`.

## Live connection and activation

- A replacement key successfully fetched the real habit catalog and dated journal, then was saved in macOS Keychain through Habit Gate's secure setup screen. Real API access and response decoding are verified.
- Activated three daily essentials: Learn 20 English words, Review English vocabulary · 15 min, and Focused study · 60 min. Each currently has `inprogress` status, so the verified state is blocked with three habits remaining. Launch at login is enabled; unlock notifications are off.
- At the live check shortly after midnight on 18 October, the active habit date was correctly 17 October, expiring at 04:00 on 18 October (Asia/Ho_Chi_Minh). No habit progress or completion was changed to test unlocking.
- Habitify's official API V2 help article confirms that API key management is mobile-only under Settings → API Credentials. The desktop UI has no such option. Habit Gate's native connection instructions and setup guide were corrected to state this explicitly and link the official instructions.
- After manual loading, one Chrome profile reported a fresh native heartbeat with website permissions granted. Direct navigation to Facebook, Instagram, X, Twitter and `m.facebook.com` redirected to Habit Gate's blocked page, confirmed by live tab URLs and titles. An unrelated HTTPS site loaded normally. Private browsing is not enabled for that profile.
- A file scan found no plaintext Habitify API key in project/runtime browser files. The replacement key was absent from the bridge's recent container logs. The installed native protocol exposes only the snapshot and connection flags.
- Automatic browser approval rejected opening `chrome://extensions` because the browser tool only permits HTTP(S) URLs. No alternate automation surface was used to bypass that rejection. Manual installation steps are in README.md and the app's Chrome & app tab.
- Safari is not packaged or installed: this Mac has no valid Apple code-signing identity and only Command Line Tools. Safari is a deferred phase requiring signing and build prerequisites.

## Remaining live checks

Real-device completion → unlock → undo → re-lock, cross-device cloud propagation, redirect chains and existing-tab enforcement, and actual sleep/wake and timezone transitions have not been exercised with live user data. Relevant policy and adapter cases pass automated tests. These live scenarios should not be claimed as verified. Safari remains deferred.

## Chrome UI redesign checks

All eight existing browser policy/adapter tests passed after the frontend update, along with JavaScript syntax validation. The UI was rendered in a local HTTP preview with mock extension messaging and the current three habit names. Verified partial progress, completed, rest-day, offline, permission-required, connection-error, long-name and light-mode variants. Continue is hidden for partial, offline and unverified states, and visible for verified-complete/rest-day fixtures. These fixture states did not modify the real Habitify journal or native snapshot.

Desktop rendering was reviewed at 1440 × 960 and narrow rendering at 390 × 844. Long habit names wrap without horizontal overflow. The matching 380 px popup measures approximately 589 px tall with three habits, fitting a 600 px popup viewport. Tab navigation moves from Open Habitify to Sync now with a visible outline; the sync button is re-enabled after its request. Test viewport overrides were reset afterward. Results are saved in `validation/blocked-page-ui-checks.json`, with rendered screenshots in `design/`.

Automatic browser approval rejected refreshing the existing Chrome extension page because only HTTP(S) protocols are allowed. No alternate browser surface was used to bypass that rejection. The user subsequently refreshed the existing tab manually and confirmed that the new design appears. No alternate automation surface was used to access the extension page.

## Existing Orange Pi bridge

The Orange Pi Habit Bridge service was recovered and the rejected Habitify key replaced through its authenticated connection API. The API verified that the new key belongs to the existing mapped account. All seven mappings remained unchanged; existing ownership/history and write settings were preserved. A backup ran before replacement.

Read-only test run 6232 examined seven mappings and 14 dates with no proposed changes. Three warnings preserve Habitify progress not owned by the bridge: research and vocabulary on 16 October, and the workout week beginning 12 October. These are intentional protections, not continuing authentication failures. No Habitify writes were performed by the manual test.

The existing bridge's 05:00 day boundary remains in place. Habit Gate uses the requested 04:00 boundary. Between 04:00 and 05:00 they intentionally refer to different habit dates; changing historical bridge reconciliation is outside this repair.

## Native redesign · version 1.2.0 (build 5)

- Generated a high-fidelity native design board with the built-in imagegen tool, then implemented its visual language in SwiftUI. The concept and exact prompt are saved in `design/native-redesign/`.
- Replaced settings tabs with a sidebar, added an overview with progress and protection status, restyled the Today popover and blocked-app notice, and separated habits, websites, connection and preferences into focused sections. Light and dark colors follow macOS. Lists scroll rather than growing past the available screen.
- Reviewed light/dark UI fixtures for seven habits, completion, rest days, offline access, missing habits, long names and setup. The fixture preview uses an in-memory substitute store: no credentials, network requests, journal writes or policy persistence. Continue appears only for verified complete/rest-day fixtures. Missing and offline fixtures remain blocked. Habit accessibility labels expose names, progress and status.
- Release build and installed signature/protocol checks passed. The 28 native tests and eight browser tests passed. Browser code, API behavior and the saved active/pending policy model are unchanged.
- Verified the installed overview, website editor, Mac app selector and preferences against real local settings. The saved configuration file hash stayed identical: seven essentials, five apps and the same five domains. Launch at login was visibly on; unlock notifications were off.
- A real attempt to bring Discord forward was intercepted and showed the redesigned native notice. Manual Sync now visibly entered the syncing state and completed successfully at **11:34 local**, with no error and access still blocked. Screenshots are in `design/native-redesign/installed-*.png`.
- Startup explicitly retains its delegate and initializes the service once. Duplicate detection ignores exited processes and returns before entering AppKit for a live duplicate.

The first warm idle sample, after visiting settings and the blocked-app screen, measured **0.333% average CPU**, **101.77 MB mean RSS**, and **115.97 MB peak RSS** over **66.02 seconds**. This met the CPU target but exceeded the original memory target. The app selector was then changed to use system symbols rather than decoding full-resolution application icons. The before-optimization report is saved under `validation/native-redesign-before-icon-optimization.json`.

The user approved the final locally signed rebuild’s access to the existing Keychain item. Live Habitify synchronization resumed without error, with a successful check at **11:46 local**. The final installed overview, lighter app selector, website settings and Preferences were inspected again; launch at login remained on. A second live Discord activation was intercepted by the final build and showed the redesigned notice. The saved configuration hash remained identical. The computer-use tool had rejected access to SecurityAgent for safety reasons, and the system authorization was completed by the user without an alternate automation surface. The earlier apparent startup stall was the synchronous Keychain read waiting for that system authorization, rather than an API failure.


After Keychain approval, a final warm idle sample of the installed build ran for **65.21 seconds** with all Habit Gate windows closed, after visiting Overview, Mac apps, Preferences, Websites and the blocked-app notice. It measured **0.107% average CPU**, **122.31 MB mean RSS** and **122.75 MB peak RSS** across 63 samples. The CPU result meets the requested idle target. The conservative resident-memory result exceeds the original 100 MB target; the system-symbol change did not bring warm RSS under that budget. The report is `validation/native-redesign-final-idle-profile.json`.

A separate macOS process sample reported an app **physical footprint of 39.4M**, with **42.6M peak**. Physical footprint and RSS are different accounting measures; neither this app-only point sample nor a separately measured helper peak establishes a continuous combined-process memory guarantee. The final resident-memory target is therefore recorded as unmet. No further rebuild was performed after the user’s Keychain approval.


## Reliability update · version 1.2.1 (build 6)

- Moved Keychain reads and saves to a dedicated actor. Startup initializes the UI, app guard, daily timer and connection monitoring before beginning credential retrieval. The UI explains pending/unavailable access and offers a retry after failure. The cached proof’s expiry and policy remain unchanged.
- Added six credential regression tests: pending authorization allows app-guard work, a cached unlock still expires while authorization waits, duplicate reads are coalesced, a late read cannot overwrite a reconnect, denied/missing access are distinguished with sanitized errors and retry, and failed replacement preserves a usable in-memory key.
- Added three coverage tests: heartbeat/file-order changes are ignored, permission/private-coverage changes remain visible, and disconnected/replaced profiles remain visible.
- **37 Swift tests and eight browser tests passed — 45 total.** The release build, installed code signature and native bridge checks passed.
- The installed app connected successfully using the existing Keychain item. Manual sync completed at **12:06 local** without error. The journal timestamp advanced from **05:05:33 UTC** to **05:06:16 UTC**, while the unchanged catalog file’s modification timestamp stayed identical. The live result is saved in `validation/reliability-live-catalog-check.json`.
- Rechecked seven selected habits, five active Mac apps, the same website domains and enabled launch at login. The saved configuration hash remained identical. A real Discord activation was intercepted by the updated app. Screenshots are in `design/reliability/`.
- Slow/denied Keychain scenarios are controlled regression tests. The final live connection completed successfully, so an extended real authorization wait was not observed during this installation.


The final 1.2.1 warm idle sample ran for **65.02 seconds**, with the same main settings sections and blocked-app notice visited before closing all panels. It recorded **0.154% average CPU**, **107.06 MB mean RSS**, and **120.83 MB peak RSS** across 63 samples. A separate app-only macOS sample reported **39.1M physical footprint**, with **42.8M peak**. Background sync subsequently completed at **12:08 local** without error. The raw reports are `validation/reliability-idle-profile.json` and `validation/reliability-final-checks.json`.

The measured CPU remains below 0.5%; resident memory remains above the original 100 MB target. The lower mean RSS versus the earlier 122.31 MB sample is an observation from a short run, not evidence of a sustained reduction under identical system conditions. The confirmed improvements are responsive startup during credential access, preserved blocking/expiry semantics, fewer redundant UI updates and avoidance of unchanged catalog writes. No new browser permissions, Habitify writes or policy changes were introduced.

## Optimization decision

The experimental 1.2.2 event-driven refactor was reverted at the user's request for simplicity. Short samples did not establish a clear practical resource benefit. The original signed **1.2.1 (build 6)** binary and sources were restored, with the exact configuration hash preserved. The restored app connected successfully to Habitify, and native Preferences confirmed launch at login remains on. All **37 native and eight browser tests** passed again; installed signature and native-protocol checks passed. Details are in `validation/optimization-rollback.json`.

## Rule timing update · version 1.3.0 (build 8)

- Changed target policy edits to be monotonic during the active day: website/app additions apply immediately; removals stay guarded until the next 4 AM boundary. Habit edits remain deferred. Mixed saves, cancelling a removal, removing a just-added target, restart and timezone rebasing use the same rule. Existing pending additions migrate without activating pending habit changes.
- Separated habit and website saves so an unsaved draft in one screen cannot be committed by the other. Buttons now say Save websites / Save apps, while Save habits for next day remains. Notices identify which changes are delayed. Only-target edits preserve a valid same-day completion proof.
- **46 native tests and eight browser tests passed — 54 total.** Eight new core timing regressions and one app-guard integration regression cover immediate additions and deferred removals. Release builds for app/helper and installed signature/native protocol checks passed. Browser files are unchanged; no extension reload is required.
- The installed migration promoted the user's pending Messenger domain into active coverage while preserving the seven active habits, eight pending habits, five app selections and original pending boundary. The native snapshot includes Messenger. Habitify synchronization succeeded without changing journal progress. The user reported approving Chrome website access, but fresh heartbeats still report missing permission. Messenger is selected in native policy; browser coverage for the expanded list remains unconfirmed.
- A live Save websites check with a changed, unsaved habit draft preserved the complete stored configuration (seven active / eight pending habits). The UI draft was restored afterward. A real foreground Discord attempt was intercepted by the installed build.
- No new resource profile was taken for 1.3.0. The preceding 1.2.1 measurements are historical and must not be relabeled as measurements of this build.

## UI/UX and reliability update · version 1.4.0 (10), Chrome 1.1.1

- Preserved the existing visual identity; separated access, Habitify verification and protection coverage. Active/scheduled essential names, exact effective times, setup drafts and review-before-activation are now explicit. Website/app additions still apply on save; removals and all habit edits wait until 4 AM, as the user specified.
- Added policy validation, owner-only last-good recovery, explicit restore and runtime corruption detection. Failed primary saves retain active in-memory rules; a separately failed backup refresh is visible. Native/helper proof checks compare current essentials and local date/offset/expiry, rejecting contradictory or stale unlocks. Controlled failure tests use isolated directories and fake credentials.
- Added Disconnect/Reconnect/confirmed API-key deletion, independent watched/verified foreground-app wording, accurate sync-request/checking/new-verification/error feedback, and safe origin-only blocked destinations with revalidated Continue.
- **61 Swift tests and 20 browser tests passed: 81 total.** Shared native/browser fixtures cover 12 proof scenarios. Release build succeeded. Installed signature, origin/framing/size checks and the key-free snapshot contract passed again on build 10. Browser assets match source byte-for-byte.
- Saved policy remained semantically identical to the preinstall backup: seven active/eight pending essentials, six domains, five Mac apps. The last-good recovery copy exists. Launch at login remained on; notifications off. Live Habitify verification succeeded at **14:30 local** with one of seven essentials complete and access locked. No journal changes were made for testing.
- Chrome initially retained an old 1.1.0 registration despite 1.1.1 installed files and repeated reported reloads. Reopening alone did not resolve the discrepancy. The user removed/reloaded the unpacked registration; the fresh report at **14:28 local** shows **1.1.1**, all six domains checked, no missing permissions and rules installed. Incognito access is off. The permission button now requests only missing explicit HTTP/HTTPS origins directly from the click and reports classified failures.
- After repair, live navigation to **www.messenger.com** redirected to Habit Gate's blocked page. The resulting target contains only the site origin. An unrelated **https://example.org/** page remained usable. These were observed through live tab metadata and the unrelated page's accessibility tree. The extension's separate in-popup test badge was not populated by this external check; its UI correctly remains “not verified in this session.”
- A scoped pattern scan of 50 app-owned source/assets/runtime files found no Habitify-key-shaped value. Keychain and Chrome profile storage were not read. No live key deletion, policy corruption, disk-full trial or synthetic real-account completion/undo was performed.
- Installed Overview, Essentials, Websites, Mac apps, Connection and Preferences were visually reviewed. Setup review/activation screenshots are explicitly illustrative in-memory fixtures. Screenshots are in `design/ux-review/`.
- **No current-build performance measurement.** Historical 1.2.1 results are not evidence that 1.4.0 meets the CPU or combined-memory targets.

Current evidence: `validation/ux-reliability-update.json`. Public release remains gated by signing/notarization and store distribution, the full live completion/undo/expiry/wake/timezone matrix, physical storage-failure trials, a complete accessibility audit and an independent onboarding pilot. The earlier 32-page engineering PDF remains a historical 1.3.0 baseline; the new UI/UX reliability addendum covers this update.

## Minimal blocked-page follow-up · 18 October 2026

- Followed the user's simpler reference: solid forest-green screen, centered shield and access message, Open Habitify, safe Back, one quote and View details. Remaining habits, verification, sync and coverage move into an optional native dialog. A concise warning remains visible on the main page when connection, sync or protection needs attention.
- Added twelve locally bundled original focus quotes with no invented attribution. Selection happens once per document; it remains unchanged through UI refreshes. No quote service, new polling timer or storage dependency was introduced.
- Main-page layout had no horizontal or vertical overflow at **1920×940, 1512×820, 1440×780, 1280×640, 1024×576, 800×500, 390×844 and 640×360** CSS-pixel viewports. These are browser viewport simulations, not a claim of testing every physical display configuration or zoom level.
- Verified complete, rest, offline, permission missing, native unavailable, long-name, missing-habit, eighteen-remaining and no-habit fixtures. Continue appeared only for valid allowed fixture states. The optional long-list dialog stayed within the viewport and scrolled internally; Escape closed it and restored focus to View details.
- All **20 browser tests** passed again, plus JavaScript syntax checks. Native code was unchanged, so the previous native test/build results remain the baseline; no native rebuild or new performance profile was taken.
- Installed `blocked.html`, `blocked.css`, `page.js` and `quotes.js` atomically per file and verified byte equality. Configuration bytes remained unchanged. Manifest/background rules and permission declarations were unchanged, so an existing blocked tab only needs Command-R.
- Screenshots and the built-in imagegen concept/prompt are in `design/minimal-blocked/`; results are in `validation/minimal-blocked-ui.json`. Screenshots show an isolated local preview using current habit names and synthetic browser messaging. The generated concept predates the follow-up quote requirement; rendered screenshots show the final UI.

## Selected Midnight Blue design · 18 October 2026

- Implemented the user's selected **03 · Midnight Blue** concept with one consistent navy/periwinkle palette across the main page and optional details dialog. The existing shield shape is rendered as a small tonal wordmark. Go back and View details share a compact utility row, and the locally selected quote is quieter plain text. No generated bitmap is loaded at runtime.
- Main page had no horizontal or vertical overflow at 1920×940, 1512×820, 1440×780, 1280×640, 1024×576, 800×500, 390×844 and 640×360 CSS-pixel viewports. Checked normal, complete, rest, permission, offline and missing-habit states. Continue remains restricted to allowed fixtures; Escape closes details and returns focus to View details.
- Checked text contrast: main 13.63:1, secondary 7.40:1, primary-button text 9.00:1, details muted text 6.11:1. These are calculated color-pair checks, not full accessibility certification.
- JavaScript syntax validation and all 20 browser tests pass. Native code, quote selection frequency, background rules, manifest, permissions and saved policy are unchanged. Installed page/style/script files match source byte-for-byte. Existing tabs need Command-R; no extension reinstall is needed.
- Current screenshots: `design/midnight-blue/`. Current evidence: `validation/midnight-blue-ui.json`. The screenshots are isolated local previews; no live Habitify completion or journal write was performed for this theme change.

## Blocked-app dialog stability · 1.4.1 (11), 20 October 2026

- Reproduced a launch/unhide/activation event burst producing four notice callbacks in the previous code. Additional controlled cases exposed duplicate hide retries, lost foreground-notice intent and obsolete verification after an unlock.
- The guard now tracks one hide request per selected app, merges foreground intent, ignores stale events for hidden apps and confirms hidden state before presenting the notice. Unlock/removal cancels pending requests; delayed callbacks cannot consume a newer operation. An already-visible notice is not repeatedly ordered forward or activated.
- The first hide request remains immediate; visibility confirmation uses the existing 150 ms delay, with the existing two bounded retries. No fast polling, new periodic timer, forced termination or policy bypass was added.
- All **65 Swift tests and 20 browser tests pass (85 total)**. The four new regressions failed against the previous implementation and pass after the fix. Existing guard assertions now wait for asynchronous hide verification where appropriate. Release build, installed signature and native-protocol checks pass.
- Installed version 1.4.1 (11) resumed real Habitify verification without another credential prompt. Configuration bytes were unchanged, Chrome reported rules ready and native Preferences confirmed launch at login remains on. A real Discord launch was intercepted; Return to work dismissed the notice normally. Live animation/focus-transition counts were not instrumented; exact one-notice callback counts come from controlled tests.
- No Habitify journal writes, saved-policy edits or current performance profile were performed. Evidence: `validation/notice-stability-update.json`. The engineering PDFs remain historical baselines.


## Zalo cold-launch correction · 1.4.2 (12), 20 October 2026

- Reproduced the reported cold-launch case with real Zalo 26.8.20, initially not running. Its first activation preceded macOS launch completion by about 0.7 seconds, followed by three further startup unhide/activation bursts. The previous visible-window guard left an existing notice behind other windows.
- Foreground intent is captured when macOS sends its notification, merged before the pending-hide visibility check, and retained until launch is ready. The launch-complete event resumes hiding; existing bounded hide verification and the five-second housekeeping interval remain in place.
- The notice disables its opening animation and floats above ordinary startup windows. Raising an existing notice does not reactivate Habit Gate. The floating notice remains in front until the user dismisses it with Return to work or the close button.
- The final installed build was tested with a real Zalo cold launch. Across the recorded startup bursts the same notice window ID and geometry were retained; Habit Gate activated once for the notice. Return to work dismissed it. Reopening the hidden Zalo showed a new notice, and another attempt with that notice already visible reused it without another Habit Gate activation. Zalo remained alive and hidden after enforcement. This verifies the notice behavior, not suppression of Zalo's own Dock animation or all startup frames.
- Both new regressions failed on 1.4.1 and pass on the correction. All **67 Swift and 20 browser tests (87 total)** pass. Release compilation and installed signature/native-host protocol checks pass. Saved configuration bytes are unchanged. Real Habitify synchronization resumed after the user approved the updated app's saved-key access in macOS.
- No Habitify journal writes or performance profile was performed. Diagnostic event metadata remains outside the public source tree. Evidence: `validation/zalo-cold-launch-update.json`. Engineering PDFs remain historical baselines.


## Installed application icons · 1.4.3 (13), 20 October 2026

- Replaced the Mac app picker's substitute SF Symbols with icons supplied by NSWorkspace for each installed bundle. Images load as rows appear. A missing app keeps a generic fallback, and the picker retains only a 60×60-pixel thumbnail per loaded row. No persistent cache, timer or background icon scan was added.
- A local smoke check resolved Discord, GeForce NOW, Telegram, WhatsApp and Zalo, confirmed 60×60 pixels and 30×30 points for all five, and checked the unavailable-app fallback. The 14,400-byte thumbnail pixel buffer excludes Cocoa object overhead, temporary rendering and system caching; no whole-process resource profile was taken.
- Release build, all **67 Swift tests**, installed code signature and native messaging protocol checks pass. The installed Mac apps screen was visually checked and shows authentic app icons. Configuration bytes remain unchanged, and live Habitify synchronization continues without an error. The Chrome extension and enforcement code were unchanged in this patch.
- Evidence: `validation/native-app-icons-update.json`. Diagnostic thumbnails and raw logs remain outside the public repository; no third-party icon assets are bundled.


## Saved API-key display · 1.4.4 (14), 20 October 2026

- The connected Connection screen now displays twelve fixed dots as the SecureField prompt. Its replacement binding remains empty, so the saved secret is not copied into editable UI state and the display cannot enable Verify & save. An empty submit returns immediately. Accessible help identifies the saved-key state.
- Release build and installed code-signature/native-host checks pass. The installed UI visibly shows the dots and a disabled Verify & save button while Habitify remains connected. No credentials were entered or changed for validation, and no new credential read was added by this display change.
- Saved configuration bytes match the pre-update backup, including the pending Zalo removal. Live Habitify sync continues without error. Native/browser unit suites were not rerun for this small display-only patch; their preceding recorded results are historical.


## Habitify catalog visibility · 1.4.5 (15), 20 October 2026

- Reproduced a successful live refresh that still displayed an archived weekly habit and an active weekly-goal habit as disabled choices. The catalog retains Habitify's archive metadata; the picker had rendered every record without excluding ineligible new choices.
- The picker now filters new choices using the existing daily-goal eligibility rules. Selected unavailable records stay visible with archive/weekly-specific explanations, and missing selected IDs keep their repair row. Full API metadata still reaches the policy engine. Saved essentials are never silently removed or counted as completed by the picker filter.
- All **70 Swift tests** pass. New coverage checks deleted IDs, current names and archive flags on successive mocked API reads, plus hidden ineligible new choices and selected unavailable habits that remain blocked even with completed journal fixtures. These fixture transitions do not modify real Habitify data.
- Release build and installed signature/native-host checks pass. A fresh installed-app sync completed successfully; the picker visibly contains the eight current daily choices and excludes the reported archived/weekly choices. Saved configuration bytes are unchanged, including the prior one-time Zalo exclusion. The complete local catalog still has ten API records, including one archived record, for policy verification.
- No Habitify writes, additional polling, new performance profile or Chrome change was introduced. Browser tests were not rerun. Evidence: `validation/habit-catalog-update.json`.

## Daily foreground app allowance · 1.5.0 (16), 21 October 2026

The installed feature uses a shared 15-minute daily balance, counts only configured Mac apps in the foreground and pauses on switching away. Settings change the next 4 AM limit without refilling today. Chrome remains 1.1.1 and receives no allowance.

86 Swift tests and 20 Chrome tests passed. The controlled macOS fixture verified visible access followed by one hide at exhaustion, no termination and no duplicate notice. Original permanent configuration, saved used time and login registration were preserved. Signature/native-host checks passed; Habitify synced after manual Keychain approval.

Minimum-window light/dark screenshots and Command-S preference saving were checked using isolated fixtures. Physical sleep/time changes were modeled. A browser URL-policy rejection prevented inspecting the new navigation's blocked-page content; fresh extension diagnostics still reported rules and permissions ready.

Final warm samples: visible window 0.933% CPU / 120.16 MB mean RSS; closed window 0.673% / 108.16 MB over approximately 65 seconds each. The original idle CPU/RSS targets are not met across those samples. Initial closed measurements were lower; different warm-up/authentication states prevent attributing the delta solely to the allowance timer.

See [the feature specification, flow, screenshots and detailed evidence](docs/DAILY-ACCESS.md), [machine-readable validation](validation/daily-access-1.5.0.json) and [rollback script](scripts/rollback-daily-access.sh).

## Manual daily access and dedicated Settings · 1.5.1 (17)

The main app now opens a large countdown with Start access / End access. Editing the daily allowance moved to the Settings tab. A manual grant uses only the remaining shared daily time, counts foreground app use, and ends on explicit End, exhaustion, a new 4 AM period or normal habit unlock. Launch restores used time with access off.

87 Swift tests and 20 Chrome tests passed. The native fixture with explicit Start verified visible access, exactly one hide at exhaustion, a preserved process and no duplicate notice. Installed UI verification confirmed Start → End → Start without refilling the balance, the settings shortcut, unchanged permanent rules and successful Habitify sync. Chrome remains 1.1.1. See [evidence](validation/manual-access-1.5.1.json) and [current screenshots/specification](docs/DAILY-ACCESS.md).

No new performance claim is made; the earlier warm 1.5.0 samples and their target misses remain recorded above.
