# Developing Linory

[Back to Linory](../README.md)

## Build from source

Clone or download this repository, then run the following from the project directory:

```sh
bash build-app.sh
open "$HOME/Applications/Linory.app"
```

Local builds install to `~/Applications/Linory.app` and run as your user, without sudo. Rerun these commands to update; a running Linory restarts with the new build. Build files stay in `.build/local-app`.

To build a bundle elsewhere, set `LINORY_APP_DIR`, for example `LINORY_APP_DIR="$PWD" bash build-app.sh`. Release packaging uses this override to keep their bundles in the repository.

The build script creates a locally ad-hoc-signed app, not a Developer ID-signed or notarized distribution. Gatekeeper behavior can differ on another Mac. A signed and notarized release has not been prepared yet.

## Checks and releases

```sh
swift build
swift run LyricsCoreChecks
# Create an ad-hoc signed universal ZIP in dist/ (version defaults to the VERSION file):
bash build-release.sh
# Release: bump the version, publish on GitHub, update the Homebrew cask:
bash publish-release.sh          # patch, e.g. 0.3.0 -> 0.3.1 (or: minor, major, 1.2.3)
```

`publish-release.sh` needs a clean `main` that matches `origin/main`, and a logged-in `gh`. It drafts release notes from `feat:` and `fix:` commit subjects since the last tag, shows them and asks before publishing (`e` opens them in your editor, `-y` skips the question). To write the notes yourself, add a `# Linory vX.Y.Z` section at the top of `RELEASE_NOTES.md` first. It then commits VERSION, notes and cask as `chore: release X.Y.Z`, tags, publishes the ZIP, and runs `brew upgrade --cask linory` if Linory is installed through Homebrew.

The checks cover LRC parsing, conservative track matching, localization, the playback clock, plain-lyrics timing, the lyrics cache, player selection, Spotify PKCE login parameters, Spotify Web API response decoding, and True Shuffle cycles. They do not replace an end-to-end test with Spotify and Music: verify the automation prompt, loading lyrics, pausing, seeking, changing tracks, the overlay controls, and the global shortcut. For True Shuffle, connect your own Spotify app (see [Usage](USAGE.md#connect-spotify-optional)), then check Shuffle & play, played counting while skipping, Reset, Remove from shuffle, Restore removed, and Keep this shuffle. XCTest is not available in every Command Line Tools installation, so the current checks use a standalone executable.
