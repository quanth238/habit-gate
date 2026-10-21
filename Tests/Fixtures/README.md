# Native allowance integration fixture

These sources are outside the SwiftPM unit-test targets. `ForegroundFixture.swift` creates an empty window. Bundle its executable as a macOS app with bundle identifier `me.habitgate.testfixture`; it contains no user data.

Compile `DailyAccessIntegration.swift` with `Sources/HabitGate/AppBlocker.swift`, `Sources/HabitGate/DailyAccessController.swift`, the release `GateCore.o` and the release module include path. Bundle the harness separately so UserNotifications can read its bundle identity. No API key or Habitify account is used.

Open the disposable fixture app first, then open the harness. It exercises five seconds of remaining daily allowance without requiring any foreground events. It verifies that the app was visible during access, receives exactly one real hide call, stays running after exhaustion and gains no renewed grant on repeated refreshes. The harness never terminates the fixture process; close or quit that disposable app after inspection. It writes `habit-gate-countdown-integration.json` in the macOS temporary directory, or accepts an absolute output JSON path as its first command-line argument.

Current recorded result: `validation/continuous-access-1.5.2.json`. Earlier foreground behavior: `validation/daily-access-native-integration.json`.
