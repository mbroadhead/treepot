#!/usr/bin/env bash
# Self-check for `treepot dns` against a fake `container` and `sudo`, so it never touches the real system.
set -euo pipefail
treepot=$(cd "$(dirname "$0")/.." && pwd)/bin/treepot
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
fails=0
eq() { if [[ $1 == "$2" ]]; then echo "ok   $3"; else echo "FAIL $3: got '$1', want '$2'"; fails=1; fi; }

mkdir "$t/bin" "$t/home"
# The fake keeps the "running service" view in $t/live; a restart copies the config file's domain into it, like the real one.
cat > "$t/bin/container" <<FAKE
#!/usr/bin/env bash
echo "container \$*" >> "$t/log"
case "\$*" in
  "system property list") echo "[dns]"; [[ ! -s "$t/live" ]] || echo "domain = \"\$(cat "$t/live")\""; echo; echo "[kernel]" ;;
  "system dns list") echo DOMAIN; cat "$t/registered" 2>/dev/null || true ;;
  "system start") sed -n 's/^domain = "\(.*\)"/\1/p' "$t/home/.config/container/config.toml" > "$t/live" 2>/dev/null || true ;;
  "system dns create "*) echo "\$4" >> "$t/registered" ;;
  "ls -q") echo one; echo two ;;
esac
FAKE
printf '#!/usr/bin/env bash\necho "sudo $*" >> "%s/log"\nexec "$@"\n' "$t" > "$t/bin/sudo"
chmod +x "$t/bin/container" "$t/bin/sudo"
run() { HOME=$t/home PATH=$t/bin:$PATH "$treepot" dns "$@" 2>&1; }
calls() { grep -cE "$1" "$t/log" || true; }
conf=$t/home/.config/container/config.toml

eq "$(run status | tail -1)" "not set up: run 'treepot dns'" "status on a fresh machine"
mkdir -p "$t/home/early"; touch "$t/home/early/cpanfile"
eq "$(cd "$t/home/early" && HOME=$t/home XDG_CONFIG_HOME=$t/cfg PATH=$t/bin:/usr/bin:/bin "$treepot" cert 2>&1)" "treepot: set up names first: run 'treepot dns'" "cert before dns points at treepot dns"
eq "$(echo n | run | tail -1)" "treepot: aborted" "declining the restart changes nothing"
[[ ! -e $conf ]] && r=1 || r=0; eq "$r" 1 "no config written after declining"
out=$(echo y | run)
eq "$(cat "$conf")" $'[dns]\ndomain = "test"' "fresh setup writes the domain"
eq "$(echo "$out" | grep -c 'stops ALL running VMs, in every worktree (2 running now)')" 1 "warns how many VMs the restart stops"
eq "$(calls '^container system stop$')$(calls '^container system start$')$(calls '^sudo container system dns create test$')" 111 "restarts once and registers with sudo"
eq "$(run status | tail -1)" "ok: apps are reachable as <project>.test (main worktree) and <worktree>.<project>.test" "status after setup"

# treepot cert, against a fake mkcert, in a project called "shop".
mkdir -p "$t/home/shop/lib" "$t/mk"; touch "$t/home/shop/cpanfile"
cat > "$t/mk/mkcert" <<FAKE
#!/usr/bin/env bash
echo "mkcert \$*" >> "$t/log"
case "\$1" in
  -CAROOT) echo "$t/caroot" ;;
  -install) mkdir -p "$t/caroot"; touch "$t/caroot/rootCA.pem" ;;
  -cert-file) echo CERT > "\$2"; echo KEY > "\$4" ;;
esac
FAKE
chmod +x "$t/mk/mkcert"
cert() { (cd "$t/home/shop/lib" && HOME=$t/home XDG_CONFIG_HOME=$t/cfg PATH=$1:/usr/bin:/bin "$treepot" cert 2>&1); }
eq "$(cert "$t/bin" </dev/null | grep -c "brew install mkcert")" 1 "cert without mkcert says how to install it"
eq "$(echo n | cert "$t/mk:$t/bin" | tail -1)" "treepot: aborted" "declining the local CA changes nothing"
[[ ! -e $t/cfg/treepot/certs/shop/cert.pem ]] && r=1 || r=0; eq "$r" 1 "no certificate after declining"
out=$(echo y | cert "$t/mk:$t/bin")
eq "$(cat "$t/cfg/treepot/certs/shop/cert.pem" "$t/cfg/treepot/certs/shop/key.pem" | tr '\n' ' ')" "CERT KEY " "certificate and key are written for the project"
eq "$(calls '^mkcert -cert-file .* shop.test \*\.shop\.test$')" 1 "certificate covers the project name and its wildcard"
eq "$(echo "$out" | tail -1 | sed 's/^ *//')" "Point your server at them on port 443, then open https://shop.test" "cert says what to do next"
out=$(cert "$t/mk:$t/bin" </dev/null); eq "$(echo "$out" | grep -c 'Create and trust')" 0 "second run does not ask about the CA again"
: > "$t/log"; out=$(run </dev/null)
eq "$(calls 'system (stop|start)|sudo')" 0 "re-running when set up restarts nothing and needs no sudo"
eq "$(run vm </dev/null | grep -c "DNS domain is already 'test'")" 1 "refuses to switch an existing domain"

# Half done: domain configured, not yet registered with macOS.
: > "$t/registered"; : > "$t/log"; run </dev/null >/dev/null
eq "$(calls 'system (stop|start)')$(calls '^sudo container system dns create test$')" 01 "finishes a half-done setup without restarting"

# A config file treepot did not write is never edited.
rm -f "$t/live" "$t/registered"; echo '[build]' > "$conf"
eq "$(echo y | run | head -1 | sed "s|$t/home|~|")" "treepot: ~/.config/container/config.toml already exists. Add these two lines to it, run 'container system stop && container system start', then re-run 'treepot dns test':" "existing config is left alone"
eq "$(cat "$conf")" "[build]" "existing config unchanged"
eq "$(run 'bad domain!' </dev/null | grep -c "bad domain 'bad domain!'")" 1 "rejects a malformed domain"

exit $fails
