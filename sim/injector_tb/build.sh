#!/bin/bash
# Self-checking bench of the ICAP controller + fault injector.
# NOTE: needs log2_pkg.vhd, scrubber_ip_pkg.vhd and fault_Injection.vhd, which are
# part of the inherited SYSYFOS RTL and are NOT in this repository (see rtl/README.md).
cd "$(dirname "$0")"
R=../../rtl
FLAGS="--std=08 -fsynopsys -frelaxed --work=work --workdir=work -Punisim"
mkdir -p work unisim
set -e
ghdl -a --std=08 -fsynopsys --work=unisim --workdir=unisim unisim_stub.vhd
echo "== analyze packages =="
ghdl -a $FLAGS $R/v1.8/log2_pkg.vhd
ghdl -a $FLAGS $R/v1.8/icape_common.vhd
ghdl -a $FLAGS $R/v1.8/scrubber_ip_pkg.vhd
echo "== analyze DUTs =="
ghdl -a $FLAGS $R/modules/icap_controller/icap_controller.vhd
ghdl -a $FLAGS $R/modules/fault_injection/fault_Injection.vhd
echo "== analyze TB =="
ghdl -a $FLAGS injsim_tb.vhd
echo "== elaborate =="
ghdl -e $FLAGS injsim_tb
echo "== run =="
ghdl -r $FLAGS injsim_tb --stop-time=35us 2>&1 | grep -E "WRB pos|SIM COMPLETE|error|assert" | head -260
