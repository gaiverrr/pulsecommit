# App Store screenshots — capture plan

Status: **all final App Store screenshots are pending capture from the release candidate**. This plan does not claim that an image exists, that a flow was exercised, or that an external destination worked.

Apple accepts one to 10 screenshots per device-size group in JPEG or PNG, without alpha or transparency. For this iPhone-only app, provide the highest-resolution 6.9-inch set first. Apple says the 6.5-inch set is required only when 6.9-inch screenshots are not provided; do not maintain two mandatory sets.

Primary reference: [Apple — Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications).

## 1.0.2 six-image set (automated)

`scripts/make-store-screenshots.sh` builds the whole set from a clean checkout after `cd marketing/video && npm ci`. Nobody edits images by hand. See `marketing/video/README.md` for the steps. Output: `marketing/screenshots/out/*.png` (not committed), 1320 × 2868, RGB without alpha, plus the committed `marketing/screenshots/preview/contact-sheet.jpg`.

| File | Kicker | Caption | Screen |
| --- | --- | --- | --- |
| `01-telegram.png` | `> telegram` | Apple Health, every evening, to your AI agent | Telegram chat drawn in React (illustrative, not a capture) |
| `02-webhook.png` | `$ pulse remote add webhook` | POST to any endpoint you own | Webhook screen: endpoint, masked token, payload |
| `03-history.png` | `$ git log --oneline` | One commit per day, in your own repo | History |
| `04-home.png` | `$ pulse commit --since=today` | Export now, or let Shortcuts run it | Home, Export Now |
| `05-destinations.png` | `$ pulse remote -v` | Telegram, GitHub and your webhook | Destinations, three configured |
| `06-automate.png` | `$ shortcuts run "Export Health Data"` | Today at 21:00 or yesterday at 08:30 | Automate |

Captions 1-3 come from the 1.0.2 design canvas. Captions 4-6 and all kickers were written for this set. App screens 2-6 are captured from the Debug app with the `-marketingDemo` seam: synthetic data, the synthetic host `agent.example.net` and a fake token. They are screenshot preparation, not evidence of live delivery or a real Health export.

## Capture target

- Preferred group: iPhone 6.9-inch display.
- Capture simulator for the automated set: iPhone 18 Pro Max on iOS 27.0, which produces `1320 × 2868` captures.
- Expected portrait size for the framed output: `1320 × 2868` pixels. Apple also accepts other listed 6.9-inch sizes, so validate the produced file against the current Apple table rather than resizing blindly.
- Format: PNG or JPEG, no alpha channel or transparency.
- Orientation: portrait for this planned set.

## Candidate-state rules

- Capture a reviewed candidate build and record its build number and Git revision with the screenshot evidence. Physical-phone rehearsal remains a separate pre-release gate.
- Use a review-only Telegram destination provided outside Git if live setup is part of the capture session. The Telegram sample-message action is not a Health export.
- GitHub imagery is optional. If live setup is shown, authenticate with the app's real OAuth Device Flow and a review repository with the GitHub App installed. There is no PAT field in the app.
- Controlled demo Health/History state may be used for screenshot composition through existing supported test/debug seams. Record it as synthetic screenshot data and never cite it as live delivery or device evidence. This documentation slice adds no screenshot-only app mode or packaged fixture.
- If a device has no visible samples, capture an honest empty state or wait for the prepared review device. HealthKit may return the same empty result for a quiet period, denied read access, or access limited to recent history.
- 1.0 is free and has no paywall. No image may show a price, trial counter, or Pro label.
- Keep secrets out of images. Confirm the bot token, any account identity, repository visibility, notification banners, and personal Health values are appropriate for publication.

## Capture procedure

1. Freeze the candidate revision and confirm `project.yml` still targets iPhone / iOS 17.0 or later.
2. Run `xcodegen generate` if `PulseCommit.xcodeproj` is missing or `project.yml` changed.
3. Choose one available iPhone 17 Pro Max simulator and record its UDID, for example the installed iOS 26.4 device `69CC9863-12D9-4DD8-A15A-1E7C5CF0A237`. Re-resolve the UDID with `xcrun simctl list devices available` if simulators change, then run `xcrun simctl boot <UDID>`.
4. Build and install the candidate for that exact UDID.
5. Navigate through the real UI. Keep controlled screenshot state, live service checks, and physical-device evidence labeled separately.
6. Stabilize the status bar if desired, then capture each selected screen:

   ```sh
   xcrun simctl io <UDID> screenshot --type=png screenshots/01-home-setup.png
   ```

7. Verify each file before upload:

   ```sh
   sips -g pixelWidth -g pixelHeight -g hasAlpha screenshots/01-home-setup.png
   ```

   The chosen 6.9-inch file must match one of Apple's accepted dimensions and report no alpha.

8. Inspect every image at full size for clipped text, personal data, secrets, stale UI, false success states, and mismatched price. Record failures as pending; do not mark them passed from this plan.
9. Upload the ordered 6.9-inch set to its matching App Store Connect group. Add a 6.5-inch set only if the 6.9-inch set is unavailable or App Store Connect explicitly requires it for the candidate.

## Pending evidence

- [ ] Final release-candidate revision and build number
- [ ] Manual phone/review rehearsal completed
- [ ] One to 10 final images captured from reachable UI
- [ ] Pixel dimensions and alpha checked for every image
- [ ] Public-safety review for Health data, credentials, identities, and notifications
- [ ] No image shows a price, trial counter, or Pro label
- [ ] Uploaded screenshot group re-opened and visually checked in App Store Connect
