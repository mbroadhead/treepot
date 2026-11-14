# treepot

Dev environments in Apple [`container`](https://github.com/apple/container) micro-VMs, one per git worktree. Each worktree gets its own app VM, service VMs (databases and anything else) and volumes. Nothing is added to the project's repo.

Rails apps need no configuration. Any other language or framework needs one short config file, which `treepot init` writes for you. The project doesn't have to be a web app.

## Setup

```sh
brew tap mbroadhead/treepot https://github.com/mbroadhead/treepot
brew trust mbroadhead/treepot    # Homebrew asks you to trust third-party taps
brew install treepot             # also installs Apple's container tool
container system start           # once; offers to download a Linux kernel
```

Or from a clone, with no Homebrew: `ln -s "$PWD/bin/treepot" ~/.local/bin/treepot` (any directory on your PATH), after installing `container` yourself.

## Use

From any worktree of your project:

```sh
treepot init              # not needed for Rails; writes ~/.config/treepot/<project>.ini
treepot up                # start services and the app VM, install dependencies
treepot config            # edit the config in $EDITOR; the next `treepot up` applies it
treepot rails s           # anything that isn't a treepot command runs in the app VM
treepot bash
treepot status
treepot down              # remove the VMs, keep data and installed dependencies
treepot destroy           # also delete the volumes; run before `git worktree remove`
```

`treepot up` prints each VM's address. A server must listen on `0.0.0.0`, not `localhost`, to be reachable from your Mac.

## Rails

With a `Gemfile` and no config file, everything is detected:

| Setting | Source |
|---|---|
| Ruby version | `.ruby-version`, `.tool-versions`, then `Gemfile.lock` |
| Services | `pg` → postgres, `mysql2`/`trilogy` → mysql, `redis` → redis (all that are present) |

The app image is built once per Ruby version and includes Node, yarn and the database clients. To change something, add a config file with just the keys you need (see [Config reference](#config-reference)). Any `[service]` section in it replaces the detected services.

## Other languages

```sh
cd ~/src/myapi
treepot init
# template: python-uv
# services: postgres (detected; ...)
# wrote ~/.config/treepot/myapi.ini; review it, then run 'treepot up'
```

`treepot init` picks a template from the files in the worktree and adds a service for each database driver it finds in your dependencies. Name a template or pass `--with` to override either choice:

```sh
treepot init python-pip --with postgres,redis
treepot init --with none
```

| Template | Chosen when it finds | Use for | Typical command |
|---|---|---|---|
| `ruby-bundler` | `Gemfile` | Non-Rails Ruby: CLI tools, gems, Sinatra | `treepot ruby bin/mytool` |
| `go` | `go.mod` | Go CLI tools, libraries, servers | `treepot go run .` |
| `python-uv` | `uv.lock`, `pyproject.toml` | FastAPI, CLI tools, libraries | `treepot uv run pytest` |
| `python-pip` | `requirements.txt` | Django, Flask | `treepot python manage.py runserver 0.0.0.0:8000` |
| `perl-cpanm` | `cpanfile`, `Makefile.PL`, `Build.PL` | Mojolicious, Dancer, CLI tools, modules | `treepot prove -lr t` |
| `node-npm` | `package.json` | Express, Next.js, CLI tools | `treepot npm run dev` |

The templates are the commented files in [`examples/`](examples). Service detection is a text search for well-known driver names (`psycopg`, `pg`, `DBD::Pg`, `mysqlclient`, `ioredis` and so on); if it misses yours, use `--with` or edit the file.

## Config reference

`~/.config/treepot/<project>.ini`, where `<project>` is the main repo's directory name. All worktrees of a project share it. The format is the same as a git config file: values containing `;` or `#` need double quotes, and a key may be repeated.

```ini
[app]
    image = ghcr.io/astral-sh/uv:python3.13-bookworm
    setup = uv sync
    cache = /cache
    env = UV_PROJECT_ENVIRONMENT=/cache/venv
    env = UV_LINK_MODE=copy

[service "postgres"]
    image = postgres:17

[service "mysql"]
    image = mariadb:11

[service "mail"]
    image = axllent/mailpit:latest
    env = MP_DATABASE=/data/mailpit.db
    volume = /data
    port = 8025
```

### `[app]`

| Key | Meaning | Default |
|---|---|---|
| `image` | Image for the app VM | required, except for Ruby projects |
| `setup` | Shell command run in the worktree on every `treepot up`; make it cheap to re-run | none (Ruby: `bundle install` if needed) |
| `cache` | Path kept in a per-worktree volume, for installed dependencies. A relative path is inside the worktree. | none (Ruby: `/usr/local/bundle`) |
| `env` | `KEY=value` for the app VM; repeatable | none |
| `cpus`, `memory` | App VM size | `4`, `4G` |
| `ruby` | Ruby version, when it can't be detected | detected |
| `apt` | Extra apt packages for the built Ruby image; run `treepot build` after changing | none |

If a tool insists on an empty directory, point it at a subdirectory of `cache`: a fresh volume contains `lost+found`.

### `[service "<name>"]`

Each section is one VM per worktree. A service can be any Docker (OCI) image with a Linux arm64 build.

| Key | Meaning |
|---|---|
| `image` | Image to run. Required, except for the built-ins below. |
| `env` | `KEY=value` for the service; repeatable |
| `volume` | Path inside the service to keep in a per-worktree volume, so data survives `down` |
| `port` | `treepot up` waits until this port accepts connections before starting the app |

Three names are built in. `treepot` gives them a password, a data volume and a readiness check, so `image` is all you might set:

| Name | Default image | Login | The app VM also gets |
|---|---|---|---|
| `postgres` | `postgres:17` | `postgres` / `postgres` | `POSTGRES_URL`, `PGHOST`, `PGUSER`, `PGPASSWORD` |
| `mysql` | `mysql:8.4` (MariaDB images work) | `root` / `root` | `MYSQL_URL` |
| `redis` | `redis:7` | none | `REDIS_URL` |

Any other name is a generic service: `treepot` runs the image with its default command and the settings you give it. What the image needs is documented on its registry page.

## How the app finds its services

For every service, the app VM gets:

- **A hostname:** the service's name. `postgres`, `mysql` or `mail` resolve from inside the app VM.
- **`<NAME>_HOST`:** its address, for example `MAIL_HOST`.

`DATABASE_URL` and `DB_HOST` point at the first database in the file.

- **Rails** (a `config/database.yml` exists): the URLs carry host and credentials only, so `database.yml` still names separate development and test databases. For a second database, point its `database.yml` entry at `ENV["MYSQL_URL"]` or `ENV["POSTGRES_URL"]`.
- **Everything else:** the URLs point at a ready-made database called `app`.

## Changing the config

```sh
treepot config    # opens ~/.config/treepot/<project>.ini in $EDITOR and checks the syntax when you save
treepot up        # applies it
```

`treepot up` works out what changed, so there is no need for `down` first:

- **App VM:** recreated on every `up`, so `[app]` changes always apply. Installed dependencies are kept in the `cache` volume.
- **A service whose settings changed:** its VM is replaced. Its data volume is kept.
- **A service you removed:** its VM is removed. Its data volume stays until `treepot destroy`.
- **Unchanged services:** left running.

`treepot config path` prints the file's location. For a Rails app with no config yet, `treepot config` creates one containing only commented-out examples.

## Stable names instead of IP addresses

By default `treepot` shows IP addresses, and they change whenever a VM is recreated. Run this once per Mac to get stable names:

```sh
treepot dns
```

From then on `treepot up` and `treepot status` show names such as `myapp-feature-app.test` and `myapp-feature-postgres.test`, usable from your Mac's browser and database tools. The pattern is `<project>-<worktree>-<service>.<domain>`.

What the command does:

- **Sets the domain** in Apple `container`'s config (`~/.config/container/config.toml`) and restarts `container`. The restart stops every running VM, so it asks first.
- **Registers the domain with macOS** using `sudo`, which asks for your password. After this, all `.test` lookups on your Mac go to `container`.

`treepot dns status` shows what is set up. Use another domain with `treepot dns vm` if `.test` is taken by another tool. It is safe to re-run: it only does the steps still missing.

If `config.toml` already exists, `treepot` won't edit it and prints the lines to add instead. The manual equivalent of the whole setup is:

```sh
printf '[dns]\ndomain = "test"\n' > ~/.config/container/config.toml
container system stop && container system start
sudo container system dns create test
```

To undo it: remove the `[dns]` lines, restart `container`, and run `sudo container system dns delete test`.

## CLI tools and libraries

Nothing requires a server or a database. With no `[service]` sections, `treepot up` starts only the app VM, and `treepot <command>` behaves like running the command locally:

```sh
treepot init && treepot up
treepot go test ./...
echo input | treepot go run . --stdin    # stdin is passed through
treepot ./mytool --fail; echo $?         # so is the exit code
```

- **Built binaries are Linux arm64.** They land in the worktree but won't run on the Mac. Run them with `treepot ./mytool`, or cross-compile for the host (`treepot env GOOS=darwin go build`).
- **Tooling that writes files** (`go mod tidy`, formatters, lockfile updates) writes straight into the worktree, so the changes show up in `git status` on the host.
- **Each worktree has its own dependency and build cache**, so a second worktree pays the first-build cost again.
- **macOS-specific behaviour can't be tested**: the VM is Linux.

## Notes

- The worktree is mounted at its host path, so `git` works inside the VM, including in linked worktrees.
- A project that isn't a git repository works too, as a single environment. Its root is the nearest parent directory you ran `treepot init` in, or else the nearest one containing a `Gemfile`, `go.mod`, `pyproject.toml`, `requirements.txt`, `cpanfile` or `package.json`.
- Everything `treepot` creates is labelled with the worktree's name, so `status`, `down` and `destroy` only ever touch that worktree's VMs and volumes.
- Test the harness itself: `test/detect_test.sh` and `test/dns_test.sh`. Neither starts a VM or changes the system.

## License

MIT. See [LICENSE](LICENSE).
