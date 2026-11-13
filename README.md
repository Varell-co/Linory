<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="Branding/Linory_Horizontal_Dark.png">
    <img src="Branding/Linory_Horizontal_Light.png" alt="Linory" width="250">
  </picture>
</p>

<h1 align="center">Lyrics in your flow.</h1>

<p align="center">Floating synced lyrics for macOS.<br>Keep the words in view. Stay with what you’re doing.</p>

<p align="center">
  <a href="https://github.com/MikeLeonFox/LyricsOverlay/releases"><b>Download for Mac ↗</b></a> &nbsp; · &nbsp;
  <a href="docs/USAGE.md">Getting started</a> &nbsp; · &nbsp;
  <a href="docs/DEVELOPMENT.md">Build from source</a>
</p>

<p align="center"><sub>macOS 13+ deployment target &nbsp; · &nbsp; Spotify &amp; Apple Music desktop apps &nbsp; · &nbsp; Early prototype</sub></p>

![Linory’s actual floating lyrics overlay presented inside an illustrated MacBook, against a blue desktop](Branding/README/macbook.png)

### Your music. Always in view.

Follow the current line as words brighten with playback. Keep the next lines nearby, without switching away from your work.

![Native Linory captures: five lyric lines in the floating overlay, alongside the current menu with visibility, click-through, position and player controls](Branding/README/overlay-and-menu.png)

**Move it anywhere.** Drag the overlay or snap it to a corner. Enable click-through to keep working underneath, and show or hide it with **⌥ ⇧ L**.

**Follow your player.** Auto follows the app that’s playing. Choose Spotify or Apple Music whenever you prefer.

![Linory’s native settings window with General, Overlay, Timing and About tabs, player selection, auto-hide, launch at login, language and keyboard shortcut](Branding/README/settings.png)

**Make room for your style.** Adjust type, size, opacity and lyric timing. Choose English or German, and optionally launch at login.

<sub>App views captured from the current SwiftUI implementation using original demo lyrics. The MacBook and desktop are illustrations. System materials vary with macOS and appearance. [About the visuals](Branding/README/VISUALS.md).</sub>

### Get Linory

Download the latest ZIP from [Releases](https://github.com/MikeLeonFox/LyricsOverlay/releases), extract it, and open `Linory.app`. Play a song and allow macOS Automation access to your player when prompted. No player login or API key is needed.

> [!IMPORTANT]
> **Early, unnotarized prototype.** This build has no Apple Developer ID signature and may be blocked by Gatekeeper. Only open it if you trust the source; follow [Apple’s opening instructions](https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unidentified-developer-mh40616/mac). Do not disable Gatekeeper globally. Tested on one Mac; Intel hardware and the full macOS 13+ deployment range remain unverified.

Lyrics come from [LRCLIB](https://lrclib.net/); availability and timing vary by song. Plain lyrics use estimated timing and are marked **~ not synced**. Uncached lookups send track metadata to LRCLIB; Spotify artwork is fetched separately. No application analytics are implemented. [Privacy and data](docs/PRIVACY.md).

<p align="center">
  <a href="docs/USAGE.md">Usage &amp; troubleshooting</a> &nbsp; · &nbsp;
  <a href="docs/DEVELOPMENT.md">Development</a> &nbsp; · &nbsp;
  <a href="CONTRIBUTING.md">Contributing</a> &nbsp; · &nbsp;
  <a href="LICENSE">MIT license</a>
</p>

<p align="center"><sub>A <a href="https://varell.co">Varell</a> product.<br>Built on <a href="https://github.com/JulianRudrich/LyricsOverlay">JulianRudrich/LyricsOverlay</a>. MIT applies to the code, not third-party lyrics.<br>Not affiliated with Spotify, Apple or LRCLIB.</sub></p>
