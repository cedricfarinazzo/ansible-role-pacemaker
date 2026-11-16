# CLAUDE.md — ansible-role-pacemaker

Orientation for Claude Code sessions in this repository. `AGENTS.md` is a symlink to this file.

## Purpose

Public Ansible role `cedricfarinazzo.pacemaker` (Ansible Galaxy): Pacemaker on a running Corosync cluster, SBD fencing on a watchdog (diskless or with devices), cluster properties and resource/operation defaults set once from one node with `crm_attribute`, `pcsd` masked. Generic by design: no reference to any downstream project, host, user or network in code, defaults, docs or commit messages.

## Layout

- `defaults/main.yml` — every user-facing variable (`pacemaker_*`), with its generic default.
- `vars/main.yml` — package list, `/etc/default/sbd` path, the CIB sections and their inputs, crm_attribute's "not set" exit codes.
- `tasks/main.yml` — `validate.yml` (every input), then for `present`: `corosync.yml` (corosync active and quorate on every play host, before any change), `install.yml` (packages, `pcsd` masked, `openipmi` masked on opt-in), `restart_check.yml` (a stack restart refused on every node unless `pacemaker_allow_restart`, before any package), `sbd.yml` (watchdog checks, device headers, `/etc/default/sbd`, rolling stack restart) or `sbd_off.yml`, `service.yml` (pacemaker running, every node online), `rejoin.yml` (the opt-in rejoin timer, or its removal), `properties.yml` (read, write the differences, read back; run_once); for `absent`: `absent.yml`.
- `templates/sbd.j2` — `/etc/default/sbd`; `pacemaker-rejoin.{service,timer}.j2` — the timer that restarts a failed stack start.
- `meta/main.yml` — Galaxy metadata; `platforms` lists exactly what CI tests.
- `molecule/shared/` — `collections.yml` (the docker driver and the corosync role's release tag), `prepare.yml` (policy-rc.d removed, a stand-in watchdog character device, qnetd on the `qnetd` group), `converge.yml` (corosync role, then this one), `run.sh` and `recap.yml` (a rerun from the control node, its recap checked), `online.yml`.
- `molecule/default/` — three nodes, every distribution; reruns: no change, check mode, properties changed and deleted, absent twice.
- `molecule/qdevice/` — two nodes and a qnetd host; a node down and back.
- `molecule/sbd-off/` — no SBD; SBD on config-only and off again.
- `molecule/sbd-service/` — sbd running on a stand-in device: restart opt-in, timeouts, have-watchdog, one-node-at-a-time restart.
- `molecule/rejoin/` — three nodes, sbd running: a boot with the peers unreachable, the stack back by itself only with the timer; a clean stop not undone.
- `molecule/failure/` — failure paths on a two-node cluster, then verify nothing changed.
- `tests/validate.test.sh` — good and bad inputs against `tasks/validate.yml` on localhost.
- `run-tests.sh` / `Makefile` — local Molecule entry points; several distros or `all` run in parallel, one log each in `.molecule-logs/`.
- `requirements.yml` (none at runtime), `requirements-dev.txt` (controller tooling, exact pins), `package.json`, `bun.lock`, `.releaserc.json` (semantic-release only).
- `.github/workflows/` — `ci.yml` (lint, Galaxy description length, shellcheck, input tests, default on every distribution, the other scenarios on Debian 13), `pr-title.yml`, `release.yml`.
- `renovate.json` — dependency updates.

## Conventions

- **Conventional Commits** (`conventionalcommits` preset). `feat:` → minor, `fix:` / `perf:` → patch, `!` or `BREAKING CHANGE:` → major; `docs:` / `ci:` / `chore:` / `test:` / `refactor:` / `build:` release nothing. A squash merge lands the **PR title** (`pr-title.yml` checks it).
- **Breaking = a consumer must act:** dropping a platform, renaming or removing a variable, changing a default that changes fencing.
- **Tags are bare semver** (`1.2.3`), notes in GitHub Releases; no `CHANGELOG.md`.
- **No ruleset or branch protection on `main`:** a ruleset blocks semantic-release. Changes still go through a PR with green CI.
- **Variables:** every user-facing variable starts with `pacemaker_`, is defined in `defaults/main.yml`, asserted in `tasks/validate.yml` (with a case in `tests/validate.test.sh`) and documented in `README.md` in the same PR. Internal facts start with `__pacemaker_`.
- **Every input checked before any change.** Every regex ends in `\Z`, never `$`; classes hold no control character; bad cases feed trailing and embedded newlines.
- **No stack restart without `pacemaker_allow_restart`;** refused on every node before any package or file changes.
- **Fencing timeouts checked in `validate.yml`:** `stonith-watchdog-timeout` at least twice the SBD timeout, `stonith-timeout` longer.
- **No change before Corosync is checked on every node:** a node down or unreachable stops the role everywhere, so no node writes the CIB.
- **CIB writes are run_once and only for values that differ;** each is read back. No `pcs` command that needs `pcsd`.
- **The rejoin timer only acts on a failed sbd, corosync or pacemaker,** never on a clean stop, and only through the normal unit chain (sbd first, corosync membership and quorum).
- **The role never writes an SBD device header** (`sbd create` erases the device).
- **Examples never copy a real deployment:** `example.com` names, documentation addresses.
- **GitHub Actions pinned by full commit SHA**, tag in a trailing comment. Exact pins for tooling; `renovate.json` identical in the sibling roles: change them together.
- **License:** MIT.

## Supported platforms

`meta/main.yml` `platforms`, the CI matrix, the `README.md` table, `run-tests.sh --help` and the `Makefile` list the same set.

## How releases work

1. A PR is squash-merged into `main` with a Conventional Commit title.
2. When `ci.yml` passes on the push to `main`, `release.yml` runs `bunx semantic-release`: tag, GitHub Release, comments on released PRs.
3. Ansible Galaxy imports each new tag by itself.

## Commands

- Lint: `source .venv/bin/activate && yamllint . && ansible-lint && shellcheck run-tests.sh tests/*.sh molecule/shared/*.sh`
- Input tests: `tests/validate.test.sh`
- Molecule: `./run-tests.sh debian13`, `./run-tests.sh -s <scenario> debian13`, `./run-tests.sh all`

## Gotchas

- Debian's and Ubuntu's postinst start pacemaker at install; with corosync stopped, that start pulls corosync up (Requires=): `corosync.yml` runs before `install.yml`.
- Pacemaker's controller exits when `stonith-watchdog-timeout` is non-zero and SBD does not run: `validate.yml` refuses it without diskless SBD running.
- `sbd.service` is PartOf corosync: it stops only with corosync, and Pacemaker reads `have-watchdog` at its start, so an SBD change restarts the whole stack (one node at a time, `throttle: 1`).
- `crm_attribute --query` of an unset value exits 105 (CRM_EX_NOSUCH; 6 on older Pacemaker): both mean "not set".
- `item.values` in Jinja is the dict method, not a key: the CIB set's key is `settings`.
- A container has no watchdog: `sbd` runs on a `mknod` character device (`/dev/null`'s numbers) with `sbd-service`; the other scenarios use `pacemaker_sbd_service: false`.
- Docker's 64 MB `/dev/shm` fills with corosync's and pacemaker's libqb buffers ("Cannot initialise VOTEQUORUM service", "No space left on device" in corosync's journal): every platform sets `shm_size: 512m`.

## Self Improvement Loop

Keep `CLAUDE.md` and `README.md` accurate, in the same PR as the change. Update when a variable, platform, file or convention changes, or a trap costs a debugging round (one Gotchas line: symptom, cause, fix). New fact replaces the old clause; never append a changelog.
