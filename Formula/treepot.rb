class Treepot < Formula
  desc "Per-worktree dev environments in Apple container micro-VMs"
  homepage "https://github.com/mbroadhead/treepot"
  url "https://github.com/mbroadhead/treepot/archive/refs/tags/v0.4.0.tar.gz"
  sha256 "e0c3a858224ab1a7248c01f26ded42e5e04786f8fed3f354c86dc0eb1665e10d"
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
      For stable hostnames (myapp.test, feature.myapp.test) instead of IP addresses, run once:
        treepot dns
    EOS
  end

  test do
    assert_match "usage: treepot", shell_output("#{bin}/treepot --help")
  end
end
