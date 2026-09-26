#!/usr/bin/env bash
# Configuration-matrix driver: for each (S,G,WD) build the bitstream, program,
# run the characterization suite, archive everything under
# campaign/2026-09-03_matrix/<config>/.  Restores the package constants at exit.
#
#   ./matrix.sh "4:64:268435456" "4:128:268435456" "8:64:268435456" "2:64:0"
#
# Suite per config: period3 (pass period), campaign_honest 150 (latency +
# verdict), campaign_conc_S (capacity), utilization + timing reports.
set -u
ROOT=${SCRUBBER_ROOT:?set SCRUBBER_ROOT to the repository root}
VIV=${VIVADO_BIN:?set VIVADO_BIN to <Xilinx>/2025.2/Vivado/bin}
PKG=$ROOT/rtl/v1.8/scrubber_ip_pkg.vhd
IP=$ROOT/rtl/v1.8/scrubber_ip.vhd
XDC=$ROOT/vivado/scrubber2025/scrubber2025.srcs/constrs_1/new/scrubber_injection_wrapper.xdc
RUN=$ROOT/vivado/scrubber2025/scrubber2025.runs/impl_1
OUT=$ROOT/campaign/2026-09-03_matrix
mkdir -p "$OUT"

ORIG_S=$(grep -oP 'subgroups_per_group_c\s*:\s*integer\s*:=\s*\K[0-9]+' "$PKG")
ORIG_G=$(grep -oP 'max_frames_per_group_c\s*:\s*integer\s*:=\s*\K[0-9]+' "$PKG")
ORIG_WD=$(grep -oP 'wd_timeout_cycles\s*:\s*integer\s*:=\s*\K[0-9]+' "$IP")
cp "$XDC" /tmp/xdc.matrix.bak
restore() {
  sed -i -E "s/(subgroups_per_group_c\s*:\s*integer\s*:=\s*)[0-9]+/\1$ORIG_S/; s/(max_frames_per_group_c\s*:\s*integer\s*:=\s*)[0-9]+/\1$ORIG_G/" "$PKG"
  sed -i -E "s/(wd_timeout_cycles\s*:\s*integer\s*:=\s*)[0-9]+/\1$ORIG_WD/" "$IP"
  cp /tmp/xdc.matrix.bak "$XDC"
}
trap restore EXIT

for cfg in "$@"; do
  S=${cfg%%:*}; rest=${cfg#*:}; G=${rest%%:*}; WD=${rest#*:}
  name="S${S}G${G}$([ "$WD" = 0 ] && echo _wdoff)"
  d="$OUT/$name"; mkdir -p "$d"
  echo "=== $name  $(date +%H:%M) ==="
  sed -i -E "s/(subgroups_per_group_c\s*:\s*integer\s*:=\s*)[0-9]+/\1$S/; s/(max_frames_per_group_c\s*:\s*integer\s*:=\s*)[0-9]+/\1$G/" "$PKG"
  sed -i -E "s/(wd_timeout_cycles\s*:\s*integer\s*:=\s*)[0-9]+/\1$WD/" "$IP"
  grep -vi "mark_debug\|dbg_hub\|create_debug\|connect_debug\|set_property C_CLK\|probe" /tmp/xdc.matrix.bak > "$XDC"
  ( cd "$ROOT/vivado" && "$VIV/vivado" -mode batch -source rebuild_force.tcl > "$d/build.log" 2>&1 )
  if ! grep -q "write_bitstream Complete" "$d/build.log"; then echo "BUILD FAILED for $name"; grep -E "^ERROR" "$d/build.log" | head -5 > "$d/BUILD_FAILED"; continue; fi
  cp "$RUN"/*timing_summary_routed.rpt "$d/timing.rpt"; cp "$RUN"/*utilization_placed.rpt "$d/util.rpt" 2>/dev/null
  grep -m1 -A2 "WNS(ns)" "$d/timing.rpt" | tail -1 | awk '{print "WNS", $1}' | tee "$d/wns.txt"
  cp "$RUN/scrubber_injection_wrapper.bit" "$ROOT/bitstream/scrubber_injection_wrapper.bit"
  cp "$RUN/scrubber_injection_wrapper.bit" "$d/$name.bit"
  cd "$ROOT/vivado"
  for s in "period3.tcl:period" "campaign_honest.tcl:campaign" "campaign_conc_S.tcl $S:conc"; do
    script=${s%%:*}; tag=${s##*:}
    pkill -x hw_server; sleep 6
    timeout 3600 "$VIV/xsdb" $script > "$d/$tag.log" 2>&1
    echo "  $tag: $(grep -a 'RESULT\|intervals\|final' "$d/$tag.log" | tail -1 | cut -c1-120)"
  done
done
echo "=== matrix done $(date +%H:%M) ==="
