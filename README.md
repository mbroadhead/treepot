# rv

Run any Rails app in Apple [`container`](https://github.com/apple/container) micro-VMs. Each git worktree gets its own app VM, database VM and volumes. Nothing is added to the app repo.

## Setup

```sh
brew install container && container system start   # once
ln -s "$PWD/bin/rv" /usr/local/bin/rv               # or add bin/ to PATH
```

## Use

From any worktree of a Rails app:

```sh
rv up                 # build image, start db (+ redis), start app VM, bundle install
rv rails db:prepare
rv rails s            # open the URL that `rv up` printed; every worktree has its own IP on port 3000
rv bash               # anything that isn't an rv command runs in the app VM
rv status
rv down               # remove the VMs, keep the database and gems
rv destroy            # also delete the volumes; run before `git worktree remove`
```

## What it detects

| Setting | Source | Override |
|---|---|---|
| Ruby | `.ruby-version`, `.tool-versions`, then `Gemfile.lock` | `RUBY_VERSION` |
| Database | `pg` / `mysql2` / `trilogy` in `Gemfile.lock`, else sqlite (no DB VM) | `DB`, `DB_IMAGE` |
| Redis | `redis` gem in `Gemfile.lock` | `REDIS=0\|1`, `REDIS_IMAGE` |

Overrides go in `projects/<project>.env`, where `<project>` is the main repo's directory name:

```sh
# projects/shop.env
DB_IMAGE=mariadb:11          # default: postgres:17 or mysql:8.4
APT_PACKAGES="libvips-dev"   # extra packages for the app image; run `rv build` after changing
IMAGE=my/custom:image        # skip the built image entirely (use for Rubies too old for the Dockerfile)
CPUS=8 MEMORY=8G             # default: 4 / 4G
```

## How the app finds its services

The app VM gets `DATABASE_URL` (host and credentials only, so `database.yml` still names separate dev and test databases), `PGHOST`/`PGUSER`/`PGPASSWORD`, `MYSQL_HOST`, `DB_HOST`, `REDIS_URL` and `BINDING=0.0.0.0`. Credentials are `postgres`/`postgres` or `root`/`root`.

Multi-database apps: `DATABASE_URL` only covers the primary, so point the other entries in `database.yml` at `ENV["DB_HOST"]`.

## Notes

- IPs can change after `rv down`/`rv up` or a reboot; `rv up` rewires the app VM each time. For stable `<name>.test` hostnames see the [container networking docs](https://github.com/apple/container/blob/main/docs/networking.md) (needs sudo).
- The worktree is mounted at its host path, so `git` works inside the VM, including in linked worktrees.
- Test the harness itself: `test/detect_test.sh`.
