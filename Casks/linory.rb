cask "linory" do
  version "0.3.1"
  sha256 "45e1d60e4bad4ba8a7c651377ef71f1f758f0dab5150d3783f50a358fd9d090e"

  url "https://github.com/MikeLeonFox/LyricsOverlay/releases/download/v#{version}/Linory-#{version}-universal.zip"
  name "Linory"
  desc "Floating synced lyrics for Spotify and Apple Music"
  homepage "https://github.com/MikeLeonFox/LyricsOverlay"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :ventura

  app "Linory.app"

  # The app is ad-hoc signed and not notarized, so a quarantined copy will not open.
  # Clearing the flag for this one app is the opt-in trust decision made by installing the cask.
  postflight_steps do
    run "/usr/bin/xattr",
        args:           ["-dr", "com.apple.quarantine", "{{appdir}}/Linory.app"],
        writable_paths: ["Linory.app"],
        writable_base:  :appdir
  end

  uninstall quit: "io.github.mikeleonfox.lyricsoverlay"

  zap trash: [
    "~/Library/Application Support/io.github.mikeleonfox.lyricsoverlay",
    "~/Library/Preferences/io.github.mikeleonfox.lyricsoverlay.plist",
  ]
end
