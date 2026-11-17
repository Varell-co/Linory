cask "linory" do
  version "0.3.2"
  sha256 "4e71041ef4823427ac0497b17b5faa2187981944fa9e343e81c5902230e071f6"

  url "https://github.com/Varell-co/Linory/releases/download/v#{version}/Linory-#{version}-universal.zip"
  name "Linory"
  desc "Floating synced lyrics for Spotify and Apple Music"
  homepage "https://github.com/Varell-co/Linory"

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

  uninstall quit: "co.varell.linory"

  zap trash: [
    "~/Library/Application Support/co.varell.linory",
    "~/Library/Preferences/co.varell.linory.plist",
  ]
end
