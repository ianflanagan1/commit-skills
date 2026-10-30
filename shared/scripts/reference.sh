#!/bin/sh
# reference: print one of the skill's references, for its SKILL.md to inline as it loads.
#
# Claude Code blocks a load-time cat of a file outside the session's working directories, whatever
# the skill's allowed-tools say, and a linked skill's references resolve into this repository. A
# script the skill's allowed-tools permit runs wherever the skill is installed.
#
# Usage: reference.sh name
#
# Exit status: 0 printed, 2 usage error or no such reference.

set -o errexit -o nounset

usage() { sed -n '8p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }
[ $# -eq 1 ] || usage
case $1 in '' | -h | */*) usage ;; esac
file=$(dirname "$0")/../references/$1
[ -f "$file" ] || { echo "No reference $1" >&2; exit 2; }
cat "$file"
