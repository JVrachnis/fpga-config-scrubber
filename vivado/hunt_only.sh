#!/usr/bin/env bash
# ./hunt_only.sh <name> <iters>  — program the saved ILA bitstream and run hunt13.sh (no rebuild)
set -u
ROOT=${SCRUBBER_ROOT:?set SCRUBBER_ROOT to the repository root}; VIV=${VIVADO_BIN:?set VIVADO_BIN to <Xilinx>/2025.2/Vivado/bin}
OUT=$ROOT/campaign/2026-09-04_night; name=${1:-10b_hunt}; N=${2:-25}
cd $ROOT/vivado
echo "=== $name  $(date +%H:%M)  (bit=ila13)" | tee -a /tmp/night.log
echo $name > /tmp/board.lock
cp $ROOT/bitstream/night_ila13.bit $ROOT/bitstream/scrubber_injection_wrapper.bit
cp $ROOT/bitstream/night_ila13.ltx $ROOT/bitstream/scrubber_injection_wrapper.ltx
pkill -x hw_server; pkill -x xsdb; sleep 4
$VIV/hw_server -d > /dev/null 2>&1; sleep 3
timeout 300 $VIV/xsdb $ROOT/vivado/prog.tcl > $OUT/${name}_prog.log 2>&1
./hunt13.sh $N > $OUT/$name.log 2>&1
tail -3 $OUT/$name.log; cp /tmp/ila_cern0_fail.csv $OUT/ 2>/dev/null
rm -f /tmp/board.lock
echo "--- $name finished $(date +%H:%M)" | tee -a /tmp/night.log
