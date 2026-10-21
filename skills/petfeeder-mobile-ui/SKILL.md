---
name: petfeeder-mobile-ui
description: Refine or extend the PetFeeder Flutter mobile interface with its shared visual system, Vietnamese copy, simple controls, and reliable connected-device states. Use for PetFeeder mobile screens and widgets, not firmware or backend features.
---

# PetFeeder mobile UI

Apply this skill to `petfeeder_app/` in the PetFeeder repository. Locate the repository in the current workspace; do not assume a machine-specific checkout path. Read `lib/theme/app_theme.dart`, `lib/widgets/app_components.dart`, and the affected screens before changing UI.

## Visual direction

PetFeeder should feel like a calm pet-care companion. Use a warm cream canvas, white cards, forest green actions, and a compact dark green hopper metric card. Keep warm amber for attention and muted red for failures. The maintained color values are in `AppTheme`; update tokens there instead of introducing competing screen palettes.

- Reuse `PageContent`, `PageHeading`, `SectionCard`, `StatusPill`, `EmptyState`, and `PortionSelector` where appropriate. Add shared components when screens need the same behavior.
- Keep content at a maximum width of 680 logical pixels, with approximately 20-pixel page gutters. Allow vertical scrolling at every supported text scale.
- Use 26–28-pixel card corners, pill-shaped buttons and chips (`StadiumBorder`), circular icon buttons, 22-pixel input corners, and an 8-pixel spacing rhythm. Primary actions are at least 56 pixels tall. Selected chips use green fill and white text; day chips retain checkmarks. Portion chips omit checkmarks to keep their width stable and preserve selected semantics. Keep sliders visually clean without tick marks. Use clear hierarchy rather than heavy borders or decorative shadows.
- Use 27-pixel page headings, 18-pixel section headings, readable body copy, and large key measurements. Prefer task-specific page titles over slogans. Do not shrink text to hide overflow.
- Keep the dashboard compact: a short connection strip, adjacent hopper/bowl metrics when the available width and text scale allow, then the feeding controls. Stack metrics on narrow layouts or enlarged text. The feed action and both measurements should be visible without scrolling on a 390 × 844 logical-pixel viewport at default text scale. Avoid restoring a tall promotional hero above the main action.
- Keep the single brand app bar and four labeled Material navigation destinations in a bar with rounded top corners. Avoid nested app bars. Preserve visited screen state when switching tabs. Give the schedule sheet a visible circular close button as well as platform dismissal.

## Interaction and content

Write concise Vietnamese with diacritics. Prioritize what a pet owner needs to know: connection, remaining food, bowl weight, portion, next action, and feeding outcome. Keep grams and times explicit. Put hardware details and emulator addresses inside expandable settings rather than the main care flow.

- Give each task one clear primary action: `Cho ăn · 30 g`, `Thêm lịch ăn`, `Lưu lịch ăn`, or `Lưu kết nối`. Use sentence case; avoid long uppercase labels.
- Keep interactive targets at least 48 logical pixels. Give icon-only actions meaningful tooltips and controls accessible names.
- Wrap badges, day selectors, and portion presets on narrow widths. Use flexible columns for long text. Account for safe areas and keyboard insets in the schedule sheet.
- Disable repeated submissions while requests are pending. Show progress and restore controls after success or failure. Do not automatically retry feeding or destructive requests.
- Keep loading, unavailable, error/retry, and genuinely empty states distinct. Missing telemetry must display an unknown value, not a misleading zero or empty-food warning. Do not claim the device is healthy merely because no alerts were returned.
- Gate remote feeding on current online status. Preserve the mandatory cooldown and all safety checks (36 cases C03/C05); do not offer an override. Explicit retries resend the saved command ID and original payload.
- Confirm deletion of schedules and feeding history. Check API results before removing rows locally. Show understandable failures without raw exception dumps.
- Validate server URLs and test a candidate before changing the shared API address. Persist the validated address and pending feed payload with SharedPreferences; a failed candidate must leave the saved address intact.
- Preserve backend contracts, portion limits, timestamps, and existing capabilities unless the user requests a behavior change. Check actual device status strings in firmware/backend before translating them into labels; retain a readable fallback for unknown statuses.
- When asked for visual optimization without functional changes, confine edits to layout, typography, spacing, colors and presentation. Preserve action handlers, validation, request payloads, refresh logic, dialogs and control ranges; compare them with the pre-edit version and run existing regression tests.
- Guard UI updates after asynchronous work with `mounted`; dispose controllers. Bound API waits so a loading button cannot stay stuck indefinitely.

## Verification

Run `dart format lib test`, `flutter analyze`, and `flutter test` from `petfeeder_app/`. Use the locally installed SDK and existing dependencies. Do not upgrade dependencies just to restyle the app; SDK-required lockfile updates should be explained.

Use `test/mobile_ui_test.dart` for layout and interaction regression coverage. Exercise all four tabs at phone and tablet widths and enlarged text, long schedule names/messages, empty/error states, sheet keyboard insets, pending actions, and duplicate-feed handling when affected. Mock network calls; never trigger a real feeder during UI tests.

For visual review, the test supports `PETFEEDER_PREVIEW_DIR` and optional `PETFEEDER_PREVIEW_FONT` environment variables. Set the font to a locally available Roboto TTF when capturing previews. Inspect the rendered PNGs before reporting the result. Fixture previews demonstrate layout and do not establish real hardware connectivity.
