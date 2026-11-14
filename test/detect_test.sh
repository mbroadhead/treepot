#!/usr/bin/env bash
# Self-check for rv's detection and naming logic. Needs no VM.
set -euo pipefail
source "$(dirname "$0")/../bin/rv"

t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
fails=0
eq() { if [[ $1 == "$2" ]]; then echo "ok   $3"; else echo "FAIL $3: got '$1', want '$2'"; fails=1; fi; }
lock() { mkdir -p "$t/$1"; printf 'GEM\n  specs:\n    %s (1.0)\n    rails (7.1.0)\n      pgx (>= 1)\n\nRUBY VERSION\n   ruby 3.2.2p53\n' "$2" > "$t/$1/Gemfile.lock"; }

lock pg pg; lock my mysql2; lock tr trilogy; lock sq sqlite3; lock rd redis; mkdir "$t/empty"
eq "$(detect_db "$t/pg")" postgres "pg gem -> postgres"
eq "$(detect_db "$t/my")" mysql2 "mysql2 gem"
eq "$(detect_db "$t/tr")" trilogy "trilogy gem"
eq "$(detect_db "$t/sq")" sqlite "sqlite3 gem -> sqlite"
eq "$(detect_db "$t/empty")" sqlite "no lockfile -> sqlite"
has_gem "$t/rd" redis && r=1 || r=0; eq "$r" 1 "redis gem found"
has_gem "$t/pg" pgx && r=1 || r=0; eq "$r" 0 "dependency lines are not gems"

eq "$(detect_ruby "$t/pg")" 3.2.2 "ruby from Gemfile.lock, patchlevel stripped"
printf 'nodejs 20.0.0\nruby 3.1.4\n' > "$t/pg/.tool-versions"
eq "$(detect_ruby "$t/pg")" 3.1.4 ".tool-versions beats Gemfile.lock"
echo 'ruby-2.7.8' > "$t/pg/.ruby-version"
eq "$(detect_ruby "$t/pg")" 2.7.8 ".ruby-version wins, ruby- prefix stripped"
eq "$(detect_ruby "$t/empty")" "" "nothing to detect -> empty"

eq "$(project_for /src/shop/.git)" shop "project from normal repo"
eq "$(project_for /src/shop.git)" shop "project from bare repo"
eq "$(slug_for /src/shop shop)" shop "main worktree slug"
eq "$(slug_for /src/Shop_Feature.X shop)" shop-shop-feature-x "linked worktree slug is sanitized"

eq "$(slug_for /src/shop-feature shop)" shop-feature "project-prefixed worktree dir is not doubled"

exit $fails
