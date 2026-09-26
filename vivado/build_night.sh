#!/usr/bin/env bash
set -u
ROOT=${SCRUBBER_ROOT:?set SCRUBBER_ROOT to the repository root}; VIV=${VIVADO_BIN:?set VIVADO_BIN to <Xilinx>/2025.2/Vivado/bin}
XDC=$ROOT/vivado/scrubber2025/scrubber2025.srcs/constrs_1/new/scrubber_injection_wrapper.xdc
RUN=$ROOT/vivado/scrubber2025/scrubber2025.runs/impl_1
WR=$ROOT/rtl/v1.8/scrubber_wrapper.vhd; PKG=$ROOT/rtl/v1.8/scrubber_ip_pkg.vhd
cp $XDC /tmp/xdc.night.bak
build() { # name
  grep -vi "mark_debug\|dbg_hub\|create_debug\|connect_debug\|set_property C_CLK\|probe" /tmp/xdc.night.bak > $XDC
  ( cd $ROOT/vivado && $VIV/vivado -mode batch -source rebuild_force.tcl > /tmp/build_$1.log 2>&1 )
  if grep -q "write_bitstream Complete" /tmp/build_$1.log; then
    cp $RUN/scrubber_injection_wrapper.bit $ROOT/bitstream/night_$1.bit
    echo "$1: WNS $(grep -m1 -A2 'WNS(ns)' $RUN/*timing_summary_routed.rpt | tail -1 | awk '{print $1}')"
  else echo "$1: BUILD FAILED"; grep -E "^ERROR" /tmp/build_$1.log | head -3; fi
}
build test
sed -i 's/\t\tTEST_MODE_G\t\t: boolean\t:= true/\t\tTEST_MODE_G\t\t: boolean\t:= false/' $WR; build prod
sed -i 's/\t\tTEST_MODE_G\t\t: boolean\t:= false/\t\tTEST_MODE_G\t\t: boolean\t:= true/' $WR
sed -i -E 's/(subgroups_per_group_c\s*:\s*integer\s*:=\s*)[0-9]+/\14/' $PKG; build s4g64
sed -i -E 's/(subgroups_per_group_c\s*:\s*integer\s*:=\s*)[0-9]+/\12/' $PKG
cp /tmp/xdc.night.bak $XDC
echo "BUILDS DONE"
