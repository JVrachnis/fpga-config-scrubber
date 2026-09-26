-- SPDX-License-Identifier: MIT
-- Copyright (c) 2021-2026 John Vrachnis
----------------------------------------------------------------------------------
-- Company:
-- Engineer:
--
-- Create Date: 03/08/2021 02:12:14 PM
-- Design Name:
-- Module Name: scrubber_wrapper - Behavioral
-- Project Name:
-- Target Devices:
-- Tool Versions:
-- Description:
--
-- Dependencies:
--
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
--
----------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use work.scrubber_ip_pkg.all;
use work.log2_pkg.all;
Library UNISIM;
use UNISIM.vcomponents.all;

entity scrubber_wrapper is
  generic (
  -- Width of S_AXI data bus
		C_S_AXI_DATA_WIDTH	: integer	:= 32;
		-- Width of S_AXI address bus
		C_S_AXI_ADDR_WIDTH	: integer	:= 5;
		-- 2026-09-03: test instrumentation (HOLD_CORRECTION, TEST_FREEZE, the
		-- BUFGCE-gated core clock). false = production build: one clock domain,
		-- no BUFGCE, the three control bits tied off so synthesis prunes them.
		TEST_MODE_G		: boolean	:= true;
		-- 2026-09-03 hardness A/B: false disables the golden-store byte-parity check
		GOLDEN_PARITY_G		: boolean	:= true
	);
  Port (
        -- Global Clock Signal
		S_AXI_ACLK	: in std_logic;
		-- Global Reset Signal. This Signal is Active LOW
		S_AXI_ARESETN	: in std_logic;
		-- Write address (issued by master, acceped by Slave)
		S_AXI_AWADDR	: in std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0);
		-- Write channel Protection type. This signal indicates the
    		-- privilege and security level of the transaction, and whether
    		-- the transaction is a data access or an instruction access.
		S_AXI_AWPROT	: in std_logic_vector(2 downto 0);
		-- Write address valid. This signal indicates that the master signaling
    		-- valid write address and control information.
		S_AXI_AWVALID	: in std_logic;
		-- Write address ready. This signal indicates that the slave is ready
    		-- to accept an address and associated control signals.
		S_AXI_AWREADY	: out std_logic;
		-- Write data (issued by master, acceped by Slave)
		S_AXI_WDATA	    : in std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
		-- Write strobes. This signal indicates which byte lanes hold
    		-- valid data. There is one write strobe bit for each eight
    		-- bits of the write data bus.
		S_AXI_WSTRB	    : in std_logic_vector((C_S_AXI_DATA_WIDTH/8)-1 downto 0);
		-- Write valid. This signal indicates that valid write
    		-- data and strobes are available.
		S_AXI_WVALID	: in std_logic;
		-- Write ready. This signal indicates that the slave
    		-- can accept the write data.
		S_AXI_WREADY	: out std_logic;
		-- Write response. This signal indicates the status
    		-- of the write transaction.
		S_AXI_BRESP	    : out std_logic_vector(1 downto 0);
		-- Write response valid. This signal indicates that the channel
    		-- is signaling a valid write response.
		S_AXI_BVALID	: out std_logic;
		-- Response ready. This signal indicates that the master
    		-- can accept a write response.
		S_AXI_BREADY	: in std_logic;
		-- Read address (issued by master, acceped by Slave)
		S_AXI_ARADDR	: in std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0);
		-- Protection type. This signal indicates the privilege
    		-- and security level of the transaction, and whether the
    		-- transaction is a data access or an instruction access.
		S_AXI_ARPROT	: in std_logic_vector(2 downto 0);
		-- Read address valid. This signal indicates that the channel
    		-- is signaling valid read address and control information.
		S_AXI_ARVALID	: in std_logic;
		-- Read address ready. This signal indicates that the slave is
    		-- ready to accept an address and associated control signals.
		S_AXI_ARREADY	: out std_logic;
		-- Read data (issued by slave)
		S_AXI_RDATA	: out std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
		-- Read response. This signal indicates the status of the
    		-- read transfer.
		S_AXI_RRESP	: out std_logic_vector(1 downto 0);
		-- Read valid. This signal indicates that the channel is
    		-- signaling the required read data.
		S_AXI_RVALID	: out std_logic;
		-- Read ready. This signal indicates that the master can
    		-- accept the read data and response information.
		S_AXI_RREADY	: in std_logic
	);
