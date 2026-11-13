# Contributing

Thanks for considering a contribution! This project is an early prototype. The project code is available under the [MIT License](LICENSE).

For a bug report, please include your macOS version, Spotify version, how you installed the app, the steps to reproduce, and what you expected to happen. Do not include private information, Spotify credentials, or full copyrighted song lyrics.

For code changes, run `swift build` and `swift run LyricsCoreChecks`, then test the affected behavior with Spotify when possible. Explain any test limitations in your pull request. Do not add copyrighted lyrics to fixtures or documentation.

This repository is a fork. The original project is configured as the `upstream` remote (`git fetch upstream`). Pull requests for generally useful features may also be offered to [JulianRudrich/LyricsOverlay](https://github.com/JulianRudrich/LyricsOverlay).

To see what the app is doing, stream its logs (metadata only, never lyrics text):

```sh
log stream --predicate 'subsystem == "io.github.mikeleonfox.lyricsoverlay"'
```
