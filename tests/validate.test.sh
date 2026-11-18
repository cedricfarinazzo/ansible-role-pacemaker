#!/usr/bin/env bash
# The role's input checks: each bad input fails before anything changes, the good ones pass.
# Runs tasks/validate.yml on localhost; needs ansible-playbook on PATH, no host.
set -euo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir "$WORK/roles"
ln -s "$REPO" "$WORK/roles/pacemaker"
cat > "$WORK/play.yml" <<'PLAY'
- name: Validate pacemaker inputs
  hosts: localhost
  gather_facts: false
  tasks:
    - name: Validate
      ansible.builtin.include_role:
        name: pacemaker
        tasks_from: validate.yml
PLAY
fails=0
run() { ANSIBLE_ROLES_PATH=$WORK/roles ansible-playbook -i localhost, -c local -e "$1" "$WORK/play.yml" > "$WORK/out" 2>&1; }
good() { if run "$2"; then echo "ok   accepted: $1"; else echo "FAIL rejected a good input: $1" >&2; tail -5 "$WORK/out" >&2; fails=$((fails + 1)); fi; }
# Rejected by an assert, never by a templating crash: that would pass for the wrong reason.
bad() {
  if run "$2"; then echo "FAIL accepted: $1" >&2; fails=$((fails + 1))
  elif grep -qE '"assertion"|Action failed: ' "$WORK/out"; then echo "ok   rejected: $1"
  else echo "FAIL failed without an assertion: $1" >&2; grep -m3 -E 'ERROR|fatal' "$WORK/out" >&2; fails=$((fails + 1)); fi
}


