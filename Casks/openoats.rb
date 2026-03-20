cask "openoats" do
  version "1.12.0"
  sha256 "822bfadf0508e16915a45d19c7445c5dc332806e4104836aac94e7ff7d5bba4b"

  url "https://github.com/yazinsai/OpenOats/releases/download/v#{version}/OpenOats.dmg"
  name "OpenOats"
  desc "Real-time meeting copilot"
  homepage "https://github.com/yazinsai/OpenOats"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on macos: ">= :sequoia"

  app "OpenOats.app"

  zap trash: [
    "~/Library/Application Support/OpenOats",
    "~/Library/Caches/com.openoats.app",
    "~/Library/HTTPStorages/com.openoats.app",
    "~/Library/Preferences/com.openoats.app.plist",
    "~/Library/Saved Application State/com.openoats.app.savedState",
    "~/Library/Caches/com.opengranola.app",
    "~/Library/HTTPStorages/com.opengranola.app",
    "~/Library/Preferences/com.opengranola.app.plist",
    "~/Library/Saved Application State/com.opengranola.app.savedState",
  ]
end
