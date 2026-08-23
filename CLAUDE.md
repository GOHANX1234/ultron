# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Ultron-3 (Dart package name `private_agent`) is a Flutter **Android-only** app that automates the phone
by natural language. An OpenAI-compatible LLM reads a text dump of the Android accessibility tree and
returns a single next action; the native layer executes it; the loop repeats until the goal is done.

## Commands

```bash
flutter pub get
flutter analyze                       # lint (flutter_lints ^6.0.0 via analysis_options.yaml)
flutter test
flutter test test/ai_service_test.dart                       # single file
flutter test test/ai_service_test.dart --plain-name 'GLM'     # single test by name
dart run flutter_launcher_icons       # regenerate launcher icons after changing assets/app-logo.png
flutter run                           # needs a connected Android device (arm64)
flutter build apk --release --target-platform android-arm64
```

Release builds are ABI-restricted to `arm64-v8a` in `android/app/build.gradle.kts` (`abiFilters`);
`minSdk = 26`, Java/Kotlin target 17, core library desugaring on. Release signing reads
`android/key.properties` and falls back to the debug config when that file is absent.
`.github/workflows/android-release.yml` runs `flutter test` then builds the arm64 APK; it synthesizes a
keystore when `ANDROID_KEYSTORE_BASE64` is unset.

Test coverage is currently a single file (`test/ai_service_test.dart`) covering `AiService` static
helpers. There is no widget/integration test harness.

## Architecture

### The automation loop

`TaskExecutor.executeTask(goal)` (`lib/services/task_executor.dart`, the largest and most important
file) drives everything:

1. Bail out early unless `ScreenAutomationService.isServiceRunning()` — the accessibility service must
   be enabled by the user in Android settings.
2. Consult `SkillMemoryService` for a saved, reliable recording of this goal and replay it verbatim.
3. Try `_getNavigationShortcut()` — hardcoded step sequences for common goals, executed without the LLM.
4. Otherwise loop: dump the screen → `PromptBuilder.buildStepPrompt` → `AiService.sendTaskMessage` →
   `ActionParser` → `ScreenAutomationService` executes → feed the result back as
   `PREVIOUS ACTION RESULT` on the next turn. Loop guards track repeated identical actions and
   consecutive failures; `RecoveryEngine.diagnose()` proposes an alternative from screen heuristics
   (loading spinner → wait, permission dialog → click Allow, etc.).
5. Log to `TaskHistoryLogger`, notify via `NotificationService`, and save a successful run as a skill.

Step budget, temperature, max tokens, and screen compression are user settings read from
`SharedPreferences` by `AiService.init()` — not constants.

### Two prompt layers, two response shapes

- **Router** (`AiService._systemPrompt`): decides between a plain conversational reply, a one-shot
  device action (`open_app`, `make_call`, `set_alarm`, …), or `execute_task` for anything multi-step.
  `ActionHandler.execute()` is the switch that dispatches these to the per-capability services
  (`app_launcher`, `communication`, `alarm`, `system_control`, `contacts`, `shizuku`), delegating
  `execute_task` to a `TaskExecutor`.
- **Step agent** (`PromptBuilder.taskSystemPrompt`): the per-step action vocabulary
  (`click_text`, `click_at`, `type_text`, `press_enter`, `scroll`, `swipe`, `press_back`, `press_home`,
  `open_app`, `wait`, `done`) with `is_complete`.

Both expect bare JSON, and models routinely wrap it in prose or code fences — always go through
`ActionParser.extractJson` / `parseAction` (null means parse failure, caller retries) rather than
`jsonDecode` directly. Prompt text and parsing rules live only in `PromptBuilder` and `ActionParser`;
keep them there rather than reintroducing copies in `TaskExecutor`.

### Native bridge

Everything screen-related crosses one `MethodChannel`, `com.ultron.llm/accessibility`, plus an
`EventChannel` `com.ultron.llm/accessibility_events`. Dart side: `ScreenAutomationService`
(3-second timeout on every call, exceptions swallowed into `false`/empty results). Native side:
`AgentAccessibilityService.kt` implements the tree walk and gestures;
`MainActivity.registerAccessibilityChannel` is a `companion object` function so the *overlay* Flutter
engine can register the same channel. Adding a capability means editing both sides plus the `when`
branch in the Kotlin handler.

Screen dumps are rendered to text in Dart, not Kotlin: `getScreenDescription` (verbose) and
`getCompressedScreenDescription` (token-thrifty, drops status-bar noise, abbreviates class names,
marks task-keyword matches with `*`). Which one is used depends on the `api_use_screen_compression`
setting. Elements carry center coordinates so the LLM can fall back to `click_at` for unlabeled icons.

`ScreenAutomationService.logToNative()` pipes Dart logs into logcat under tag `Ultron3Dart`
(Kotlin logs under `Ultron3Kotlin`) — the practical way to debug on-device, since the automation runs
while the app is backgrounded.

### Entry points

`lib/main.dart` has two: `main()` (onboarding vs. home based on the `onboarding_completed` pref) and
`@pragma("vm:entry-point") overlayMain()` for the floating overlay's separate engine
(`lib/overlay_main.dart`). The overlay is gated off by `FeatureFlags.floatingOverlayEnabled = false`
while its implementation is stabilized; `flutter_overlay_window` is vendored in
`local_plugins/flutter_overlay_window` via `dependency_overrides`.

### Other surfaces

- **Telegram** (`telegram_service.dart`): `getUpdates` long-poll timer with backoff, feeding messages
  through the same `ActionHandler`/`AiService` path as the UI. Remote command execution.
- **Voice** (`voice_service.dart`): `speech_to_text` for input; TTS is a cloud call to a
  `stepaudio-2.5-tts` endpoint. Output is spoken via a sentence-streaming queue — LLM text is split on
  sentence boundaries as it streams and each fragment is pre-fetched and played in order, so audio
  starts before generation finishes. Per-sentence 35s safety timeout; changing session IDs cancels
  stale audio.
- **Persistence:** settings and flags in `SharedPreferences`; learned skills as JSONL at
  `skills_memory.jsonl` and chat/task history in the app documents directory.
- **UI:** `home_screen.dart` toggles a `_mode` string between `'chat'` (conversational only, no tools)
  and `'agent'` (tool-calling). Styling is a hand-rolled "liquid glass" set in `lib/widgets/` with the
  palette in `lib/config/app_colors.dart`.

## Setup context worth knowing

The app is inert without an API key, a base URL, and a model set in Settings (defaults:
DeepSeek; presets in `lib/config/api_presets.dart` include OpenRouter and NVIDIA NIM, whose free-chat
model list is hardcoded and intersected with the live `/models` response). Enabling the accessibility
service on a sideloaded APK also requires "Allow restricted settings" in Android app info — onboarding
walks the user through this.
