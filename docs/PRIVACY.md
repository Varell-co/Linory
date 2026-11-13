# Privacy and third-party services

[Back to Linory](../README.md)

For each track lookup that is not cached, the app sends the song title, artist, album, and duration to LRCLIB over HTTPS. LRCLIB receives the request and associated network metadata, such as your IP address. Playback details are read locally from Spotify or Music through macOS Automation. For Spotify tracks, the cover art is downloaded from the image link Spotify provides; Music provides its cover art locally. Settings and the window position are stored locally in macOS preferences. Lookup results are cached in `~/Library/Application Support/io.github.mikeleonfox.lyricsoverlay/lyrics-cache.json` (up to 500 tracks; "not found" results are retried after 7 days). Delete that file to clear the cache. No application analytics are implemented in this prototype.

LRCLIB is a third-party service, and its availability and policies may change. Users and distributors are responsible for considering applicable terms and rights relating to lyrics. This project is not affiliated with Spotify, Apple, or LRCLIB. Linory is a Varell product; brand assets and guidelines are in [`Branding/`](../Branding/).
