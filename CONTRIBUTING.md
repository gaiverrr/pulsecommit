# Contributing to Pulse Commit

Pull requests are welcome. Good first areas: new Health categories, export format improvements, Telegram report details, bug fixes and tests.

## Before you start

- For anything larger than a bug fix, open a feature request issue first so we can agree on scope. New destinations, backends or dependencies need that discussion before code.
- Read [AGENTS.md](AGENTS.md): architecture, design tokens, conventions and known HealthKit/GitHub/Telegram pitfalls.

## Build and test

Requirements: Xcode 27 or later, [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
xcodegen generate
swift test --package-path Packages/HealthCore
xcodebuild test -project PulseCommit.xcodeproj -scheme PulseCommit \
  -destination 'platform=iOS Simulator,name=<any installed iPhone simulator>' \
  -skip-testing:PulseCommitTests/ArchiveVerificationTests
```

`ArchiveVerificationTests` need a separately built Release archive and are skipped in CI.

Never edit the generated `.xcodeproj`; change `project.yml` and regenerate. To run on your own device, set your team and a Debug bundle id suffix locally and keep those changes out of your PR.

## Ground rules

- **Privacy is load-bearing.** No analytics, crash reporters, ad SDKs or new outbound hosts. Production code may only contact `api.github.com`, the GitHub Device Flow endpoints on `github.com`, `api.telegram.org`, and the HTTPS webhook URL the user enters. Never a server of ours.
- **No new third-party dependencies** beyond ZIPFoundation without prior agreement.
- **Health data is read-only.** No HealthKit write access.
- **JSON schema changes are additive.** Every emitted JSON file carries `"schema_version": "1.0"`.
- **Tests first** for behavior changes. Pure logic belongs in `Packages/HealthCore` with tests there.
- **Copy follows the tone rule:** numbers over adjectives; `scripts/verify-tone.sh` must pass.
- Keep PRs focused: one change per PR, with a description of what changed and how you tested it. UI changes need a simulator screenshot.

## License

By submitting a pull request you agree that your contribution is licensed under the [MIT License](LICENSE).
