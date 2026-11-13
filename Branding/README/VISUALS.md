# README visuals

The app interfaces are macOS window captures of the repository's actual `OverlayView`, `MenuPanel` and `SettingsView` in `Sources/Linory/`, captured on November 13, 2026. They are not AI-generated interfaces or the identity kit's concept UI.

The captures use a temporary native host, English, dark appearance, version 0.2.0 and the default 400 × 240 overlay. The host seeds `PlayerModel` without starting player polling or making lyrics requests. “A little closer” by “Linory Sessions” and its five lines are original demonstration content, not a commercial recording or an LRCLIB result. Cover art uses the app's real placeholder.

The current menu includes the Now Playing header, Show overlay, Click-through, Position, Source, Settings and Quit. It is captured with both disclosure sections collapsed. Settings shows General with optional switches off.

The MacBook, desktop wallpaper and surrounding layouts are vector illustrations. The SVG sources embed the native captures without redrawing their controls or text. The PNG exports are used by the README for consistent GitHub rendering. macOS materials vary with the OS version, appearance, wallpaper and accessibility settings.

`native-overlay.png`, `native-menu.png` and `native-settings.png` retain the original window captures. To update the promotional layouts, replace the embedded image data in the corresponding SVG with a new native capture, preserving its aspect ratio, then export with:

```sh
rsvg-convert Branding/README/macbook.svg -o Branding/README/macbook.png
rsvg-convert Branding/README/overlay-and-menu.svg -o Branding/README/overlay-and-menu.png
rsvg-convert Branding/README/settings.svg -o Branding/README/settings.png
```

Brand colors and the existing wordmark come from Linory Brand Identity v1. The layout follows the restrained neutral surfaces and typography of [Varell](https://varell.co).
