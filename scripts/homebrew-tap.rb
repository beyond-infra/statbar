# Homebrew Formula for statbar
#
# To publish:
#   1. Create repo: github.com/beyond-infra/homebrew-tap
#   2. Copy this file to homebrew-tap/Formula/statbar.rb
#   3. Update `url` and `sha256` for each release
#
# Users install with:
#   brew tap beyond-infra/tap
#   brew install statbar

class Statbar < Formula
  desc "macOS menu bar CPU & memory monitor"
  homepage "https://github.com/beyond-infra/statbar"
  url "https://github.com/beyond-infra/statbar/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "cba1498b5cfd8a08582551f1105ea76a9c43ad940732bbacd53efb7f0fc3cb99"
  license "MIT"

  depends_on macos: :ventura
  uses_from_macos "swift"

  def install
    system "make"
    bin.install "statbar"
  end

  def post_install
    ohai "statbar installed to #{opt_bin}/statbar — auto-starts on next login"
  end

  def caveats
    plist = etc/"com.statbar.plist"
    plist.write <<~EOS
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0">
      <dict>
        <key>Label</key>
        <string>com.statbar</string>
        <key>Program</key>
        <string>#{opt_bin}/statbar</string>
        <key>RunAtLoad</key>
        <true/>
        <key>KeepAlive</key>
        <true/>
      </dict>
      </plist>
    EOS

    <<~EOS
      To auto-start statbar on login, run:
        mkdir -p ~/Library/LaunchAgents
        cp #{plist} ~/Library/LaunchAgents/com.statbar.plist

      Then to start immediately (or just logout and back in):
        launchctl bootstrap gui/#{Process.uid} ~/Library/LaunchAgents/com.statbar.plist

      To stop:
        launchctl bootout gui/#{Process.uid}/com.statbar

      To uninstall:
        brew uninstall statbar
        rm ~/Library/LaunchAgents/com.statbar.plist
    EOS
  end

  test do
    system "#{bin}/statbar", "--version"
  end
end
