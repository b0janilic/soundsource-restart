class SourcesoundRestart < Formula
  desc "Automatically restarts SoundSource before trial-mode noise kicks in"
  homepage "https://github.com/b0janilic/sourcesound-restart"
  url "https://github.com/b0janilic/sourcesound-restart/archive/refs/tags/v1.0.1.tar.gz"
  sha256 "FIXME" # fill in after: shasum -a 256 <downloaded-tarball>
  license "MIT"

  head "https://github.com/b0janilic/sourcesound-restart.git", branch: "main"

  depends_on :macos

  def install
    libexec.install "sourcesound-restart.sh"
    libexec.install "sourcesound-install.sh"

    # Symlink exposes management commands (status/reload/uninstall) on PATH.
    # Homebrew relinks this on `brew upgrade` via the opt symlink chain.
    bin.install_symlink libexec/"sourcesound-install.sh" => "sourcesound-restart"
  end

  # post_install runs after both `brew install` and `brew upgrade`.
  # launchctl must not be called from `install` — that path runs during `brew audit`.
  #
  # Invoke the installer via opt_libexec (stable symlink), not libexec (versioned Cellar path).
  # This ensures bash's logical `cd` preserves the opt path through SCRIPT_DIR resolution,
  # so the generated LaunchAgent plist references the stable symlink rather than a
  # versioned Cellar path that would break after `brew upgrade` removes the old Cellar.
  #
  # Skip on upgrade: if the plist exists, opt already points to the new version —
  # no reinstall needed.
  def post_install
    plist = File.expand_path("~/Library/LaunchAgents/com.user.sourcesound-restart.plist")
    unless File.exist?(plist)
      system "/bin/bash", "#{opt_libexec}/sourcesound-install.sh", "install"
    end
  end

  def caveats
    <<~EOS
      To completely uninstall the background service:

        sourcesound-restart uninstall
        brew uninstall sourcesound-restart

      Logs: ~/.config/sourcesound-restart/sourcesound-restart.log
    EOS
  end

  test do
    # Syntax-check only — does not execute or touch system state
    system "bash", "-n", libexec/"sourcesound-restart.sh"
    system "bash", "-n", libexec/"sourcesound-install.sh"
  end
end
