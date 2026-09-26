#!/usr/bin/env bash
VIV=${VIVADO_BIN:?set VIVADO_BIN to <Xilinx>/2025.2/Vivado/bin}; N=${1:-20}
cd ${SCRUBBER_ROOT:?set SCRUBBER_ROOT}/vivado
for i in $(seq 1 $N); do
  rm -f /tmp/ila_armed /tmp/rmw_result
  ILA_CSV=/tmp/ila_c0_$i.csv $VIV/vivado -mode batch -source ila_arm13.tcl > /tmp/ila_arm13_$i.log 2>&1 &
  VPID=$!
  timeout 300 $VIV/xsdb cern0_one.tcl > /tmp/c0one_$i.log 2>&1
  wait $VPID
  R=$(cat /tmp/rmw_result 2>/dev/null); echo "iter $i: $R ($(grep -c 'CSV written' /tmp/ila_arm13_$i.log) csv)"
  if echo "$R" | grep -q "skipped=1\|dirty=[0-9A-F]"; then echo "FAILURE CAPTURED at iter $i"; cp /tmp/ila_c0_$i.csv /tmp/ila_cern0_fail.csv; break; fi
done