end scrubber_wrapper;

architecture Behavioral of scrubber_wrapper is
signal reset                       : std_logic;
-- Reset-paradox diagnostic word (observation only)
signal rst_dbg                     : std_logic_vector(4 downto 0);
-- ICAP primitive Interface
signal icap_csn                     : std_logic;
signal icap_rd_wrn                  : std_logic;
signal icap_wrdata                  : std_logic_vector(bits_per_word_c-1 downto 0);
signal icap_rddata                  : std_logic_vector(bits_per_word_c-1 downto 0);
signal icap_ready                   : std_logic;
signal icap_clk                     : std_logic;
     -- FRAME ECC primitive Interface
signal fecc_syndromevalid           : std_logic;
signal fecc_eccerror                : std_logic;
signal fecc_syndrome                : std_logic_vector(log2(words_per_frame_c)+log2(bits_per_word_c) downto 0);
signal fecc_crcerror                : std_logic;
signal fecc_far                     : std_logic_vector(frame_addr_width_c-1 downto 0);
signal fecc_synword                 : std_logic_vector(log2(words_per_frame_c)-1 downto 0);
signal fecc_synbit                  : std_logic_vector(log2(bits_per_word_c)-1 downto 0);
signal fecc_eccerrorsingle          : std_logic;
-- Fault Injection Interface
signal inject_request               :   std_logic;
signal     inject_grant                 :  std_logic;
signal     inject_start                 :   std_logic;
signal     inject_stop                  :   std_logic;
signal     inject_write_command         :   std_logic;
signal     inject_register_access       :   std_logic;
signal     inject_desync                :   std_logic;
signal     inject_busy                  :  std_logic;
signal     inject_synced                :  std_logic;
signal     inject_data_in_fetch         :  std_logic;
signal     inject_data_out_valid        :  std_logic;
signal     inject_frame_addr            :   std_logic_vector(frame_addr_width_c-1 downto 0);
signal     inject_num_of_frames         :   std_logic_vector(19 downto 0);
signal     inject_cur_frame_index       :  std_logic_vector(19 downto 0);
signal     inject_cur_word_index        :  std_logic_vector(log2(words_per_frame_c)-1 downto 0);
signal     inject_data_in               :   std_logic_vector(bits_per_word_c-1 downto 0);
signal     inject_data_out              :  std_logic_vector(bits_per_word_c-1 downto 0);
-- Scrubber diagnostic status word (observation only)
signal     scrub_diag                    :  std_logic_vector(7 downto 0);
-- Parity-calculator FSM diagnostic word (observation only)
signal     scrub_pcalc_dbg               :  std_logic_vector(7 downto 0);
-- Runtime scan pause from AXI slv_reg3(5): 1 = pause continuous scan (test isolation)
signal     scan_pause                    :  std_logic;
signal     hold_corr                     :  std_logic;   -- 2026-09 test freeze (slv_reg3(6))
signal     hold_corr_g                   :  std_logic;   -- gated by TEST_MODE_G
signal     test_freeze_g                 :  std_logic;
signal     detect_pulse                  :  std_logic;   -- 2026-09 instrumentation
signal     correct_pulse                 :  std_logic;
signal     diag_pulses                   :  std_logic_vector(4 downto 0);
signal     test_freeze                   :  std_logic;
signal     icap_free                     :  std_logic;
-- 2026-09 clock freeze: scrubber_ip runs on a gated version of the AXI clock so
-- its state can be stopped exactly where it stands. The AXI interface itself
-- stays on the ungated clock and remains accessible while the core is frozen.
signal     freeze_clk                    :  std_logic;
signal     scrub_clk                     :  std_logic;
signal     icap_idle                     :  std_logic;
signal     test_dbg                      :  std_logic_vector(4 downto 0);
signal     core_live                     :  std_logic_vector(31 downto 0);
attribute mark_debug                                                                                                                                                                                                                 : string;
  attribute mark_debug of fecc_crcerror,fecc_eccerror,fecc_eccerrorsingle,fecc_far,fecc_synbit,fecc_syndrome,fecc_syndromevalid,fecc_synword: signal is "true";