# Each bad case changes one input of a good set (JSON objects merge left to right in -e)
good "the defaults" '{}'
good "absent" '{"pacemaker_state": "absent"}'
good "diskless SBD with a watchdog timeout and properties" '{"pacemaker_sbd_watchdog_device": "/dev/watchdog0", "pacemaker_sbd_watchdog_timeout": 35, "pacemaker_cluster_properties": {"stonith-watchdog-timeout": 70, "stonith-timeout": "90s", "no-quorum-policy": "stop", "stonith-enabled": true}}'
good "SBD devices and options" '{"pacemaker_sbd_devices": ["/dev/disk/by-id/scsi-example-1", "/dev/disk/by-id/scsi-example-2"], "pacemaker_sbd_options": {"SBD_STARTMODE": "clean", "SBD_DELAY_START": "no"}}'
good "openipmi masked" '{"pacemaker_openipmi_masked": true}'
good "SBD off, pcsd left alone, extra packages" '{"pacemaker_sbd": false, "pacemaker_pcsd_masked": false, "pacemaker_packages_extra": ["fence-agents"]}'
good "SBD config only" '{"pacemaker_sbd_service": false}'
good "defaults, a deleted property" '{"pacemaker_resource_defaults": {"resource-stickiness": 100}, "pacemaker_op_defaults": {"timeout": "60s"}, "pacemaker_cluster_properties": {"cluster-recheck-interval": null}}'
good "stonith-watchdog-timeout twice the watchdog timeout, in seconds, a longer stonith-timeout" '{"pacemaker_sbd_watchdog_timeout": 35, "pacemaker_cluster_properties": {"stonith-watchdog-timeout": "70s", "stonith-timeout": 71}}'
good "stonith-watchdog-timeout -1, Pacemaker takes twice" '{"pacemaker_sbd_watchdog_timeout": 35, "pacemaker_cluster_properties": {"stonith-watchdog-timeout": -1, "stonith-timeout": "90s"}}'
good "a restart allowed" '{"pacemaker_allow_restart": true}'
good "a watchdog timeout of 0 without SBD" '{"pacemaker_sbd": false, "pacemaker_cluster_properties": {"stonith-watchdog-timeout": 0}}'
good "rejoin on, a quorum device unit" '{"pacemaker_rejoin": true, "pacemaker_rejoin_interval": 30, "pacemaker_rejoin_units": ["pacemaker.service", "corosync-qdevice.service"]}'
bad "rejoin as a string" '{"pacemaker_rejoin": "yes"}'
good "a rejoin interval of 5" '{"pacemaker_rejoin_interval": 5}'
bad "a rejoin interval of 4" '{"pacemaker_rejoin_interval": 4}'
bad "a rejoin interval of 0" '{"pacemaker_rejoin_interval": 0}'
bad "a rejoin interval with a trailing newline" '{"pacemaker_rejoin_interval": "60\n"}'
bad "a rejoin interval with a unit" '{"pacemaker_rejoin_interval": "60s"}'
bad "rejoin units as a string" '{"pacemaker_rejoin_units": "pacemaker.service"}'
bad "no rejoin unit" '{"pacemaker_rejoin_units": []}'
bad "a rejoin unit that is no service" '{"pacemaker_rejoin_units": ["pacemaker"]}'
bad "a rejoin unit with a trailing newline" '{"pacemaker_rejoin_units": ["pacemaker.service\n"]}'
bad "a rejoin unit with an embedded newline" '{"pacemaker_rejoin_units": ["pacemaker.service\nExecStart=/bin/sh"]}'
bad "a rejoin unit with a space" '{"pacemaker_rejoin_units": ["pacemaker.service reboot.target"]}'
bad "an unknown state" '{"pacemaker_state": "latest"}'
bad "an extra package with a trailing newline" '{"pacemaker_packages_extra": ["fence-agents\n"]}'
bad "an extra package with an embedded newline" '{"pacemaker_packages_extra": ["fence\nagents"]}'
bad "extra packages as a string" '{"pacemaker_packages_extra": "fence-agents"}'
bad "pcsd masked as a string" '{"pacemaker_pcsd_masked": "yes"}'
bad "openipmi masked as a string" '{"pacemaker_openipmi_masked": "false"}'
bad "sbd as a string" '{"pacemaker_sbd": "yes"}'
bad "sbd service as a string" '{"pacemaker_sbd_service": "no"}'
bad "a join timeout of 0" '{"pacemaker_join_timeout": 0}'
bad "a join timeout with a trailing newline" '{"pacemaker_join_timeout": "60\n"}'
bad "a relative watchdog path" '{"pacemaker_sbd_watchdog_device": "dev/watchdog"}'
bad "a watchdog path with a trailing newline" '{"pacemaker_sbd_watchdog_device": "/dev/watchdog\n"}'
bad "a watchdog path with an embedded newline" '{"pacemaker_sbd_watchdog_device": "/dev/watchdog\nSBD_DEVICE=/dev/sda"}'
bad "a watchdog path with a space" '{"pacemaker_sbd_watchdog_device": "/dev/watch dog"}'
bad "a watchdog timeout of 0" '{"pacemaker_sbd_watchdog_timeout": 0}'
bad "a watchdog timeout with a trailing newline" '{"pacemaker_sbd_watchdog_timeout": "5\n"}'
bad "a watchdog timeout with a unit" '{"pacemaker_sbd_watchdog_timeout": "5s"}'
bad "four SBD devices" '{"pacemaker_sbd_devices": ["/dev/a", "/dev/b", "/dev/c", "/dev/d"]}'
bad "an SBD device with a semicolon" '{"pacemaker_sbd_devices": ["/dev/a;/dev/b"]}'
bad "an SBD device with a trailing newline" '{"pacemaker_sbd_devices": ["/dev/a\n"]}'
bad "SBD devices as a string" '{"pacemaker_sbd_devices": "/dev/a"}'
bad "an SBD option not named SBD_" '{"pacemaker_sbd_options": {"WATCHDOG": "x"}}'
bad "an SBD option name with a trailing newline" '{"pacemaker_sbd_options": {"SBD_STARTMODE\n": "clean"}}'
bad "an SBD option that overrides an input" '{"pacemaker_sbd_options": {"SBD_WATCHDOG_DEV": "/dev/other"}}'
bad "an SBD option value with a newline" '{"pacemaker_sbd_options": {"SBD_STARTMODE": "clean\nSBD_DEVICE=/dev/sda"}}'
bad "an SBD option value with a quote" '{"pacemaker_sbd_options": {"SBD_STARTMODE": "clean\" x=\""}}'
# shellcheck disable=SC2016 # a literal $( ) is the bad input
bad "an SBD option value with a dollar" '{"pacemaker_sbd_options": {"SBD_STARTMODE": "$(reboot)"}}'
bad "SBD options as a list" '{"pacemaker_sbd_options": ["SBD_STARTMODE"]}'
bad "a property with a trailing newline" '{"pacemaker_cluster_properties": {"no-quorum-policy": "stop\n"}}'
bad "a property with an embedded newline" '{"pacemaker_cluster_properties": {"no-quorum-policy": "st\nop"}}'
bad "a property with a CR" '{"pacemaker_cluster_properties": {"no-quorum-policy": "st\rop"}}'
bad "a property with a tab" '{"pacemaker_cluster_properties": {"no-quorum-policy": "st\top"}}'
bad "an empty property value" '{"pacemaker_cluster_properties": {"no-quorum-policy": ""}}'
bad "a property name with a trailing newline" '{"pacemaker_cluster_properties": {"no-quorum-policy\n": "stop"}}'
bad "a property name with a space" '{"pacemaker_cluster_properties": {"no quorum": "stop"}}'
bad "properties as a list" '{"pacemaker_cluster_properties": ["no-quorum-policy"]}'
bad "a resource default with a newline" '{"pacemaker_resource_defaults": {"resource-stickiness": "1\n"}}'
bad "an op default name starting with a dash" '{"pacemaker_op_defaults": {"-timeout": "60s"}}'
bad "a restart allowance as a string" '{"pacemaker_allow_restart": "yes"}'
bad "stonith-watchdog-timeout under twice the watchdog timeout" '{"pacemaker_sbd_watchdog_timeout": 35, "pacemaker_cluster_properties": {"stonith-watchdog-timeout": 69, "stonith-timeout": "90s"}}'
bad "stonith-watchdog-timeout -1 with a stonith-timeout under twice the watchdog timeout" '{"pacemaker_sbd_watchdog_timeout": 35, "pacemaker_cluster_properties": {"stonith-watchdog-timeout": -1, "stonith-timeout": "70s"}}'
bad "stonith-timeout equal to stonith-watchdog-timeout" '{"pacemaker_sbd_watchdog_timeout": 35, "pacemaker_cluster_properties": {"stonith-watchdog-timeout": 70, "stonith-timeout": "70s"}}'
bad "stonith-timeout under stonith-watchdog-timeout" '{"pacemaker_sbd_watchdog_timeout": 35, "pacemaker_cluster_properties": {"stonith-watchdog-timeout": 70, "stonith-timeout": 30}}'
bad "stonith-timeout left to Pacemaker's default" '{"pacemaker_sbd_watchdog_timeout": 35, "pacemaker_cluster_properties": {"stonith-watchdog-timeout": 70}}'
bad "stonith-watchdog-timeout with a unit other than seconds" '{"pacemaker_sbd_watchdog_timeout": 35, "pacemaker_cluster_properties": {"stonith-watchdog-timeout": "2min", "stonith-timeout": "300s"}}'
bad "stonith-timeout with a unit other than seconds" '{"pacemaker_sbd_watchdog_timeout": 35, "pacemaker_cluster_properties": {"stonith-watchdog-timeout": 70, "stonith-timeout": "2min"}}'
bad "a watchdog timeout without SBD" '{"pacemaker_sbd": false, "pacemaker_cluster_properties": {"stonith-watchdog-timeout": 10}}'
bad "a watchdog timeout with SBD config only" '{"pacemaker_sbd_service": false, "pacemaker_cluster_properties": {"stonith-watchdog-timeout": 10}}'
bad "a watchdog timeout with disk SBD" '{"pacemaker_sbd_devices": ["/dev/a"], "pacemaker_cluster_properties": {"stonith-watchdog-timeout": 10}}'

