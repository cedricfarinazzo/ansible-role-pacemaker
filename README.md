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
- ✅ Install `pacemaker`, `pacemaker-cli-utils`, `pcs`, `psmisc` (and `sbd`), mask `pcsd` and its backend `pcsd-ruby` (nothing listens on TCP 2224); optionally mask `openipmi`, which `ipmitool` recommends and which fails at boot on a host without IPMI hardware
- ✅ With SBD: refuse a watchdog path that is no character device, or that a process other than `sbd` holds (the message names it); refuse SBD devices without an SBD header; write `/etc/default/sbd`; enable `sbd` with corosync
- ✅ Refuse, before any change, a new or changed SBD configuration (it restarts the stack, and a node's resources stop while it restarts) unless `pacemaker_allow_restart: true`; with it, restart the stack on every node, one node at a time, each back in a quorate partition with `sbd` running before the next (Pacemaker reads `have-watchdog` at its start)
- ✅ Start Pacemaker and wait until every node of the play, by its name in the running membership (`crm_node -n`), is online in a partition with quorum
- ✅ Read each wanted CIB value with `crm_attribute`, write only those that differ (a rerun changes nothing), from one node, and read them back
- ✅ In check mode, report each pending `pcsd` mask, CIB value and CIB element write or removal as changed, writing nothing: a converged cluster checks with `changed=0`

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
pacemaker_pcsd_masked: true                  # pcsd and pcsd-ruby masked; false leaves them as their package set them
pacemaker_openipmi_masked: false             # true masks openipmi.service (fails at boot without IPMI hardware)

pacemaker_sbd: true                          # false: no SBD (fence agents instead)
pacemaker_sbd_service: true                  # false: /etc/default/sbd written, sbd.service disabled
pacemaker_allow_restart: false               # true: restart corosync, pacemaker and sbd, one node at a time, when SBD is new or changed
pacemaker_sbd_watchdog_device: /dev/watchdog # a character device
pacemaker_sbd_watchdog_timeout: 5            # seconds, 1-9999
pacemaker_sbd_devices: []                    # up to 3 shared block devices; [] is diskless
pacemaker_sbd_options: {}                    # other SBD_* settings, e.g. {SBD_STARTMODE: clean}

pacemaker_cluster_properties: {}             # crm_config; a null value deletes the property
pacemaker_resource_defaults: {}              # rsc_defaults
pacemaker_op_defaults: {}                    # op_defaults
pacemaker_primitives: []                     # primitive resources, see "Resources and location constraints"
pacemaker_location_constraints: []           # location constraints, the same
pacemaker_cib_patch_retries: 3               # reruns from a fresh CIB copy when the patch is refused: the CIB changed meanwhile, 0-99
pacemaker_join_timeout: 120                  # seconds to wait for quorum, the controller, a node online

pacemaker_rejoin: false                      # true: a timer starts the stack again after a failed start
pacemaker_rejoin_interval: 60                # seconds between retries, 5-99999
pacemaker_rejoin_units:                      # .service or .target names started on a retry
  - pacemaker.service                        # add corosync-qdevice.service with a quorum device
pacemaker_rejoin_log_level_max: ""           # LogLevelMax= of the rejoin service, e.g. notice; empty logs all

# Rolling upgrade only (tasks_from: upgrade.yml), see "Rolling upgrade of the cluster packages"
pacemaker_upgrade_patterns: [corosync, libcorosync, ..., pacemaker, libpe-, ..., sbd, pcs, resource-agents, fence-agents]
pacemaker_upgrade_nodes: []                  # nodes that must be Online and out of standby; [] reads every member from the cluster
pacemaker_upgrade_timeout: 300               # seconds per wait: resources off the node, stack up, node Online, 1-99999
pacemaker_upgrade_poll_delay: 5              # seconds between polls, 1-999
pacemaker_systemd_after: []                  # units pacemaker starts after and stops before
pacemaker_systemd_wants: []                  # units pacemaker pulls in (Wants=) and starts after
pacemaker_systemd_requires: []               # units pacemaker needs (Requires=) and starts after
pacemaker_drbd_wait_resources: []            # DRBD resources whose local disk pacemaker waits for at start; [] no wait
pacemaker_drbd_wait_timeout: 90              # seconds, one deadline over every resource, 1-99999
pacemaker_drbd_wait_after: []                # units the wait starts after, e.g. the service that brings DRBD up
pacemaker_drbd_wait_resource_dir: ""         # wait only for resources with a <name>.res file here, e.g. /etc/drbd.d
```

Names are `[A-Za-z][A-Za-z0-9_-]*`; values printable, 1-255 characters; booleans are written `true`/`false`.

### Resources and location constraints

Primitives and location constraints are written from one node with `cibadmin`, never `pcs`: each element is read, created when it is missing, replaced when it differs, and read back, so a rerun changes nothing. Every create and replace of a run lands in one CIB update (built on a copy with `CIB_file`, applied with one `cibadmin --patch`): the scheduler never acts on a half-written configuration, e.g. a new `target-role` with the old locations. A CIB changed between the copy and the patch (a status update counts) refuses it (`cibadmin` exit 103): the copy, edits, diff and patch rerun from a fresh copy, up to `pacemaker_cib_patch_retries` times, 2 s apart, still one write; then the run fails ("the CIB changed during the run N times; rerun") with nothing written. Any other error fails at once.

```yaml
pacemaker_primitives:
  - id: web-ip                     # [A-Za-z][A-Za-z0-9_.-]*, unique across both lists
    class: ocf                     # ocf, systemd, lsb or service
    provider: heartbeat            # ocf only
    type: IPaddr2                  # checked with crm_resource --show-metadata before any write
    instance_attributes:           # agent parameters
      ip: 192.0.2.10
    meta_attributes:               # e.g. target-role, resource-stickiness
      resource-stickiness: 100
    operations:                    # one per name and interval
      - name: monitor
        interval: 10s
        timeout: 20s
        on_fail: restart           # optional: ignore, block, stop, restart, fence, standby, ask, demote, restart-container
    state: present                 # absent: stopped first, then removed with its location constraints
pacemaker_location_constraints:
  - id: web-ip-on-node-a
    resource: web-ip
    node: node-a.example.com       # a cluster node name
    score: INFINITY                # INFINITY, -INFINITY or an integer
    state: present                 # absent removes it
```

An entry dropped from a list is left in the CIB: only `state: absent` removes. The role writes the whole element, so a change made by hand to a managed element (e.g. `target-role` set with `crm_resource`) is undone on the next run. Child ids are derived: `<id>-instance_attributes`, `<id>-meta_attributes`, `<id>-<operation>-interval-<interval>`. A key the role does not know (group, clone, a misspelt name) is refused. Values are printable, never null, without quotes, `<`, `>` or `&`. Whether a change restarts the resource is Pacemaker's call: a changed parameter restarts it, a changed operation timeout does not. Groups, clones, colocation, order constraints and fencing resources are not managed.

### Diskless SBD

With `pacemaker_sbd_devices: []`, a node that loses quorum stops feeding the watchdog and resets after `pacemaker_sbd_watchdog_timeout`; the others consider it fenced after `stonith-watchdog-timeout`. The role refuses `stonith-watchdog-timeout` under twice `pacemaker_sbd_watchdog_timeout` (`-1` lets Pacemaker take twice), and refuses it without an explicit `stonith-timeout` longer than it (Pacemaker's default of 60 s may be shorter); both in seconds, before any change. Raising `pacemaker_sbd_watchdog_timeout` above a `stonith-watchdog-timeout` already in the CIB: raise the property in a run of its own first. The role refuses `stonith-watchdog-timeout` unless `pacemaker_sbd` and `pacemaker_sbd_service` are true with no devices: Pacemaker's controller exits when it is set and SBD does not run.

On a first run, with `pacemaker_allow_restart: true`, SBD is enabled and the stack restarted before the properties are written, so both land in one run.

### SBD with devices

The role never writes an SBD header (it erases the device). Initialise each device once, from one node: `sbd -d /dev/disk/by-id/<id> create`. The role refuses a device it cannot read a header from.

### Rejoin after a failed start

`sbd` starts with corosync, and its cluster servant waits for a running local corosync. When corosync waits for `network-online.target` at boot (the network is down, e.g. a node reset by its watchdog while isolated), sbd hits its start timeout first: corosync and pacemaker fail as a dependency, and systemd never retries that, even once the network is back. With `pacemaker_rejoin: true` the role installs `pacemaker-rejoin.timer`. Every `pacemaker_rejoin_interval` seconds, if `sbd`, `corosync` or `pacemaker` is **failed**, it runs `systemctl start --no-block` on `pacemaker_rejoin_units`. Fencing is unchanged: the stack starts through its normal unit chain, sbd and its watchdog first, and the node joins only by corosync membership and quorum. A clean `systemctl stop` leaves the units inactive, not failed, so the timer never undoes it. A start that fails for another reason (e.g. a stack restart by this role that failed) is retried the same way; a stack that fails again, e.g. from a bad config, is retried every interval forever, and `systemctl stop pacemaker-rejoin.timer` pauses it. `pacemaker_rejoin_log_level_max: notice` sets `LogLevelMax=notice` on the service: systemd's own info lines about it (Starting, Finished, skipped by its condition) are dropped too, so a healthy node logs nothing every interval; warnings and errors still reach the journal. The interval is at least 5 s: below it the oneshot service would hit systemd's start limit (5 starts in 10 s). Off by default; `false` removes the timer.

### Systemd ordering of pacemaker.service

Pacemaker stops every resource of a node when it stops, so its place in the boot and shutdown order decides what those resources still have around them. The role writes one drop-in per unit in `/etc/systemd/system/pacemaker.service.d/`:

| Variable | Drop-in | Content | When the unit fails or is missing |
|----------|---------|---------|-----------------------------------|
| `pacemaker_systemd_after` | `ansible-after-<unit>.conf` | `After=` | pacemaker starts anyway; the unit is not started for it |
| `pacemaker_systemd_wants` | `ansible-wants-<unit>.conf` | `After=` and `Wants=` | pacemaker starts anyway; starting pacemaker starts the unit |
| `pacemaker_systemd_requires` | `ansible-requires-<unit>.conf` | `After=` and `Requires=` | pacemaker does not start, and stops when the unit stops |

`After=` also reverses at shutdown: pacemaker stops, and so stops its resources, **before** the units it starts after. Each file is named by the full unit name, so `ups-monitor.service` and `ups-monitor.socket` get one each. A unit with `Wants=` that never finishes starting (e.g. a `systemd-cryptsetup@` unit waiting for a passphrase) still holds pacemaker back, by the `After=`. Unit names are checked (one token, a known unit type, no newline); a unit sits in one of the three lists only, and `pacemaker.service` in none.

A unit dropped from a list loses its drop-in. The role only ever writes and removes files named `ansible-after-*.conf`, `ansible-wants-*.conf`, `ansible-requires-*.conf` and `ansible-drbd-wait.conf` there: any other drop-in (an `override.conf` from `systemctl edit`, another tool's) is left alone. A change runs `systemctl daemon-reload` and never restarts pacemaker (that would stop the node's resources): it applies from pacemaker's next start.

### Waiting for DRBD before pacemaker starts

When resources run on DRBD (e.g. a VM or a filesystem on a replicated volume), pacemaker can start at boot before the DRBD resources are attached and in sync, and the resources fail on a missing or outdated disk. With `pacemaker_drbd_wait_resources` set, pacemaker's start first runs `/usr/local/sbin/pacemaker-drbd-wait` (an `ExecStartPre=` in `ansible-drbd-wait.conf`). It polls `drbdsetup status <resource>` every second until the **local** disk of every volume reads `disk:UpToDate`; a peer's `peer-disk:UpToDate` never counts. All resources share **one** deadline of `pacemaker_drbd_wait_timeout` seconds, never one each, and the wait never blocks the boot: a resource still not UpToDate at the deadline is logged to pacemaker's journal (`pacemaker-drbd-wait: <resource>: local disk not UpToDate after <n> s, starting pacemaker anyway`) and pacemaker starts. `TimeoutStartSec=` is set to the deadline plus 60 s, for pacemaker's own start after the wait.

- `pacemaker_drbd_wait_after`: units the wait starts after, e.g. the service that creates or attaches the DRBD resources on your hosts (`drbd.service`, or a storage manager's satellite service). No default: the role does not guess which one you run.
- `pacemaker_drbd_wait_resource_dir`: with one inventory list for every node, set it to the directory holding one `<resource>.res` file per resource configured on that host (e.g. `/etc/drbd.d`, or a storage manager's generated directory). A resource without its file is skipped on that host, without a poll.

An empty list removes the drop-in and the script.

### Removal

`pacemaker_state: absent` stops and disables Pacemaker and SBD, purges the packages and removes `/var/lib/pacemaker` and `/etc/default/sbd`, and the role's own `pacemaker.service` drop-ins and DRBD wait script (other drop-ins stay). `sbd` stops only with corosync, and a killed `sbd` lets the watchdog reset the node: when `sbd` runs, the role stops corosync on that node first and leaves it stopped. Corosync's configuration and the `pcsd` mask are left to whoever set them up.

### Stopping a node for maintenance

Never stop `pacemaker` alone while `sbd` and `corosync` run: Debian's `pacemaker.service` uses `KillMode=process`, so a forked Pacemaker child can outlive the stop, `sbd`'s Pacemaker servant never sees a clean shutdown, and the watchdog resets the node. Move the resources off, then stop Pacemaker and Corosync in one command (`sbd` stops with Corosync):

```bash
crm_attribute --node "$(crm_node -n)" --name standby --update on
crm_mon -1                          # wait until the node runs no resource
systemctl stop pacemaker corosync
```

Bring it back, then let it take resources again:

```bash
systemctl start corosync pacemaker  # sbd starts with corosync
systemctl start corosync-qdevice    # only on a node that uses a quorum device (it stopped with corosync)
crm_attribute --node "$(crm_node -n)" --name standby --delete
```

### Rolling upgrade of the cluster packages

`unattended-upgrades` or a plain `apt upgrade` upgrades the cluster packages with the stack running: a maintainer script stops or restarts part of it (`pacemaker` alone, `corosync` under a running `pacemaker`), which can lose resources or, with `sbd`, reset the node. The `upgrade.yml` entry point upgrades them behind the maintenance stop above, one node per run of its tasks. On each node it:

1. refuses, before any change, unless this node is Online and every other node (`pacemaker_upgrade_nodes`, or every member node `crm_mon --output-as=xml` lists) is Online and not in standby: never two nodes out at once;
2. runs `apt-get update` and lists the upgradable packages whose name a `pacemaker_upgrade_patterns` entry matches from its start; none: nothing else happens (no standby);
3. in check mode, names those packages (reported as changed) and stops there;
4. puts the node in standby and waits until no resource runs on it;
5. stops `pacemaker` and `corosync` in one command (never `pacemaker` alone) and checks none of `corosync`, `corosync-qdevice`, `pacemaker` and `sbd` still active;
6. runs `apt-get install --only-upgrade -o Dpkg::Options::=--force-confold` on exactly those packages, then checks `dpkg --audit` prints nothing;
7. starts `pacemaker` (and `corosync-qdevice` when it ran before), waits until every unit that ran before runs again;
8. deletes the standby attribute and waits until the node is Online.

Each wait is bounded by `pacemaker_upgrade_timeout`. Any failure stops there and leaves the node as it is (in standby, possibly stopped) for the operator; nothing is undone. Run it from a `serial: 1` play with `any_errors_fatal: true`, so a failure on one node stops the run before the next node stops: the peer check only sees the cluster, a parallel run would stop several nodes at once. Debian and Ubuntu (apt) only, with facts gathered; anything else is refused before any change. Only the matched packages are upgraded: run the rest of the host's upgrades as usual, with these patterns held back (e.g. in `Unattended-Upgrade::Package-Blacklist`).

```yaml
- name: Upgrade the cluster packages, one node at a time
  hosts: cluster
  become: true
  serial: 1
  any_errors_fatal: true
  tasks:
    - name: Upgrade this node
      ansible.builtin.include_role:
        name: cedricfarinazzo.pacemaker
        tasks_from: upgrade.yml
      vars:
        pacemaker_upgrade_timeout: 600
```

`--check` lists what each node would upgrade and changes nothing. A failed run leaves the node in standby: check `crm_mon -1r`, finish by hand (`dpkg --configure -a`, `systemctl start pacemaker`, `crm_attribute --node "$(crm_node -n)" --name standby --delete`), or fix the cause and rerun.

## 🎯 Usage Examples

### Two nodes and a quorum device, diskless SBD

Two votes plus the quorum device make three, so quorum means something and the watchdog alone can fence a node that loses it.

```yaml
- hosts: cluster          # node-a, node-b
  become: true
  roles:
    - role: cedricfarinazzo.corosync
      vars:
        corosync_cluster_name: example
        corosync_nodes:
          - {name: node-a, nodeid: 1, addrs: [192.0.2.11]}
          - {name: node-b, nodeid: 2, addrs: [192.0.2.12]}
        corosync_qdevice: true
        corosync_qdevice_host: qnetd.example.com
        corosync_qdevice_address: 192.0.2.10
    - role: cedricfarinazzo.pacemaker
      vars:
        pacemaker_sbd_watchdog_device: /dev/watchdog0
        pacemaker_sbd_watchdog_timeout: 10
        pacemaker_cluster_properties:
          stonith-enabled: true
          stonith-watchdog-timeout: 20     # at least twice the watchdog timeout
          no-quorum-policy: stop
```

### Two nodes and a quorum device, SBD off

For a cluster fenced by fence agents: no `sbd` package, no watchdog. Create the fence devices as cluster resources, outside this role.

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
        corosync_qdevice: true
        corosync_qdevice_host: qnetd.example.com
        corosync_qdevice_address: 192.0.2.10
    - role: cedricfarinazzo.pacemaker
      vars:
        pacemaker_sbd: false
        pacemaker_packages_extra:
          - fence-agents
        pacemaker_cluster_properties:
          no-quorum-policy: stop
        pacemaker_resource_defaults:
          resource-stickiness: 100
```

### SBD with a shared device

Initialise the device once first (see [SBD with devices](#sbd-with-devices)).

```yaml
- hosts: cluster
  become: true
  roles:
    - role: cedricfarinazzo.pacemaker
      vars:
        pacemaker_sbd_devices:
          - /dev/disk/by-id/example-sbd-device
        pacemaker_sbd_options:
          SBD_STARTMODE: clean
```

### Ordering after a UPS monitor, an encrypted volume and DRBD

```yaml
- hosts: cluster
  become: true
  roles:
    - role: cedricfarinazzo.pacemaker
      vars:
        # At shutdown on battery, pacemaker stops the resources before the UPS monitor goes
        pacemaker_systemd_after:
          - nut-monitor.service
        # The data volume is unlocked before pacemaker starts; a failed unlock still lets it start
        pacemaker_systemd_wants:
          - systemd-cryptsetup@data.service
        # The resources' filesystem: no pacemaker without it
        pacemaker_systemd_requires:
          - srv-data.mount
        # Each node waits up to 120 s in all for the resources configured on it
        pacemaker_drbd_wait_resources:
          - vm-web
          - vm-db
        pacemaker_drbd_wait_timeout: 120
        pacemaker_drbd_wait_after:
          - drbd.service
        pacemaker_drbd_wait_resource_dir: /etc/drbd.d
```

## 🧪 Testing

```bash
./run-tests.sh                     # default scenario, Debian 13
./run-tests.sh all                 # every distribution, in parallel
./run-tests.sh -s failure debian13 # the failure paths
tests/validate.test.sh             # the input checks: every rule, trailing and embedded newlines
tests/drbd-wait.test.sh            # the DRBD wait script on a stub drbdsetup
```

| Scenario | What it proves |
|----------|----------------|
| `default` | Three nodes: check mode (converged; a pending `pcsd-ruby` mask and pending properties reported, nothing written), idempotence, properties and defaults written lower case and read back on every node, a change and a delete written once, absent twice with Corosync still quorate |
| `qdevice` | Two nodes and a qnetd host: a node down leaves the other quorate, the rerun changes nothing |
| `sbd-off` | No SBD package or file, `have-watchdog` false; SBD turned on config-only, then off |
| `sbd-service` | Three nodes, sbd really running on a stand-in character device: the opt-in refused without `pacemaker_allow_restart` with nothing changed, timeouts that do not fit refused, `have-watchdog` true, a changed SBD timeout restarted one node at a time, `pcsd` left alone, an extra package, check mode and reruns change nothing |
| `rejoin` | Three nodes, sbd running: one node boots with its peers unreachable (iptables, a stand-in for `network-online` that waits for a peer), sbd's start times out, corosync and pacemaker fail as a dependency; once the network is back the node stays out with the timer off, and rejoins by itself with it on; a clean stop is not undone; with `LogLevelMax=notice` two runs log no journal line, emptied they log again; the timer removed when turned off |
| `resources` | Two nodes, a Dummy primitive with attributes and two operations, pinned to one node with INFINITY: Started there, the CIB matches the inputs, idempotence; an operation timeout changed writes that primitive only and does not restart it; both entries dropped from the input are left in the CIB with nothing changed; an id with a newline and an unknown agent refused before any write, CIB byte-identical; absent stops it, then deletes it and its location; absent twice changes nothing |
| `resources-multi` | Three nodes, three primitives (one with no attribute or operation) and INFINITY, -INFINITY and integer scores: each where its locations put it, the CIB matches the inputs, idempotence; check mode on the converged CIB reports nothing; a parameter change in check mode reports one replace and writes nothing; the same change writes one primitive and Pacemaker restarts it; a location moved (the primitive follows) and one set absent alone; a meta attribute edited by hand undone; two primitives removed together with their locations (reported first in check mode, nothing removed), the third kept; the removal again changes nothing |
| `resources-atomic` | Two nodes, a stopped primitive pinned to the first: started and moved to the second in one run (target-role and both locations changed); check mode reports the three replaces and writes nothing; one CIB update; a status update forced between the copy and the patch, the update retried from a fresh copy and written once; the primitive Started on the second node with no start or stop in the first node's operation history; a rerun changes nothing |
| `upgrade` | Three nodes, each with a local apt repository holding newer versions of two stand-in packages (one matching the pattern, one holding it but not at its start), a Dummy primitive preferring the first node: check mode names each node's package and changes nothing; a peer in standby, a peer offline and a listed node absent from the cluster each refused before any change, with the reason; one node upgraded alone: the primitive runs elsewhere meanwhile and comes back, the package upgraded with corosync and pacemaker inactive (its postinst records them), the other package untouched; the whole cluster: the node already upgraded gets no standby; a rerun changes nothing; a resource stop slower than the timeout fails with its message, the node left in standby with its stack running and nothing upgraded |
| `systemd` | Two nodes: a drop-in per unit (`.service` and `.socket` of one name apart) byte for byte, as `systemctl show` reads them; a stale role drop-in removed, the host's own drop-ins (`override.conf`, names outside the role's prefixes) kept; lists changed: drop-ins replaced and removed, systemd reloaded, pacemaker's main process unchanged; check mode reports and writes nothing; a real pacemaker start pulls in the wanted and required units and runs the wait on a stub `drbdsetup`: the resource without a `.res` file never polled, the UpToDate one silent, the one UpToDate only on its peer logged at the deadline and pacemaker started; everything off removes the role's drop-ins and script, then a rerun changes nothing; absent removes them too |
| `failure` | A control character, a rejoin log level with a trailing newline, a missing watchdog, a watchdog held by another process (named), an SBD device without a header, corosync stopped on one node: each fails with its message, no property and no SBD file changed |

A container has no watchdog: `sbd` runs on a stand-in character device that never resets the node, and the other scenarios run SBD config-only (`pacemaker_sbd_service: false`). The reset itself is only proven on hosts.

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