begin
reset <= not S_AXI_ARESETN;
-- 0x14 bits[23:19] (injector RST_DBG). Until 2026-09-03 this carried the
-- reset-paradox diagnostic (resolved; all five bits read constant). Now the
-- recovery/hand-off word from scrubber_ip.test_dbg:
--   bit19 wd_fires parity   bit20..21 init_drops   bit22 handoff_timeout
--   bit23 tf_release
rst_dbg <= test_dbg;
-- FRAME_ECCE2: Configuration Frame Error Correction
-- 7 Series
-- Xilinx HDL Libraries Guide, version 13.1
FRAME_ECCE2_inst : FRAME_ECCE2
generic map (
FARSRC => "FAR", -- Determines if the output of FAR[25:0] configuration register points
-- to the FAR or EFAR. Sets configuration option register bit CTL0[7].
FRAME_RBT_IN_FILENAME => "NONE" -- This file is output by the ICAP_E2 model and it contains Frame Data
-- information for the Raw Bitstream (RBT) file. The FRAME_ECCE2 model
-- will parse this file, calculate ECC and output any error conditions.
)
port map (
CRCERROR => fecc_crcerror, -- 1-bit output: Output indicating a CRC error.
ECCERROR => fecc_eccerror, -- 1-bit output: Output indicating an ECC error.
ECCERRORSINGLE => fecc_eccerrorsingle, -- 1-bit output: Output Indicating single-bit Frame ECC error detected.
FAR => fecc_far, -- 26-bit output: Frame Address Register Value output.
SYNBIT => fecc_synbit, -- 5-bit output: Output bit address of error.
SYNDROME => fecc_syndrome, -- 13-bit output: Output location of erroneous bit.
SYNDROMEVALID => fecc_syndromevalid, -- 1-bit output: Frame ECC output indicating the SYNDROME output is
-- valid.
SYNWORD => fecc_synword -- 7-bit output: Word output in the frame where an ECC error has been
-- detected.
);
-- End of FRAME_ECCE2_inst instantiation



-- ICAPE2: Internal Configuration Access Port
-- 7 Series
-- Xilinx HDL Libraries Guide, version 13.1
-- 2026-09: glitchless gate on the scrubber core clock (test instrumentation).
-- CE is driven from an AXI register bit; BUFGCE handles the clean stop/start.
g_test_clk : if TEST_MODE_G generate
  BUFGCE_scrub : BUFGCE
    port map (O => scrub_clk, CE => not freeze_clk, I => S_AXI_ACLK);
end generate;
g_prod_clk : if not TEST_MODE_G generate
  scrub_clk <= S_AXI_ACLK;          -- single clock domain in production
end generate;
hold_corr_g   <= hold_corr   when TEST_MODE_G else '0';
test_freeze_g <= test_freeze when TEST_MODE_G else '0';

ICAPE2_inst : ICAPE2
generic map (
DEVICE_ID => x"13722093", -- Specifies the pre-programmed Device ID value
ICAP_WIDTH => "X32", -- Specifies the input and output data width to be used with the ICAPE2.
-- Possible values: (X18,X16 or X32).
SIM_CFG_FILE_NAME => "NONE" -- Specifies the Raw Bitstream (RBT) file to be parsed by the simulation
-- model
)
port map (
O => icap_rddata, -- 32-bit output: Configuration data output bus
CLK => icap_clk, -- 1-bit input: Clock Input
CSIB => icap_csn, -- 1-bit input: Active-Low ICAP Enable
I => icap_wrdata, -- 32-bit input: Configuration data input bus
RDWRB => icap_rd_wrn -- 1-bit input: Read/Write Select input
);
-- End of ICAPE2_inst instantiation



