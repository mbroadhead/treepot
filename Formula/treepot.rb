class Treepot < Formula
  desc "Per-worktree dev environments in Apple container micro-VMs"
  homepage "https://github.com/mbroadhead/treepot"
  url "https://github.com/mbroadhead/treepot/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "116c93b9f5e3c794e87b6181695cfc53fa055829a958aa4545db730c4bec0a15"
  license "MIT"
  head "https://github.com/mbroadhead/treepot.git", branch: "main"

  depends_on "container"
  depends_on :macos

  def install
    # treepot finds its Dockerfile and examples relative to its own (resolved) path.
    libexec.install "bin", "Dockerfile", "examples"
    bin.install_symlink libexec/"bin/treepot"
  end

  def caveats
    <<~EOS
      Start Apple's container service once before first use:
        container system start
      For stable hostnames (<worktree>-app.test) instead of IP addresses, run once:
        treepot dns
    EOS
  end

  test do
    assert_match "usage: treepot", shell_output("#{bin}/treepot --help")
  end
end
