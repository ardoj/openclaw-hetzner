# openclaw-hetzner

One command to provision a hardened Hetzner Cloud VPS and run an
[OpenClaw](https://docs.openclaw.ai) gateway on it in Docker, with Telegram as
the chat channel and DeepSeek as the model provider.

## What you get

- A Hetzner Cloud server (default: `cx23`, 2 vCPU / 4 GB, Ubuntu 24.04, Helsinki).
- A Hetzner firewall and `ufw` that allow inbound SSH and ping only.
- SSH access by public key only, as the admin user `claw`. Root login and
  password login are disabled.
- `fail2ban` and unattended security upgrades.
- OpenClaw running from the official image `ghcr.io/openclaw/openclaw:latest`
  under Docker Compose, restarted automatically.
- The dashboard published only on the server's loopback interface, so it is
  reachable only through an SSH tunnel.

## Requirements

On your local machine:

- [`hcloud`](https://github.com/hetznercloud/cli) (Hetzner Cloud CLI)
- `jq`, `ssh`, `scp`, `ssh-keygen`
- An SSH key pair (`ssh-keygen -t ed25519` if you don't have one)

Accounts and keys:

| Variable | Where to get it |
| --- | --- |
| `HCLOUD_TOKEN` | Hetzner Cloud Console → your project → Security → API tokens (Read & Write) |
| `DEEPSEEK_API_KEY` | [platform.deepseek.com](https://platform.deepseek.com) → API keys (the account needs a positive balance) |
| `TELEGRAM_BOT_TOKEN` | [@BotFather](https://t.me/BotFather) in Telegram → `/newbot` |

## Quick start

```bash
cp .env.example .env
$EDITOR .env          # fill in the three keys above
./claw up
```

`./claw up` creates the server, waits for it to finish its first-boot setup,
installs OpenClaw and starts the gateway. It takes a few minutes.

Then pair your Telegram account:

1. Send any message to your bot in Telegram. It replies with a pairing code.
2. Approve the code:

   ```bash
   ./claw approve <code>
   ```

3. Message the bot again; it now answers.

## Commands

| Command | What it does |
| --- | --- |
| `./claw up` | Create the server if it is missing, then install or refresh OpenClaw |
| `./claw deploy` | Re-run the install on the existing server (after changing `.env` or `remote/`) |
| `./claw update` | Pull the latest OpenClaw image and restart the gateway |
| `./claw status` | Show server and container status |
| `./claw logs` | Follow the gateway logs |
| `./claw ssh [cmd...]` | Open a shell on the server, or run a command |
| `./claw tunnel` | Forward the dashboard to `http://127.0.0.1:18789` |
| `./claw token` | Print the gateway token used to log in to the dashboard |
| `./claw cli <args...>` | Run an `openclaw` CLI command on the server |
| `./claw pairing` | List pending Telegram pairing requests |
| `./claw approve <code>` | Approve a Telegram pairing code |
| `./claw destroy` | Delete the server and its firewall (asks for confirmation) |

### Dashboard

```bash
./claw tunnel     # leave running
./claw token      # in another terminal
```

Open `http://127.0.0.1:18789` and log in with the token.

### Changing the model

Onboarding selects `deepseek/deepseek-v4-pro`. To switch, for example to the
cheaper flash model:

```bash
./claw cli config set agents.defaults.model.primary deepseek/deepseek-v4-flash
```

## Configuration

Everything is set in `.env`. Besides the three required keys:

| Variable | Default | Purpose |
| --- | --- | --- |
| `SSH_PUBLIC_KEY_FILE` | `~/.ssh/id_ed25519.pub` | Public key allowed to log in |
| `SERVER_NAME` | `openclaw` | Hetzner server name (the firewall is `<name>-fw`) |
| `SERVER_TYPE` | `cx23` | Hetzner server type |
| `SERVER_LOCATION` | `hel1` | Hetzner location |
| `SERVER_IMAGE` | `ubuntu-24.04` | OS image |
| `ADMIN_USER` | `claw` | Login user on the server |
| `OPENCLAW_IMAGE` | `ghcr.io/openclaw/openclaw:latest` | OpenClaw image to run |
| `OPENCLAW_TZ` | `UTC` | Time zone inside the container |

## Layout

```
claw                 Local entry point: provisioning and day-to-day commands
.env.example         Template for .env
remote/compose.yml   Docker Compose file used on the server
remote/install.sh    Install script that runs on the server
```

On the server:

```
~/openclaw/                        compose.yml, install.sh, .env (secrets, mode 600)
~/.openclaw/                       OpenClaw config, state and workspace
~/.openclaw-auth-profile-secrets/  OpenClaw auth profile secrets
```

## Security notes

- `.env` holds your Hetzner token and API keys. It is gitignored; never commit it.
- Secrets are sent to the server over SSH after it boots, not through
  cloud-init, because cloud-init user data stays readable on the server.
- The DeepSeek key and gateway token live only in `~/openclaw/.env` on the
  server. The Telegram bot token is also written to OpenClaw's config file.
- The admin user has passwordless `sudo` and is in the `docker` group.
- Log in as `claw`, not `root`: `ssh root@<ip>` is rejected by design.

## Troubleshooting

**`Permission denied (publickey)` when using SSH.** You are probably logging in
as `root`. Use `./claw ssh` or `ssh claw@<ip>`.

**The bot replies with a billing error.** The DeepSeek account has no balance.
Top it up, then restart the gateway if the error persists:

```bash
./claw ssh 'cd ~/openclaw && docker compose restart openclaw-gateway'
```

**Logs show `state ownership ... could not be verified`.** Something ran the
OpenClaw CLI in a separate container while the gateway was running, which
removes the gateway's state lock. Restart the gateway (command above), and
always use `./claw cli`, which runs the CLI inside the gateway container.
Never use `docker compose run` against a running gateway.

**First-boot setup failed.** Inspect the cloud-init log:

```bash
./claw ssh sudo cat /var/log/cloud-init-output.log
```

**`unknown server type`.** Hetzner renames server types from time to time. Run
`hcloud server-type list` and set `SERVER_TYPE` in `.env`.

## Removing everything

```bash
./claw destroy
```

This deletes the server, all OpenClaw data on it, and the firewall. The SSH key
uploaded to Hetzner is kept.
