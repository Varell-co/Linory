cask "linory" do
  version "0.3.0"
  sha256 "7629d5831b0ce4064d62f8422377050c2fe29b1dfd3a8d89f4d185acc0f6a296"

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
