# PulseCommit · Brand assets

Generated icon assets in `lime #A4F03A` on `black #0a0a0a`. Glyph: EKG pulse waveform terminating in a Git commit node — owns both halves of the product name.

## Files

```
brand/
├── icon.svg                 ← master vector (square — iOS uses its own squircle mask)
├── icon-round.svg           ← master vector, pre-clipped to a circle
├── icon-1024.png            ← square 1024 PNG (App Store)
├── icon-512.png             ← square 512 PNG (web, README, OG image)
├── icon-round-1024.png      ← round 1024 PNG (avatar, social, GitHub org icon)
├── icon-round-512.png       ← round 512 PNG (Telegram bot avatar, Twitter, etc.)
└── AppIcon.appiconset/
    ├── Contents.json        ← Xcode asset catalog manifest
    ├── icon-1024.png        ← App Store marketing
    ├── icon-20-2x.png       ← Notifications · iPhone @2x  (40pt)
    ├── icon-20-3x.png       ← Notifications · iPhone @3x  (60pt)
    ├── icon-29-2x.png       ← Settings · iPhone @2x       (58pt)
    ├── icon-29-3x.png       ← Settings · iPhone @3x       (87pt)
    ├── icon-40-2x.png       ← Spotlight · iPhone @2x      (80pt)
    ├── icon-60-2x.png       ← App icon · iPhone @2x       (120pt)
    └── icon-60-3x.png       ← App icon · iPhone @3x       (180pt)
```

## Adding to Xcode

1. In Xcode, open `Assets.xcassets`.
2. Drag the entire `AppIcon.appiconset` folder into the assets catalog (or replace the existing `AppIcon` entry).
3. Xcode will pick up `Contents.json` automatically.

Modern Xcode (14+) also accepts a single 1024×1024 PNG — if you prefer the simplified setup, just drag `icon-1024.png` onto the AppIcon slot and delete the legacy sizes.

## Where to use the round variant

- Telegram bot profile picture (`@BotFather` → Set Bot Pic)
- GitHub organisation / personal avatar
- Twitter / X profile
- Anywhere your icon will appear inside a circle mask

## Regenerating

The master is `brand/icon.svg`. Edit the SVG, then re-export the PNG sizes with any rasterizer (e.g. `rsvg-convert -w 1024 icon.svg > icon-1024.png`).

## Brand color contract

- Black background: `#0a0a0a` (matches `PC.bg` from the design system)
- Lime accent: `#A4F03A` (matches `ACCENTS.lime.hue`)

Never substitute either color for production icons.
