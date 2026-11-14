#!/usr/bin/env bash
# Self-check for treepot's detection and naming logic. Needs no VM.
set -euo pipefail
source "$(dirname "$0")/../bin/treepot"

t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
fails=0
eq() { if [[ $1 == "$2" ]]; then echo "ok   $3"; else echo "FAIL $3: got '$1', want '$2'"; fails=1; fi; }
lock() { mkdir -p "$t/$1"; printf 'GEM\n  specs:\n    %s (1.0)\n    rails (7.1.0)\n      pgx (>= 1)\n\nRUBY VERSION\n   ruby 3.2.2p53\n' "$2" > "$t/$1/Gemfile.lock"; }

lock pg pg; lock my mysql2; lock tr trilogy; lock sq sqlite3; lock rd redis; mkdir "$t/empty"
svc() { detect_services "$1" | tr '\n' ' '; }
eq "$(svc "$t/pg")" "postgres " "pg gem -> postgres"
eq "$(svc "$t/my")" "mysql " "mysql2 gem -> mysql"
eq "$(svc "$t/tr")" "mysql " "trilogy gem -> mysql"
eq "$(svc "$t/sq")" "" "sqlite3 gem -> no services"
eq "$(svc "$t/rd")" "redis " "redis gem -> redis"
eq "$(svc "$t/empty")" "" "no dependency files -> no services"
has_gem "$t/pg" pgx && r=1 || r=0; eq "$r" 0 "dependency lines are not gems"

mk() { mkdir -p "$t/$1"; printf '%b' "$3" > "$t/$1/$2"; }
mk py pyproject.toml 'dependencies = ["fastapi", "psycopg[binary]", "redis>=5"]\n'
mk pip requirements.txt 'django\nmysqlclient\nredis==5.0\n'
mk js package.json '{"dependencies": {"pg": "^8", "mysql2": "^3", "ioredis": "^5"}}\n'
mk pl cpanfile "requires 'Mojo::Pg';\nrequires 'Redis';\n"
mk go go.mod 'require (\n\tgithub.com/jackc/pgx/v5 v5.0.0\n\tgithub.com/go-sql-driver/mysql v1.8.0\n)\n'
mk plain pyproject.toml 'dependencies = ["click", "redistricting"]\n'
eq "$(svc "$t/py")" "postgres redis " "python: psycopg + redis"
eq "$(svc "$t/pip")" "mysql redis " "pip: mysqlclient + redis"
eq "$(svc "$t/js")" "postgres mysql redis " "node: pg + mysql2 + ioredis"
eq "$(svc "$t/pl")" "postgres redis " "perl: Mojo::Pg + Redis"
eq "$(svc "$t/go")" "postgres mysql " "go: pgx + mysql driver"
eq "$(svc "$t/plain")" "" "no drivers (and 'redistricting' is not redis)"

eq "$(detect_template "$t/pg")" "" "Gemfile.lock alone is not a Gemfile"
touch "$t/pg/Gemfile" "$t/pg/package.json"
eq "$(detect_template "$t/pg")" ruby-bundler "Gemfile beats package.json"
eq "$(detect_template "$t/py")" python-uv "pyproject.toml -> python-uv"
eq "$(detect_template "$t/pip")" python-pip "requirements.txt -> python-pip"
eq "$(detect_template "$t/js")" node-npm "package.json -> node-npm"
eq "$(detect_template "$t/pl")" perl-cpanm "cpanfile -> perl-cpanm"
eq "$(detect_template "$t/go")" go "go.mod -> go"
eq "$(detect_template "$t/empty")" "" "unknown project -> nothing"
for f in "$(dirname "$0")"/../examples/*.ini; do git config -f "$f" --get app.image >/dev/null && r=1 || r=0; eq "$r" 1 "template $(basename "$f") parses and sets app.image"; done

CFG=$t/c.ini; printf '[app]\n  image = x\n  env = A=1\n  env = B=2\n  setup = "a; b"\n[service "postgres"]\n  image = postgres:14\n[service "search"]\n  image = es:8\n  env = k=v\n' > "$CFG"
eq "$(cfg_services | tr '\n' ' ')" "postgres search " "service sections listed in file order"
eq "$(cfg_all app.env | tr '\n' ' ')" "A=1 B=2 " "repeated keys"
eq "$(cfg app.setup)" "a; b" "quoted value keeps its semicolon"
eq "$(cfg app.cache)" "" "missing key -> empty"
CFG=$t/none.ini; eq "$(cfg_services)$(cfg app.image)" "" "missing config file -> empty"

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

mkdir -p "$t/proj/frontend/src" "$t/proj/t" "$t/cfgs" "$t/bare/sub"
touch "$t/proj/cpanfile" "$t/proj/frontend/package.json"
eq "$(find_root "$t/proj/t" "$t/cfgs")" "$t/proj" "root from a subdirectory via the manifest"
eq "$(find_root "$t/proj/frontend/src" "$t/cfgs")" "$t/proj/frontend" "no config yet: nearest manifest wins"
touch "$t/cfgs/proj.ini"
eq "$(find_root "$t/proj/frontend/src" "$t/cfgs")" "$t/proj" "an initialised project beats a nested manifest"
eq "$(find_root "$t/bare/sub" "$t/cfgs")" "$t/bare/sub" "no markers at all -> the directory itself"
eq "$(HOME=$t/proj find_root "$t/proj/t" "$t/cfgs")" "$t/proj/t" "HOME is never a project root"

vm() { printf '{"status":{"networks":[{"hostname":"%s","ipv4Address":"192.168.64.5/24"}]}}' "$1"; }
ad() { vm "$1" | jq -r --argjson d "$2" "$JQ_ADDR addr"; }
eq "$(ad shop-app.test. '["test"]')" shop-app.test "DNS name when its domain is resolvable from the Mac"
eq "$(ad shop-app.test. '[]')" 192.168.64.5 "IP when the domain is not registered on the Mac"
eq "$(ad shop-app '["test"]')" 192.168.64.5 "IP when the VM has no domain"
eq "$(ad shop-app.dev. '["test"]')" 192.168.64.5 "IP when the VM's domain is a different one"
eq "$(echo '{"status":{"networks":[]}}' | jq -r --argjson d '[]' "$JQ_ADDR addr")" "-" "stopped VM has no address"

exit $fails