scrubber: entity work.scrubber_ip
  generic map ( golden_parity_check => GOLDEN_PARITY_G )
  port map
    (
    clk                           => scrub_clk,
    clk_free                      => S_AXI_ACLK,
    icap_idle                     => icap_idle,
    test_dbg                      => test_dbg,
    core_live                     => core_live,
    reset                         => reset,
    -- Control Interface
    enable                        => not scan_pause,
    hold_correction               => hold_corr_g,
    test_freeze                   => test_freeze_g,
    icap_free                     => icap_free,
    detect_pulse                  => detect_pulse,
    correct_pulse                 => correct_pulse,
    diag_pulses                   => diag_pulses,
    golden_pmem_init              => '1',
    start_frame_addr              => "00" & x"000900",
    end_frame_addr                => "00" & X"401ba9",
    -- Status Interface
    status_state                  => open,
    heartbeat                     => open,
    scrub_diag                    => scrub_diag,
    pcalc_dbg                     => scrub_pcalc_dbg,
    -- ICAP primitive Interface
    icap_csn                      => icap_csn,
    icap_rd_wrn                   => icap_rd_wrn,
    icap_wrdata                   => icap_wrdata,
    icap_rddata                   => icap_rddata,
    icap_ready                    => icap_ready,
    icap_clk                      => icap_clk,
    -- FRAME ECC primitive Interface
    fecc_syndromevalid            => fecc_syndromevalid,
    fecc_eccerror                 => fecc_eccerror,
    fecc_syndrome                 => fecc_syndrome,
    fecc_crcerror                 => fecc_crcerror,
    fecc_far                      => fecc_far,
    fecc_synword                  => fecc_synword,
    fecc_synbit                   => fecc_synbit,
    fecc_eccerrorsingle           => fecc_eccerrorsingle,
    -- Fault Injection Interface
    inject_request               => inject_request,
    inject_grant                 => inject_grant,
    inject_start                 => inject_start,
    inject_stop                  => inject_stop,
    inject_write_command         => inject_write_command,
    inject_register_access       => inject_register_access,
    inject_desync                => inject_desync,
    inject_busy                  => inject_busy,
    inject_synced                => inject_synced,
    inject_data_in_fetch         => inject_data_in_fetch,
    inject_data_out_valid        => inject_data_out_valid,
    inject_frame_addr            => inject_frame_addr,
    inject_num_of_frames         => inject_num_of_frames,
    inject_cur_frame_index       => inject_cur_frame_index,
    inject_cur_word_index        => inject_cur_word_index,
    inject_data_in               => inject_data_in,
    inject_data_out              => inject_data_out
    );
