# Hero video

A 10-second, 60 fps looping animation for the pulsecommit.app hero. Everything is generated: simulator screenshots of the real app plus a Remotion composition. Nobody edits video by hand.

## One command

```bash
cd marketing/video && npm ci && cd ../..
scripts/make-hero-video.sh
```

The script:

1. Takes the shared `/tmp/pulsecommit-xcodebuild.lock`, runs `xcodegen generate`, boots the `iPhone 18 Pro` iOS 27.0 simulator (override with `SIM_NAME` / `SIM_OS`) and pins the status bar to 9:41.
2. Runs the `PulseCommitMarketing` scheme. `HeroCaptureUITests` launches the Debug app with `-marketingDemo -onboarding_completed YES`, taps Export, opens History and saves six full-resolution screenshots as XCTest attachments.
3. Exports them from the `.xcresult` with `xcrun xcresulttool export attachments` into `public/screens/`. These are generated, so they are not committed.
4. Runs `npm run render`, which type-checks, renders `HeroLoop` (1080x1920) and `HeroLoopWide` (1440x1080) with Remotion, then encodes with ffmpeg. The CRF starts at 23 for H.264 and 34 for VP9 and goes up until each file is at most 1.5 MB (`HERO_MAX_BYTES`).

To re-render from existing screens without Xcode: `scripts/make-hero-video.sh --skip-capture`. To preview interactively: `npm run studio`.

## Outputs (`out/`, not committed)

| File | Size | Notes |
| --- | --- | --- |
| `hero.mp4` | 1080x1920 | H.264, yuv420p, faststart, no audio |
| `hero.webm` | 1080x1920 | VP9 |
| `hero-poster.jpg` | 1080x1920 | frame 0, same as the last frame |
| `hero-wide.mp4`, `hero-wide.webm`, `hero-wide-poster.jpg` | 1440x1080 | landscape version |
| `hero-strip.jpg`, `hero-wide-strip.jpg` | | one frame per second |

`preview/` holds a committed copy of the frame strips. The script refreshes it on every render.

## App Store screenshots

```bash
cd marketing/video && npm ci && cd ../..
scripts/make-store-screenshots.sh
```

1. Takes the same lock, boots the `iPhone 18 Pro Max` iOS 27.0 simulator (6.9-inch, 1320x2868 screenshots; override with `SIM_NAME` / `SIM_OS`) and pins the status bar to 9:41.
2. Runs only `StoreCaptureUITests` from the `PulseCommitMarketing` scheme. With `-marketingDemo` it captures Home, History, Destinations, the Webhook screen (endpoint, masked token, payload) and Automate into `public/store/` (not committed).
3. Runs `npm run render:store`. The `StoreShot` still frames each capture in a phone with its kicker and caption at 1320x2868, converts it to RGB PNG without alpha and writes `marketing/screenshots/out/01-telegram.png` to `06-automate.png` (not committed). Screenshot 1 is the React Telegram scene from the hero video, so it is illustrative, not a capture.
4. Writes the committed `marketing/screenshots/preview/contact-sheet.jpg` (under 400 KB) and fails if any PNG is not 1320x2868 or has alpha.

Captions and kickers live in `src/store.ts` and are covered by `npm test`. `--skip-capture` re-renders from existing captures.

## Demo data

`-marketingDemo` is read only in Debug builds (`PulseCommit/Marketing/MarketingDemo.swift` is wrapped in `#if DEBUG`, and so is the seam in `AppContainer.shared`). It builds an in-memory container with no Keychain, HealthKit or network access: six fake categories, three stub sinks (GitHub, Telegram and a webhook at the synthetic host `agent.example.net`) that sleep and return fixed references, seeded History rows (the three most recent include the webhook) and a throwaway `UserDefaults` suite. The Telegram scene is drawn in React and uses the same numbers (12 483 steps, 642 kcal, 7h 31m sleep, HRV 47 ms).

## Storyboard

| Frames | Scene |
| --- | --- |
| 0-54 | Home, idle |
| 54-72 | Tap ripple and button press |
| 72-250 | Running: three captured stages, progress bar fill |
| 250-330 | Done, recent commits stagger in, tap History |
| 330-404 | History rows stagger in |
| 404-562 | Telegram: summary with counting numbers and ZIP, typing indicator, agent reply |
| 562-600 | Slide back to Home; frame 599 matches frame 0 |

Frame ranges live in `src/timeline.ts` and are covered by `npm test`. Screen coordinates for overlays are in `src/layout.ts` and assume a 1206x2622 capture (iPhone 18 Pro). With another simulator, update that file.

## Licence

Remotion is source-available, not open source. Its licence (`node_modules/remotion/LICENSE.md`) grants the Free License to "an individual" and "a for-profit organization with up to 3 employees", and allows commercial use "for the purpose of creating videos and images". Pulse Commit is built by one individual developer, so the Free License applies. A Company License from remotion.pro is required if the project is ever owned by an organization with more than 3 employees.

Fonts: Inter and JetBrains Mono through `@fontsource` (SIL Open Font License), bundled from npm so the render does not depend on installed or network fonts.
