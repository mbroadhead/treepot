class Treepot < Formula
  desc "Per-worktree dev environments in Apple container micro-VMs"
  homepage "https://github.com/mbroadhead/treepot"
  url "https://github.com/mbroadhead/treepot/archive/refs/tags/v0.2.1.tar.gz"
  sha256 "9287006523071d701a7b3841bc29f8de1359299a7eb7b7919ff57a87541fa228"
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