injector: entity work.Fault_Injection_v1_0_S00_AXI port map(
----ICAP Arbiter Interface----
  icap_request        => inject_request,
  icap_grant          => inject_grant,
  icap_ready          => icap_ready,
  icap_start          => inject_start,
  icap_stop           => inject_stop,
  icap_write_command  => inject_write_command,
  icap_register_access=> inject_register_access,
  icap_desync         => inject_desync,
  icap_busy           => inject_busy,
  icap_synced         => inject_synced,
  icap_data_in_fetch  => inject_data_in_fetch,
  icap_data_out_valid => inject_data_out_valid,
  icap_frame_addr     => inject_frame_addr,
  icap_num_of_frames  => inject_num_of_frames,
  icap_current_frame_index=> inject_cur_frame_index,
  icap_current_word_index=> inject_cur_word_index,
  icap_data_in           => inject_data_in,
  icap_data_out=> inject_data_out,
----FRAME_ECC monitoring inputs (read-only status capture)----
  CRCERROR       => fecc_crcerror,
  ECCERROR       => fecc_eccerror,
  ECCERRORSINGLE => fecc_eccerrorsingle,
  FAR            => fecc_far,
  SYNBIT         => fecc_synbit,
  SYNDROME       => fecc_syndrome,
  SYNDROMEVALID  => fecc_syndromevalid,
  SYNWORD        => fecc_synword,
----Scrubber diagnostic status word (observation only)----
  DETECT_PULSE   => detect_pulse,
  CORRECT_PULSE  => correct_pulse,
  DIAG_PULSES    => diag_pulses,
  SCRUB_DIAG     => scrub_diag,
----Parity-calculator FSM diagnostic word (observation only)----
  PCALC_DBG      => scrub_pcalc_dbg,
----Reset-paradox diagnostic word (observation only)----
  RST_DBG        => rst_dbg,
  CORE_LIVE      => core_live,
----Runtime scan pause output (drives scrubber_ip enable)----
  SCAN_PAUSE     => scan_pause,
  HOLD_CORR      => hold_corr,
  FREEZE_CLK     => freeze_clk,
  TEST_FREEZE    => test_freeze,
  ICAP_FREE      => icap_free,
  ICAP_IDLE      => icap_idle,
		-- User ports ends
		-- Do not modify the ports beyond this line

		-- Global Clock Signal
		S_AXI_ACLK	=> S_AXI_ACLK,
		-- Global Reset Signal. This Signal is Active LOW
		S_AXI_ARESETN	=> S_AXI_ARESETN,
		-- Write address (issued by master, acceped by Slave)
		S_AXI_AWADDR	=> S_AXI_AWADDR,
		-- Write channel Protection type. This signal indicates the
    		-- privilege and security level of the transaction, and whether
    		-- the transaction is a data access or an instruction access.
		S_AXI_AWPROT	=> S_AXI_AWPROT,
		-- Write address valid. This signal indicates that the master signaling
    		-- valid write address and control information.
		S_AXI_AWVALID	=> S_AXI_AWVALID,
		-- Write address ready. This signal indicates that the slave is ready
    		-- to accept an address and associated control signals.
		S_AXI_AWREADY	=> S_AXI_AWREADY,
		-- Write data (issued by master, acceped by Slave)
		S_AXI_WDATA	=> S_AXI_WDATA,
		-- Write strobes. This signal indicates which byte lanes hold
    		-- valid data. There is one write strobe bit for each eight
    		-- bits of the write data bus.
		S_AXI_WSTRB	=> S_AXI_WSTRB,
		-- Write valid. This signal indicates that valid write
    		-- data and strobes are available.
		S_AXI_WVALID	=> S_AXI_WVALID,
		-- Write ready. This signal indicates that the slave
    		-- can accept the write data.
		S_AXI_WREADY	=> S_AXI_WREADY,
		-- Write response. This signal indicates the status
    		-- of the write transaction.
		S_AXI_BRESP	=> S_AXI_BRESP,
		-- Write response valid. This signal indicates that the channel
    		-- is signaling a valid write response.
		S_AXI_BVALID	=> S_AXI_BVALID,
		-- Response ready. This signal indicates that the master
    		-- can accept a write response.
		S_AXI_BREADY	=> S_AXI_BREADY,
		-- Read address (issued by master, acceped by Slave)
		S_AXI_ARADDR	=> S_AXI_ARADDR,
		-- Protection type. This signal indicates the privilege
    		-- and security level of the transaction, and whether the
    		-- transaction is a data access or an instruction access.
		S_AXI_ARPROT	=> S_AXI_ARPROT,
		-- Read address valid. This signal indicates that the channel
    		-- is signaling valid read address and control information.
		S_AXI_ARVALID	=> S_AXI_ARVALID,
		-- Read address ready. This signal indicates that the slave is
    		-- ready to accept an address and associated control signals.
		S_AXI_ARREADY	=> S_AXI_ARREADY,
		-- Read data (issued by slave)
		S_AXI_RDATA	=> S_AXI_RDATA,
		-- Read response. This signal indicates the status of the
    		-- read transfer.
		S_AXI_RRESP	=> S_AXI_RRESP,
		-- Read valid. This signal indicates that the channel is
    		-- signaling the required read data.
		S_AXI_RVALID	=> S_AXI_RVALID,
		-- Read ready. This signal indicates that the master can
    		-- accept the read data and response information.
		S_AXI_RREADY	=> S_AXI_RREADY
);
end Behavioral;
