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
good "SBD off, pcsd left alone, extra packages" '{"pacemaker_sbd": false, "pacemaker_pcsd_masked": false, "pacemaker_packages_extra": ["fence-agents"]}'
good "SBD config only" '{"pacemaker_sbd_service": false}'
good "defaults, a deleted property" '{"pacemaker_resource_defaults": {"resource-stickiness": 100}, "pacemaker_op_defaults": {"timeout": "60s"}, "pacemaker_cluster_properties": {"cluster-recheck-interval": null}}'
good "stonith-watchdog-timeout twice the watchdog timeout, in seconds, a longer stonith-timeout" '{"pacemaker_sbd_watchdog_timeout": 35, "pacemaker_cluster_properties": {"stonith-watchdog-timeout": "70s", "stonith-timeout": 71}}'
good "stonith-watchdog-timeout -1, Pacemaker takes twice" '{"pacemaker_sbd_watchdog_timeout": 35, "pacemaker_cluster_properties": {"stonith-watchdog-timeout": -1, "stonith-timeout": "90s"}}'
good "a restart allowed" '{"pacemaker_allow_restart": true}'
good "a watchdog timeout of 0 without SBD" '{"pacemaker_sbd": false, "pacemaker_cluster_properties": {"stonith-watchdog-timeout": 0}}'
bad "an unknown state" '{"pacemaker_state": "latest"}'
bad "an extra package with a trailing newline" '{"pacemaker_packages_extra": ["fence-agents\n"]}'
bad "an extra package with an embedded newline" '{"pacemaker_packages_extra": ["fence\nagents"]}'
bad "extra packages as a string" '{"pacemaker_packages_extra": "fence-agents"}'
bad "pcsd masked as a string" '{"pacemaker_pcsd_masked": "yes"}'
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

if [[ $fails -gt 0 ]]; then echo "$fails failed" >&2; exit 1; fi
echo "all passed"
