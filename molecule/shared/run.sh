#!/usr/bin/env bash
# Runs the converge playbook again from the control node, on Molecule's inventory, with extra arguments;
# prints the recap. Used by side_effect plays to check a rerun's result and recap.
set -uo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
export ANSIBLE_NOCOLOR=1 ANSIBLE_FORCE_COLOR=0
inv=$(dirname "${MOLECULE_INVENTORY_FILE:?run by Molecule}")
ansible-playbook -i "$inv" "$here/converge.yml" "$@" 2>&1
