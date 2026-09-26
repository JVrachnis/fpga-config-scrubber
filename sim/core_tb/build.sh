#!/bin/bash
# NOTE: the DUT is the full scrubber_ip. Only the files authored by J. Vrachnis are in this
# repository; the inherited SYSYFOS RTL listed in rtl/README.md must be supplied under rtl/
# (same paths as below) before this bench will elaborate.
cd "$(dirname "$0")"
R=../../rtl
FLAGS="--std=08 -fsynopsys -frelaxed --work=work --workdir=work -P../injector_tb/unisim"
mkdir -p work ../injector_tb/unisim
set -e
ghdl -a --std=08 -fsynopsys --work=unisim --workdir=../injector_tb/unisim ../injector_tb/unisim_stub.vhd
ghdl -a $FLAGS $R/v1.8/log2_pkg.vhd $R/v1.8/icape_common.vhd $R/v1.8/scrubber_ip_pkg.vhd $R/v1.8/device_geometry_pkg.vhd
ghdl -a $FLAGS $R/modules/mem_blocks/dualportmem.vhd $R/modules/mem_blocks/pchk_dualportmem.vhd $R/modules/mem_blocks/fwft_fifo.vhd
ghdl -a $FLAGS $R/modules/icap_controller/icap_controller.vhd
ghdl -a $FLAGS $R/modules/icap_arbiter/icap_arbiter.vhd 2>/dev/null || ghdl -a $FLAGS $R/history/v1.1/icap_arbiter/icap_arbiter.vhd
ghdl -a $FLAGS $R/modules/golden_parity_mem/golden_parity_mem.vhd
ghdl -a $FLAGS $R/modules/calc_parity_mem/calc_parity_mem.vhd
ghdl -a $FLAGS $R/modules/parity_calculator/parity_calculator.vhd
ghdl -a $FLAGS $R/modules/syndrome_handler/syndrome_handler.vhd
ghdl -a $FLAGS $R/modules/edc_algorithm/calc_mem_read_arbiter.vhd
ghdl -a $FLAGS $R/modules/edc_algorithm/algorithm_icap_if.vhd
ghdl -a $FLAGS $R/modules/edc_algorithm/algorithm_state_machine.vhd
ghdl -a $FLAGS $R/modules/edc_algorithm/edc_algorithm.vhd
ghdl -a $FLAGS $R/modules/fault_injection/fault_Injection.vhd
ghdl -a $FLAGS $R/v1.8/scrubber_ip.vhd
ghdl -a $FLAGS core_tb.vhd
ghdl -e $FLAGS core_tb
ghdl -r $FLAGS core_tb --stop-time=${STOP:-15ms} 2>&1 | grep -vE "metavalue|NUMERIC|assertion warning|std_logic_arith" | tail -${TAIL:-40}
