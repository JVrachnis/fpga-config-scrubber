#!/bin/bash
# Run the closed-loop core testbench across the validated (S,G) configuration matrix.
#
#   S = subgroups_per_group  (interleave depth; must be a power of two)
#   G = max_frames_per_group (group window; must be >= the largest column minor count)
#
# Every check in core_tb.vhd runs for each configuration, including the ones that
# only become meaningful at S>=4 (four adjacent upset frames corrected together)
# and the self-hardening checks (golden-store upset, TMR flip, watchdog recovery).
#
# Usage:  ./run_matrix.sh              # the three validated configurations
#         ./run_matrix.sh 4 128        # one specific configuration
#         STOP=80ms ./run_matrix.sh    # override the simulation time limit
#
# The script restores core_tb.vhd to its committed (S,G) on exit, including on
# interrupt, so a failed run never leaves the testbench edited.

set -u
cd "$(dirname "$0")"
TB=core_tb.vhd
STOP="${STOP:-60ms}"

[ -f "$TB" ] || { echo "error: $TB not found (run from sim/core_tb)"; exit 2; }

ORIG_S=$(grep -oP 'constant S_TB\s+: integer := \K[0-9]+' "$TB")
ORIG_G=$(grep -oP 'constant G_TB\s+: integer := \K[0-9]+' "$TB")
[ -n "$ORIG_S" ] && [ -n "$ORIG_G" ] || { echo "error: could not read S_TB/G_TB from $TB"; exit 2; }

restore() { sed -i -E "s/(constant S_TB\s+: integer := )[0-9]+/\1$ORIG_S/; \
                       s/(constant G_TB\s+: integer := )[0-9]+/\1$ORIG_G/" "$TB"; }
trap restore EXIT INT TERM

if [ $# -eq 2 ]; then
  CONFIGS="$1:$2"
else
  CONFIGS="2:64 4:64 4:128"
fi

fail=0
printf '%-10s %-10s %s\n' "S" "G" "RESULT"
printf '%-10s %-10s %s\n' "-" "-" "------"
for cfg in $CONFIGS; do
  S=${cfg%%:*}; G=${cfg##*:}
  sed -i -E "s/(constant S_TB\s+: integer := )[0-9]+/\1$S/; \
             s/(constant G_TB\s+: integer := )[0-9]+/\1$G/" "$TB"
  log="/tmp/core_tb_S${S}_G${G}.log"
  if STOP="$STOP" TAIL=100 bash build.sh > "$log" 2>&1 && grep -qa "ALL CHECKS PASSED" "$log"; then
    printf '%-10s %-10s PASS\n' "$S" "$G"
  else
    printf '%-10s %-10s FAIL   (see %s)\n' "$S" "$G" "$log"
    grep -aE "assertion failure|error:" "$log" | head -3 | sed 's/^/           /'
    fail=1
  fi
done

echo
if [ $fail -eq 0 ]; then
  echo "matrix green (restored to committed S=$ORIG_S G=$ORIG_G)"
else
  echo "matrix FAILED (restored to committed S=$ORIG_S G=$ORIG_G)"
fi
exit $fail
