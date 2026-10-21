# Native allowance integration fixture

These sources are outside the SwiftPM unit-test targets. `ForegroundFixture.swift` creates an empty window. Bundle its executable as a macOS app with bundle identifier `me.habitgate.testfixture`; it contains no user data.

Compile `DailyAccessIntegration.swift` with `Sources/HabitGate/AppBlocker.swift`, `Sources/HabitGate/DailyAccessController.swift`, the release `GateCore.o` and the release module include path. Bundle the harness separately so UserNotifications can read its bundle identity. No API key or Habitify account is used.

Open the disposable fixture app first. Run the harness executable with an absolute output JSON path and `--simulated-foreground` to exercise five seconds of remaining daily allowance without changing desktop focus. It verifies that the app was visible during access, receives exactly one real hide call, stays running after exhaustion and gains no renewed grant on repeated refreshes. The simulated signal isolates OS window hiding; unit tests cover actual event ordering and foreground accounting separately. Without that flag, keep the fixture foreground for five seconds. The harness never terminates the fixture process; close or quit that disposable app after inspection.

Recorded result: `validation/daily-access-native-integration.json`.
