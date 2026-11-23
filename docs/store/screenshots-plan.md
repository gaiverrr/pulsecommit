# App Store screenshots — capture plan

Status: **all final App Store screenshots are pending capture from the release candidate**. This plan does not claim that an image exists, that a flow was exercised, or that an external destination worked.

Apple accepts one to 10 screenshots per device-size group in JPEG or PNG, without alpha or transparency. For this iPhone-only app, provide the highest-resolution 6.9-inch set first. Apple says the 6.5-inch set is required only when 6.9-inch screenshots are not provided; do not maintain two mandatory sets.

Primary reference: [Apple — Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications).

## Proposed six-image story

These labels describe capture intent and filenames. App Store Connect has no per-screenshot Caption field. Do not paste these labels into nonexistent metadata fields.

1. `01-home-setup.png` — first-export Home state showing Health permissions and Telegram recommended / GitHub optional.
2. `02-telegram-setup.png` — Telegram setup with the visible target and sample message in Test Delivery; the bot token must remain masked.
3. `03-export-consent.png` — destination-specific Health export disclosure with target, categories, formats, readers, retention, and deletion limits visible.
4. `04-home-ready.png` — configured Home screen with the current Export Now action and period selector.
5. `05-history.png` — History rendered through the actual candidate UI with clearly controlled demo data; keep live destination verification as separate evidence.
6. `06-automate.png` — Automate with its Today / Yesterday distinction and locked-phone warning.

The final set may contain one to 10 images. Keep only screens captured from reachable release-candidate UI. Controlled demo data is acceptable when it is rendered through the real app and recorded as screenshot preparation; it is not proof of live destination delivery or a real Health export.

## Capture target

- Preferred group: iPhone 6.9-inch display.
- Available capture simulator verified 2026-09-23: iPhone 17 Pro Max on iOS 26.4 or 26.5. There is no iPhone 17 Pro Max device in the installed iOS 27.0 runtime.
- Expected portrait size for that simulator: `1320 × 2868` pixels. Apple also accepts other listed 6.9-inch sizes, so validate the produced file against the current Apple table rather than resizing blindly.
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
