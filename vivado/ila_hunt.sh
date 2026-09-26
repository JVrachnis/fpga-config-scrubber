#!/usr/bin/env bash
# repeat arm+frozen-RMW until a corrupted read is captured
VIV=${VIVADO_BIN:?set VIVADO_BIN to <Xilinx>/2025.2/Vivado/bin}
F=${1:-0x400A23}; N=${2:-10}
cd ${SCRUBBER_ROOT:?set SCRUBBER_ROOT}/vivado
for i in $(seq 1 $N); do
  rm -f /tmp/ila_armed /tmp/rmw_result
  ILA_CSV=/tmp/ila_rmw_$i.csv $VIV/vivado -mode batch -source ila_arm12.tcl > /tmp/ila_arm_$i.log 2>&1 &
  VPID=$!
  timeout 300 $VIV/xsdb rmw_one.tcl $F > /tmp/rmw_one_$i.log 2>&1
  wait $VPID
  R=$(cat /tmp/rmw_result 2>/dev/null); echo "iter $i: $R  ($(grep -c 'CSV written' /tmp/ila_arm_$i.log) csv)"
  if echo "$R" | grep -q "frame_diff=[1-9]"; then echo "CORRUPTION CAPTURED at iter $i"; cp /tmp/ila_rmw_$i.csv /tmp/ila_corrupt.csv; cp /tmp/rmw_bad_words /tmp/rmw_bad_words_$i; break; fi
done
