# 🛡️ Ansible Role: pacemaker

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Ansible Galaxy](https://img.shields.io/badge/Ansible%20Galaxy-cedricfarinazzo.pacemaker-blue)](https://galaxy.ansible.com/cedricfarinazzo/pacemaker)

> **[Pacemaker](https://clusterlabs.org/pacemaker/) on a running Corosync cluster: SBD fencing on a watchdog (diskless or with shared devices), cluster properties, resource and operation defaults set once from one node with the local CIB tools, `pcsd` masked.**

The role never builds the Corosync cluster: run [`cedricfarinazzo.corosync`](https://github.com/cedricfarinazzo/ansible-role-corosync) (or your own) first, in the same play. It uses no `pcs` command that needs `pcsd` (cluster setup, host auth, node add); the `pcs` CLI stays installed for read-only `pcs status`. Resources are out of its scope.

## 🚀 Quick Start

Install from Ansible Galaxy ([cedricfarinazzo.pacemaker](https://galaxy.ansible.com/cedricfarinazzo/pacemaker), [cedricfarinazzo.corosync](https://galaxy.ansible.com/cedricfarinazzo/corosync)), pinned to a release:

```yaml
# requirements.yml
roles:
  - name: cedricfarinazzo.pacemaker
    version: 1.0.0
  - name: cedricfarinazzo.corosync
    version: 1.0.0
```

```bash
ansible-galaxy role install -r requirements.yml
```

```yaml
- hosts: cluster
  become: true
  roles:
    - role: cedricfarinazzo.corosync
      vars:
        corosync_cluster_name: example
        corosync_nodes:
          - {name: node-a, nodeid: 1, addrs: [192.0.2.11]}
          - {name: node-b, nodeid: 2, addrs: [192.0.2.12]}
          - {name: node-c, nodeid: 3, addrs: [192.0.2.13]}
    - role: cedricfarinazzo.pacemaker
      vars:
        pacemaker_sbd_watchdog_device: /dev/watchdog0
        pacemaker_sbd_watchdog_timeout: 10
        pacemaker_cluster_properties:
          stonith-enabled: true
          stonith-watchdog-timeout: 20
          no-quorum-policy: stop
```

The role will:
- ✅ Check every input before any change (anchored patterns, no control character in any value)
- ✅ Check that corosync runs and is quorate on every node of the play, before any package, service or CIB change: one node down or unreachable stops the role on every node, with nothing changed
- ✅ Install `pacemaker`, `pacemaker-cli-utils`, `pcs`, `psmisc` (and `sbd`), mask `pcsd` (nothing listens on TCP 2224)
- ✅ With SBD: refuse a watchdog path that is no character device, or that a process other than `sbd` holds (the message names it); refuse SBD devices without an SBD header; write `/etc/default/sbd`; enable `sbd` with corosync
- ✅ Restart the cluster stack on a new or changed SBD configuration, one node at a time, each back in a quorate partition with `sbd` running before the next (Pacemaker reads `have-watchdog` at its start)
- ✅ Start Pacemaker and wait until every node of the play, by its name in the running membership (`crm_node -n`), is online in a partition with quorum
- ✅ Read each wanted CIB value with `crm_attribute`, write only those that differ (a rerun changes nothing), from one node, and read them back

## 📋 Requirements

- Ansible 2.15+, `become: true`
- A running, quorate Corosync 3 cluster on every host of the play
- Diskless SBD needs quorum to mean something: three votes or more (three nodes, or two and a quorum device), never `two_node`
- A watchdog driver loaded, and no other consumer of the device (watchdog daemon, systemd's `RuntimeWatchdogSec`)

### Supported Distributions

| Distribution | Version | Status |
|--------------|---------|--------|
| Debian       | 13 (trixie) | ✅ Tested |
| Ubuntu       | 24.04 (noble) | ✅ Tested |
| Ubuntu       | 26.04 (resolute) | ✅ Tested |

The scenarios beyond the default one run on Debian 13.

## ⚙️ Configuration

```yaml
pacemaker_state: present                     # absent: stop, purge, remove the CIB and /etc/default/sbd
pacemaker_packages_extra: []                 # e.g. fence-agents
pacemaker_pcsd_masked: true                  # false leaves pcsd as its package set it

pacemaker_sbd: true                          # false: no SBD (fence agents instead)
pacemaker_sbd_service: true                  # false: /etc/default/sbd written, sbd.service disabled
pacemaker_sbd_watchdog_device: /dev/watchdog # a character device
pacemaker_sbd_watchdog_timeout: 5            # seconds, 1-9999
pacemaker_sbd_devices: []                    # up to 3 shared block devices; [] is diskless
pacemaker_sbd_options: {}                    # other SBD_* settings, e.g. {SBD_STARTMODE: clean}

pacemaker_cluster_properties: {}             # crm_config; a null value deletes the property
pacemaker_resource_defaults: {}              # rsc_defaults
pacemaker_op_defaults: {}                    # op_defaults
pacemaker_join_timeout: 120                  # seconds to wait for quorum, the controller, a node online
```

Names are `[A-Za-z][A-Za-z0-9_-]*`; values printable, 1-255 characters; booleans are written `true`/`false`.

### Diskless SBD

With `pacemaker_sbd_devices: []`, a node that loses quorum stops feeding the watchdog and resets after `pacemaker_sbd_watchdog_timeout`; the others consider it fenced after `stonith-watchdog-timeout`. Set that property to at least twice the watchdog timeout. The role refuses `stonith-watchdog-timeout` unless `pacemaker_sbd` and `pacemaker_sbd_service` are true with no devices: Pacemaker's controller exits when it is set and SBD does not run.

On a first run SBD is enabled and the stack restarted before the properties are written, so both land in one run.

### SBD with devices

The role never writes an SBD header (it erases the device). Initialise each device once, from one node: `sbd -d /dev/disk/by-id/<id> create`. The role refuses a device it cannot read a header from.

### Removal

`pacemaker_state: absent` stops and disables Pacemaker and SBD, purges the packages and removes `/var/lib/pacemaker` and `/etc/default/sbd`. `sbd` stops only with corosync, and a killed `sbd` lets the watchdog reset the node: when `sbd` runs, the role stops corosync on that node first and leaves it stopped. Corosync's configuration and the `pcsd` mask are left to whoever set them up.

## 🧪 Testing

```bash
./run-tests.sh                     # default scenario, Debian 13
./run-tests.sh all                 # every distribution, in parallel
./run-tests.sh -s failure debian13 # the failure paths
tests/validate.test.sh             # the input checks
```

| Scenario | What it proves |
|----------|----------------|
| `default` | Three nodes: check mode, idempotence, properties and defaults written lower case and read back on every node, a change and a delete written once, absent twice with Corosync still quorate |
| `qdevice` | Two nodes and a qnetd host: a node down leaves the other quorate, the rerun changes nothing |
| `sbd-off` | No SBD package or file, `have-watchdog` false; SBD turned on config-only, then off |
| `failure` | A control character, a missing watchdog, a watchdog held by another process (named), an SBD device without a header, corosync stopped on one node: each fails with its message, no property and no SBD file changed |

A container has no watchdog: the scenarios run SBD config-only (`pacemaker_sbd_service: false`) on a stand-in character device. The stack restart on SBD, and the reset itself, are only proven on hosts.

## 🚢 Releases

Once CI passes on `main`, [semantic-release](https://github.com/semantic-release/semantic-release) cuts the version from [Conventional Commits](https://www.conventionalcommits.org/): `fix:` releases a patch, `feat:` a minor, a `!` or `BREAKING CHANGE:` footer a major. A squash merge lands the pull request title (checked in CI), a merge commit lands each branch commit, so both must follow the convention. Each release gets a bare semver tag (`1.2.3`) and GitHub release notes; Ansible Galaxy imports the new tag from the repository. [Renovate](https://docs.renovatebot.com/) keeps the tooling and the pinned GitHub Actions up to date.

## 📦 Dependencies

- ✅ **Ansible Core Modules** (built-in); no collection
- ✅ **OS packages** `pacemaker`, `pacemaker-cli-utils`, `pcs`, `psmisc`, `sbd` (with SBD)
- ✅ **A running Corosync cluster**, e.g. from [cedricfarinazzo.corosync](https://galaxy.ansible.com/cedricfarinazzo/corosync)

## 👥 Authors & Contributors

**Cédric Farinazzo** ([@cedricfarinazzo](https://github.com/cedricfarinazzo)) - *Author and Maintainer*

## 📄 License

MIT, see [LICENSE](LICENSE).