good "a primitive and a location" '{"pacemaker_primitives": [{"id": "web", "class": "ocf", "provider": "heartbeat", "type": "IPaddr2", "instance_attributes": {"ip": "192.0.2.10"}, "operations": [{"name": "monitor", "interval": "10s", "timeout": "20s"}]}], "pacemaker_location_constraints": [{"id": "web-on-a", "resource": "web", "node": "node-a.example.com", "score": "INFINITY"}]}'
good "a systemd primitive, no provider" '{"pacemaker_primitives": [{"id": "svc", "class": "systemd", "type": "nginx", "meta_attributes": {"target-role": "Started", "is-managed": true}}]}'
good "a primitive and a location set absent" '{"pacemaker_primitives": [{"id": "web", "class": "ocf", "provider": "heartbeat", "type": "IPaddr2", "instance_attributes": {"ip": "192.0.2.10"}, "operations": [{"name": "monitor", "interval": "10s", "timeout": "20s"}], "state": "absent"}], "pacemaker_location_constraints": [{"id": "web-on-a", "resource": "web", "node": "node-a.example.com", "score": "INFINITY", "state": "absent"}]}'
good "a negative score" '{"pacemaker_primitives": [{"id": "web", "class": "ocf", "provider": "heartbeat", "type": "IPaddr2", "instance_attributes": {"ip": "192.0.2.10"}, "operations": [{"name": "monitor", "interval": "10s", "timeout": "20s"}]}], "pacemaker_location_constraints": [{"id": "web-on-a", "resource": "web", "node": "node-a.example.com", "score": "INFINITY", "score": -100}]}'
bad "primitives as a map" '{"pacemaker_primitives": {"id": "web", "class": "ocf", "provider": "heartbeat", "type": "IPaddr2", "instance_attributes": {"ip": "192.0.2.10"}, "operations": [{"name": "monitor", "interval": "10s", "timeout": "20s"}]}}'
bad "a primitive id with a trailing newline" '{"pacemaker_primitives": [{"id": "web", "class": "ocf", "provider": "heartbeat", "type": "IPaddr2", "instance_attributes": {"ip": "192.0.2.10"}, "operations": [{"name": "monitor", "interval": "10s", "timeout": "20s"}], "id": "web\n"}]}'
bad "a primitive id with an embedded newline" '{"pacemaker_primitives": [{"id": "web", "class": "ocf", "provider": "heartbeat", "type": "IPaddr2", "instance_attributes": {"ip": "192.0.2.10"}, "operations": [{"name": "monitor", "interval": "10s", "timeout": "20s"}], "id": "web\nx"}]}'
bad "a primitive id starting with a digit" '{"pacemaker_primitives": [{"id": "web", "class": "ocf", "provider": "heartbeat", "type": "IPaddr2", "instance_attributes": {"ip": "192.0.2.10"}, "operations": [{"name": "monitor", "interval": "10s", "timeout": "20s"}], "id": "1web"}]}'
bad "a stonith class" '{"pacemaker_primitives": [{"id": "web", "class": "ocf", "provider": "heartbeat", "type": "IPaddr2", "instance_attributes": {"ip": "192.0.2.10"}, "operations": [{"name": "monitor", "interval": "10s", "timeout": "20s"}], "class": "stonith"}]}'
bad "an ocf primitive without a provider" '{"pacemaker_primitives": [{"id": "web", "class": "ocf", "type": "IPaddr2"}]}'
bad "a provider on a systemd primitive" '{"pacemaker_primitives": [{"id": "web", "class": "ocf", "provider": "heartbeat", "type": "IPaddr2", "instance_attributes": {"ip": "192.0.2.10"}, "operations": [{"name": "monitor", "interval": "10s", "timeout": "20s"}], "class": "systemd"}]}'
bad "a type with a trailing newline" '{"pacemaker_primitives": [{"id": "web", "class": "ocf", "provider": "heartbeat", "type": "IPaddr2", "instance_attributes": {"ip": "192.0.2.10"}, "operations": [{"name": "monitor", "interval": "10s", "timeout": "20s"}], "type": "IPaddr2\n"}]}'
bad "an attribute value with a quote" '{"pacemaker_primitives": [{"id": "web", "class": "ocf", "provider": "heartbeat", "type": "IPaddr2", "instance_attributes": {"ip": "192.0.2.10"}, "operations": [{"name": "monitor", "interval": "10s", "timeout": "20s"}], "instance_attributes": {"ip": "a\"b"}}]}'
bad "an attribute value with an embedded newline" '{"pacemaker_primitives": [{"id": "web", "class": "ocf", "provider": "heartbeat", "type": "IPaddr2", "instance_attributes": {"ip": "192.0.2.10"}, "operations": [{"name": "monitor", "interval": "10s", "timeout": "20s"}], "instance_attributes": {"ip": "a\nb"}}]}'
bad "an attribute name with a space" '{"pacemaker_primitives": [{"id": "web", "class": "ocf", "provider": "heartbeat", "type": "IPaddr2", "instance_attributes": {"ip": "192.0.2.10"}, "operations": [{"name": "monitor", "interval": "10s", "timeout": "20s"}], "meta_attributes": {"target role": "Stopped"}}]}'
bad "an operation timeout with a trailing newline" '{"pacemaker_primitives": [{"id": "web", "class": "ocf", "provider": "heartbeat", "type": "IPaddr2", "instance_attributes": {"ip": "192.0.2.10"}, "operations": [{"name": "monitor", "interval": "10s", "timeout": "20s"}], "operations": [{"name": "monitor", "interval": "10s", "timeout": "20s\n"}]}]}'
bad "an operation interval in days" '{"pacemaker_primitives": [{"id": "web", "class": "ocf", "provider": "heartbeat", "type": "IPaddr2", "instance_attributes": {"ip": "192.0.2.10"}, "operations": [{"name": "monitor", "interval": "10s", "timeout": "20s"}], "operations": [{"name": "monitor", "interval": "1d", "timeout": "20s"}]}]}'
bad "two operations with one name and interval" '{"pacemaker_primitives": [{"id": "web", "class": "ocf", "provider": "heartbeat", "type": "IPaddr2", "instance_attributes": {"ip": "192.0.2.10"}, "operations": [{"name": "monitor", "interval": "10s", "timeout": "20s"}], "operations": [{"name": "monitor", "interval": "10s"}, {"name": "monitor", "interval": "10s", "timeout": "5s"}]}]}'
bad "an unknown primitive state" '{"pacemaker_primitives": [{"id": "web", "class": "ocf", "provider": "heartbeat", "type": "IPaddr2", "instance_attributes": {"ip": "192.0.2.10"}, "operations": [{"name": "monitor", "interval": "10s", "timeout": "20s"}], "state": "stopped"}]}'
bad "a location score with a trailing newline" '{"pacemaker_primitives": [{"id": "web", "class": "ocf", "provider": "heartbeat", "type": "IPaddr2", "instance_attributes": {"ip": "192.0.2.10"}, "operations": [{"name": "monitor", "interval": "10s", "timeout": "20s"}]}], "pacemaker_location_constraints": [{"id": "web-on-a", "resource": "web", "node": "node-a.example.com", "score": "INFINITY", "score": "INFINITY\n"}]}'
bad "a location score as a word" '{"pacemaker_primitives": [{"id": "web", "class": "ocf", "provider": "heartbeat", "type": "IPaddr2", "instance_attributes": {"ip": "192.0.2.10"}, "operations": [{"name": "monitor", "interval": "10s", "timeout": "20s"}]}], "pacemaker_location_constraints": [{"id": "web-on-a", "resource": "web", "node": "node-a.example.com", "score": "INFINITY", "score": "high"}]}'
bad "a location node with an embedded newline" '{"pacemaker_primitives": [{"id": "web", "class": "ocf", "provider": "heartbeat", "type": "IPaddr2", "instance_attributes": {"ip": "192.0.2.10"}, "operations": [{"name": "monitor", "interval": "10s", "timeout": "20s"}]}], "pacemaker_location_constraints": [{"id": "web-on-a", "resource": "web", "node": "node-a.example.com", "score": "INFINITY", "node": "node-a\nx"}]}'
bad "a location resource with a <" '{"pacemaker_primitives": [{"id": "web", "class": "ocf", "provider": "heartbeat", "type": "IPaddr2", "instance_attributes": {"ip": "192.0.2.10"}, "operations": [{"name": "monitor", "interval": "10s", "timeout": "20s"}]}], "pacemaker_location_constraints": [{"id": "web-on-a", "resource": "web", "node": "node-a.example.com", "score": "INFINITY", "resource": "web<"}]}'
bad "a present location on a primitive set absent" '{"pacemaker_primitives": [{"id": "web", "class": "ocf", "provider": "heartbeat", "type": "IPaddr2", "instance_attributes": {"ip": "192.0.2.10"}, "operations": [{"name": "monitor", "interval": "10s", "timeout": "20s"}], "state": "absent"}], "pacemaker_location_constraints": [{"id": "web-on-a", "resource": "web", "node": "node-a.example.com", "score": "INFINITY"}]}'
bad "a location id equal to a primitive id" '{"pacemaker_primitives": [{"id": "web", "class": "ocf", "provider": "heartbeat", "type": "IPaddr2", "instance_attributes": {"ip": "192.0.2.10"}, "operations": [{"name": "monitor", "interval": "10s", "timeout": "20s"}]}], "pacemaker_location_constraints": [{"id": "web-on-a", "resource": "web", "node": "node-a.example.com", "score": "INFINITY", "id": "web"}]}'
good "an operation with on_fail" '{"pacemaker_primitives": [{"id": "web", "class": "ocf", "provider": "heartbeat", "type": "IPaddr2", "operations": [{"name": "monitor", "interval": "10s", "timeout": "20s", "on_fail": "standby"}]}]}'
bad "an unknown operation on_fail" '{"pacemaker_primitives": [{"id": "web", "class": "ocf", "provider": "heartbeat", "type": "IPaddr2", "operations": [{"name": "monitor", "interval": "10s", "on_fail": "explode"}]}]}'
bad "an unknown operation key" '{"pacemaker_primitives": [{"id": "web", "class": "ocf", "provider": "heartbeat", "type": "IPaddr2", "operations": [{"name": "monitor", "interval": "10s", "on-fail": "standby"}]}]}'
bad "an unknown primitive key" '{"pacemaker_primitives": [{"id": "web", "class": "ocf", "provider": "heartbeat", "type": "IPaddr2", "group": "g"}]}'
bad "a null attribute value" '{"pacemaker_primitives": [{"id": "web", "class": "ocf", "provider": "heartbeat", "type": "IPaddr2", "instance_attributes": {"ip": null}}]}'
bad "an unknown location key" '{"pacemaker_primitives": [{"id": "web", "class": "ocf", "provider": "heartbeat", "type": "IPaddr2"}], "pacemaker_location_constraints": [{"id": "web-on-a", "resource": "web", "node": "node-a.example.com", "score": "INFINITY", "role": "Promoted"}]}'

if [[ $fails -gt 0 ]]; then echo "$fails failed" >&2; exit 1; fi
echo "all passed"
