#!/bin/sh
set -eu
a0="$1"
v1="${BUCK_SCRATCH_PATH:-/tmp}"'/out.link'
'nix' 'build' '--print-build-logs' '--no-update-lock-file' '--no-eval-cache' '--max-jobs' '1' '--cores' '8' '--out-link' "$v1" 'path:.#book'
v2="$v1"
v3=$('readlink' '-f' "$v2")
'cp' '-a' '--reflink=auto' "$v3"'/.' "$a0"
'chmod' '-R' 'u+w' "$a0"
