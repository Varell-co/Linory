# Developing Linory

[Back to Linory](../README.md)

## Build from source

Clone or download this repository, then run the following from the project directory:

```sh
bash build-app.sh
open "$HOME/Applications/Linory.app"
```

Local builds install to `~/Applications/Linory.app` and run as your user, without sudo. Rerun these commands to update; a running Linory restarts with the new build. Build files stay in `.build/local-app`.

To build a bundle elsewhere, set `LINORY_APP_DIR`, for example `LINORY_APP_DIR="$PWD" bash build-app.sh`. Release packaging and CI use this override to keep their bundles in the repository.

The build script creates a locally ad-hoc-signed app, not a Developer ID-signed or notarized distribution. Gatekeeper behavior can differ on another Mac. A signed and notarized release has not been prepared yet.

## Checks and releases

```sh
swift build
swift run LyricsCoreChecks
# Create an ad-hoc signed universal ZIP in dist/ (version defaults to the VERSION file):
bash build-release.sh
```

The checks cover LRC parsing, conservative track matching, localization, the playback clock, plain-lyrics timing, the lyrics cache, and player selection. They do not replace an end-to-end test with Spotify and Music: verify the automation prompt, loading lyrics, pausing, seeking, changing tracks, the overlay controls, and the global shortcut. XCTest is not available in every Command Line Tools installation, so the current checks use a standalone executable.
