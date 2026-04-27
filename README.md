# Ubuntu 26 Developer Setup

This project installs and verifies a full developer environment on Ubuntu 26.x.

It is useful when you want a new Ubuntu machine to have the same tools every time, without manually installing each package. The setup is split into groups, so you can run everything or only the part you need.

## When This Helps Developers

This setup helps when:

- You bought or created a new Ubuntu machine and want it ready for development quickly.
- You reinstalled Ubuntu and want to restore the same tools.
- You manage more than one developer machine and want the same base setup everywhere.
- You want to install only one tool group, such as Docker, Node.js, PostgreSQL, or editors.
- You want to verify whether required tools are already installed.
- You want to add future setup groups without editing the main `setup.sh` runner.

## What It Installs

The setup is organized by group:

- `base`: system basics, apt upgrade, Git, curl, wget, build tools, certificates, locale tools.
- `dev-libraries`: common native build libraries and headers.
- `ssh`: OpenSSH client and server.
- `python`: Python, pip, venv, pipx.
- `node`: NVM and latest Node.js LTS.
- `docker`: Docker Engine, Docker Compose plugin, docker user group setup.
- `dotnet`: latest available .NET SDK.
- `postgres-pgadmin`: PostgreSQL, PostgreSQL client/dev files, pgAdmin.
- `tools`: htop, neovim, tmux, fzf, tree, network tools, shellcheck, cron, fail2ban, ufw.
- `editors`: VS Code and Cursor.
- `chrome-postman`: Google Chrome and Postman.
- `ai-tools`: OpenCode.
- `cleanup`: apt autoremove and autoclean.

## Basic Usage

Run everything:

```bash
sudo ./setup.sh
```

List groups:

```bash
./setup.sh --list
```

Run selected groups:

```bash
sudo ./setup.sh --only docker,node,python
```

Skip selected groups:

```bash
sudo ./setup.sh --skip editors,ai-tools
```

Verify without installing:

```bash
./setup.sh --verify
```

Setup and verification output is saved automatically under `logs/`:

```text
logs/setup-YYYYmmdd-HHMMSS.log
```

You can override the log location with `SETUP_LOG_DIR` or `SETUP_LOG_FILE`.

Run one group directly:

```bash
sudo ./groups/70-postgres-pgadmin.sh
```

To add a new group, create a new `groups/*.sh` file and call `register_group`. `setup.sh` discovers it automatically.

## Adding A New Group

Create a new file in `groups/`, for example:

```text
groups/85-my-tools.sh
```

Each group should define an install function, a verify function, and register itself:

```bash
install_my_tools() {
  apt_install_packages example-package
}

verify_my_tools() {
  check_required_cmd "example tool" example-command
}

register_group "my-tools" "My custom tools" install_my_tools verify_my_tools
```

After that, the group is available automatically:

```bash
./setup.sh --list
sudo ./setup.sh --only my-tools
```

## Design

`setup.sh` is only the runner. Shared logic lives in `lib/common.sh`. Each install area lives in its own file under `groups/`.

This makes the setup easier to maintain because adding a new package group does not require changing the main script.
