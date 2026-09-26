#!/usr/bin/env bash
# ./map_build.sh <test|prod|s4g64>  — rebuild that night variant (no board) and write its
# logic-location (.ll) + essential-bits (.ebd) files to /tmp/map_<name>/ for offline bit attribution.
# Restores the RTL generics and the XDC afterwards (same edits as build_night.sh).
set -u
ROOT=${SCRUBBER_ROOT:?set SCRUBBER_ROOT to the repository root}; VIV=${VIVADO_BIN:?set VIVADO_BIN to <Xilinx>/2025.2/Vivado/bin}
XDC=$ROOT/vivado/scrubber2025/scrubber2025.srcs/constrs_1/new/scrubber_injection_wrapper.xdc
RUN=$ROOT/vivado/scrubber2025/scrubber2025.runs/impl_1
WR=$ROOT/rtl/v1.8/scrubber_wrapper.vhd; PKG=$ROOT/rtl/v1.8/scrubber_ip_pkg.vhd
name=$1; OUT=/tmp/map_$name; mkdir -p $OUT
cp $XDC /tmp/xdc.map.bak
grep -vi "mark_debug\|dbg_hub\|create_debug\|connect_debug\|set_property C_CLK\|probe" /tmp/xdc.map.bak > $XDC
case $name in
  prod)  sed -i 's/\t\tTEST_MODE_G\t\t: boolean\t:= true/\t\tTEST_MODE_G\t\t: boolean\t:= false/' $WR ;;
  s4g64) sed -i -E 's/(subgroups_per_group_c\s*:\s*integer\s*:=\s*)[0-9]+/\14/' $PKG ;;
esac
( cd $ROOT/vivado && $VIV/vivado -mode batch -source rebuild_force.tcl > $OUT/build.log 2>&1 )
if grep -q "write_bitstream Complete" $OUT/build.log; then
  cmp -s $RUN/scrubber_injection_wrapper.bit $ROOT/bitstream/night_$name.bit && echo "$name: bit identical to night_$name.bit" || echo "$name: bit DIFFERS from night_$name.bit (placement may differ)"
  cat > $OUT/map.tcl <<EOT
open_checkpoint $RUN/scrubber_injection_wrapper_routed.dcp
set_property BITSTREAM.SEU.ESSENTIALBITS yes [current_design]
write_bitstream -force -logic_location_file $OUT/design.bit
EOT
  ( cd $OUT && $VIV/vivado -mode batch -source $OUT/map.tcl > $OUT/map.log 2>&1 )
  ls -la $OUT/design.ll $OUT/design.ebd
else echo "$name: BUILD FAILED"; grep -E "^ERROR" $OUT/build.log | head -3; fi
case $name in
  prod)  sed -i 's/\t\tTEST_MODE_G\t\t: boolean\t:= false/\t\tTEST_MODE_G\t\t: boolean\t:= true/' $WR ;;
  s4g64) sed -i -E 's/(subgroups_per_group_c\s*:\s*integer\s*:=\s*)[0-9]+/\12/' $PKG ;;
esac
cp /tmp/xdc.map.bak $XDC
echo "MAP $name DONE $(date +%H:%M)"
