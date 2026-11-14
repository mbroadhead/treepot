# treepot

Dev environments in Apple [`container`](https://github.com/apple/container) micro-VMs, one per git worktree. Each worktree gets its own app VM, database VM and volumes. Nothing is added to the app repo.

Rails apps need no configuration. Any other language or framework works with a short config file (see [Other frameworks](#other-frameworks)), and the project doesn't have to be a web app (see [CLI tools and libraries](#cli-tools-and-libraries)).

## Setup

```sh
brew tap mbroadhead/treepot https://github.com/mbroadhead/treepot
brew trust mbroadhead/treepot    # Homebrew asks you to trust third-party taps
brew install treepot             # also installs Apple's container tool
container system start           # once; offers to download a Linux kernel
```

Or from a clone, with no Homebrew: `ln -s "$PWD/bin/treepot" ~/.local/bin/treepot` (any directory on your PATH), after installing `container` yourself.

## Use

From any worktree of your app:

```sh
treepot up                 # build image, start db (+ redis), start app VM, bundle install
treepot rails db:prepare
treepot rails s            # open the URL that `treepot up` printed; every worktree has its own IP on port 3000
treepot bash               # anything that isn't an treepot command runs in the app VM
treepot status
treepot down               # remove the VMs, keep the database and gems
treepot destroy            # also delete the volumes; run before `git worktree remove`
```

## What it detects (Ruby apps)

| Setting | Source | Override |
|---|---|---|
| Ruby | `.ruby-version`, `.tool-versions`, then `Gemfile.lock` | `RUBY_VERSION` |
| Database | `pg` / `mysql2` / `trilogy` in `Gemfile.lock`, else sqlite (no DB VM) | `DB`, `DB_IMAGE` |
| Redis | `redis` gem in `Gemfile.lock` | `REDIS=0\|1`, `REDIS_IMAGE` |

Overrides go in `~/.config/treepot/<project>.env`, where `<project>` is the main repo's directory name:

```sh
# ~/.config/treepot/shop.env
DB_IMAGE=mariadb:11          # default: postgres:17 or mysql:8.4
APT_PACKAGES="libvips-dev"   # extra packages for the app image; run `treepot build` after changing
IMAGE=my/custom:image        # skip the built image entirely (use for Rubies too old for the Dockerfile)
CPUS=8 MEMORY=8G             # default: 4 / 4G
```

## Other frameworks

Anything without a `Gemfile` needs a config file at `~/.config/treepot/<project>.env`, where `<project>` is the main repo's directory name. Start from a template:

```sh
cd ~/src/myapi
treepot init fastapi-uv    # writes ~/.config/treepot/myapi.env
treepot up
```

`treepot init` with no argument lists the templates. Each one is a short commented file in [`examples/`](examples) that also shows the command to start the server.

| Template | For | Dependencies from | Run with |
|---|---|---|---|
| `fastapi-uv` | FastAPI, or any uv project | `pyproject.toml` | `treepot uv run fastapi dev --host 0.0.0.0` |
| `python-pip` | Django, Flask | `requirements.txt` | `treepot python manage.py runserver 0.0.0.0:8000` |
| `node` | Express, Next.js | `package.json` | `treepot npm run dev` |
| `mojolicious` | Mojolicious, Dancer | `cpanfile` | `treepot perl app.pl daemon -l http://0.0.0.0:3000` |
| `go` | Go CLI tools, libraries, servers | `go.mod` | `treepot go run .` |

A server must listen on `0.0.0.0`, not `localhost`, to be reachable from your Mac. Open `http://<ip>:<port>` using the IP that `treepot up` prints.

### Config keys

The config file is a bash file that `treepot` sources, so quoting follows shell rules. `$TOP` holds the worktree's path.

| Key | Meaning | Default |
|---|---|---|
| `IMAGE` | Image for the app VM | required |
| `SETUP` | Shell command run in the worktree on every `treepot up`; make it cheap to re-run | none |
| `CACHE` | Path in the VM kept in a per-worktree volume, for installed dependencies | none |
| `APP_ENV` | Bash array of extra `KEY=value` variables for the app VM | none |
| `DB` | `postgres`, `mysql` or `none` | `none` |
| `DB_IMAGE` | Database image | `postgres:17` or `mysql:8.4` |
| `REDIS` | `1` to start a Redis VM | `0` |
| `CPUS`, `MEMORY` | App VM size | `4`, `4G` |

### Writing a config for another framework

1. **`IMAGE`:** pick the official language image (`elixir:1.18`, `php:8.4`, `rust:1`).
2. **`CACHE` and `SETUP`:** find where the package manager installs dependencies and point `CACHE` there, then set `SETUP` to the install command. If the tool demands an empty directory, use a subdirectory of `CACHE`, because a fresh volume contains `lost+found`.
3. **`APP_ENV`:** add whatever tells the language to look in that location (`PERL5LIB`, `VIRTUAL_ENV`, `GOMODCACHE`).
4. **`DB`:** set it if the app needs a database, then read `DATABASE_URL` in the app.

The same keys work for Ruby apps, where they override the detected defaults.

## CLI tools and libraries

Nothing requires a server or a database. With `DB` unset, `treepot up` starts only the app VM, and `treepot <command>` behaves like running the command locally:

```sh
treepot init go && treepot up
treepot go test ./...
echo input | treepot go run . --stdin    # stdin is passed through
treepot ./mytool --fail; echo $?         # so is the exit code
```

- **Built binaries are Linux arm64.** They land in the worktree but won't run on the Mac. Run them with `treepot ./mytool`, or cross-compile for the host (`treepot env GOOS=darwin go build`).
- **Tooling that writes files** (`go mod tidy`, formatters, lockfile updates) writes straight into the worktree, so the changes show up in `git status` on the host.
- **Each worktree has its own dependency and build cache**, so a second worktree pays the first-build cost again.
- **macOS-specific behaviour can't be tested**: the VM is Linux.

## How the app finds its services

The app VM gets `DATABASE_URL`, `PGHOST`/`PGUSER`/`PGPASSWORD`, `MYSQL_HOST`, `DB_HOST`, `REDIS_URL` and `BINDING=0.0.0.0`. Credentials are `postgres`/`postgres` or `root`/`root`.

- **Rails** (a `config/database.yml` exists): `DATABASE_URL` has host and credentials only, so `database.yml` still names separate dev and test databases.
- **Everything else:** `DATABASE_URL` points at a ready-made database called `app`.

Multi-database Rails apps: `DATABASE_URL` only covers the primary, so point the other entries in `database.yml` at `ENV["DB_HOST"]`.

## Notes

- IPs can change after `treepot down`/`treepot up` or a reboot; `treepot up` rewires the app VM each time. For stable `<name>.test` hostnames see the [container networking docs](https://github.com/apple/container/blob/main/docs/networking.md) (needs sudo).
- The worktree is mounted at its host path, so `git` works inside the VM, including in linked worktrees.
- Test the harness itself: `test/detect_test.sh`.
