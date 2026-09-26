-- SPDX-License-Identifier: MIT
-- Copyright (c) 2021-2026 John Vrachnis
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_arith.conv_std_logic_vector;
use work.log2_pkg.all;

library UNISIM;
use UNISIM.VComponents.all;

library work;
use work.all;
use work.icape_common.all;
use work.device_geometry_pkg.all;   -- 2026-09-03: FAR validity guard

entity Fault_Injection_v1_0_S00_AXI is
	generic (
		-- Users to add parameters here
        total_groups: integer:=228;
        mem_addr_width : integer := 7;
        mem_data_width : integer := 32;
        group_size : integer := 64;
        group_width : integer :=7;
        word_width : integer := 32;
        frame_size : integer := 101;
        frame_width : integer := 7;
      words_per_frame: integer:=101;
      bits_per_word: integer:=32;
      max_frames_per_group: integer:=64;
      subgroups_per_group: integer:=2;
      frame_addr_width: integer:=26;
		-- User parameters ends
		-- Do not modify the parameters beyond this line

		-- Width of S_AXI data bus
		C_S_AXI_DATA_WIDTH	: integer	:= 32;
		-- Width of S_AXI address bus
		C_S_AXI_ADDR_WIDTH	: integer	:= 5
	);
	port (
		-- Users to add ports here
--		CRCERROR       :in std_logic;  -- 1-bit output: Output indicating a CRC error.
--        ECCERROR       :in std_logic;  -- 1-bit output: Output indicating an ECC error.
--        ECCERRORSINGLE :in std_logic;  -- 1-bit output: Output Indicating single-bit Frame ECC error detected.
--        FAR            :in std_logic_vector(25 downto 0);  -- 26-bit output: Frame Address Register Value output.
--        SYNBIT         :in std_logic_vector(4 downto 0);  -- 5-bit output: Output bit address of error.
--        SYNDROME       :in std_logic_vector(12 downto 0);  -- 13-bit output: Output location of erroneous bit.
--        SYNDROMEVALID  :in std_logic;  -- 1-bit output: Frame ECC output indicating the SYNDROME output is
--      -- valid.
--        SYNWORD        :in std_logic_vector(6 downto 0);  -- 7-bit output: Word output in the frame where an ECC error has been);


----ICAP Arbiter Interface----
  icap_request        : out std_logic;
  icap_grant          : in std_logic;
  icap_start          : out std_logic;
  icap_ready          : out std_logic;
  icap_stop           : out std_logic;
  icap_write_command  : out std_logic;
  icap_register_access: out std_logic;
  icap_desync         : out std_logic;
  icap_busy           : in std_logic;
  icap_synced         : in std_logic;
  icap_data_in_fetch  : in std_logic;
  icap_data_out_valid : in std_logic;
  icap_frame_addr: out std_logic_vector(frame_addr_width-1 downto 0);
  icap_num_of_frames: out std_logic_vector(19 downto 0);
  icap_current_frame_index: in std_logic_vector(19 downto 0);
  icap_current_word_index: in std_logic_vector(log2(words_per_frame)-1 downto 0);
  icap_data_in: out std_logic_vector(bits_per_word-1 downto 0);
  icap_data_out: in std_logic_vector(bits_per_word-1 downto 0);
----FRAME_ECC monitoring inputs (read-only status capture)----
  CRCERROR       : in std_logic;                       -- 1-bit: CRC error indicator
  ECCERROR       : in std_logic;                       -- 1-bit: ECC error indicator
  ECCERRORSINGLE : in std_logic;                       -- 1-bit: single-bit Frame ECC error detected
  FAR            : in std_logic_vector(25 downto 0);   -- 26-bit: Frame Address Register value
  SYNBIT         : in std_logic_vector(4 downto 0);    -- 5-bit: bit address of error
  SYNDROME       : in std_logic_vector(12 downto 0);   -- 13-bit: location of erroneous bit
  SYNDROMEVALID  : in std_logic;                       -- 1-bit: SYNDROME output valid
  SYNWORD        : in std_logic_vector(6 downto 0);    -- 7-bit: word in frame where ECC error occurred
----Scrubber diagnostic status word (observation only)----
  SCRUB_DIAG     : in std_logic_vector(7 downto 0);    -- 8-bit: scrubber-core diagnostic word
----Parity-calculator FSM diagnostic word (observation only)----
  PCALC_DBG      : in std_logic_vector(7 downto 0);    -- 8-bit: parity_calculator FSM/handshake diag
----Reset-paradox diagnostic (observation only)----
  RST_DBG        : in std_logic_vector(4 downto 0);    -- 5-bit: recovery word (see wrapper)
  CORE_LIVE      : in std_logic_vector(31 downto 0) := (others => '0'); -- CTRL bit12 selects it at 0x1C
----Runtime scan pause (test/observability): 1 = pause continuous scan----
  SCAN_PAUSE     : out std_logic;                      -- slv_reg3(5): 1 pauses the scan-driver
  -- 2026-09: test-mode freeze. slv_reg3(6)=1 holds the CORRECTOR (not just the
  -- scan): syndromes are not presented to the handler, so no episode starts and
  -- nothing is written back. This is what makes genuinely concurrent multi-frame
  -- upsets stageable on silicon - the injector's own ICAP read would otherwise
  -- reveal each error and it would be corrected within microseconds, long before
  -- a second JTAG injection (~65 ms) could land.
  HOLD_CORR      : out std_logic;                      -- slv_reg3(6): 1 freezes correction
  TEST_FREEZE    : out std_logic;                      -- slv_reg3(7): 1 withdraws all scrubber ICAP requests
  -- 2026-09 CLOCK FREEZE (slv_reg3(11)). Gates the scrubber core's clock, so
  -- every register in it holds its exact value - the state is stopped where it
  -- stands, mid-correction if that is when it is asserted. The AXI interface
  -- and its counters stay on the free-running clock, so registers remain
  -- readable while the core is frozen. Intended sequence:
  --     assert -> core stops mid-episode -> plant the upset -> release
  -- and the correction resumes from exactly the cycle it was interrupted at.
  FREEZE_CLK     : out std_logic;
  ICAP_FREE      : in  std_logic := '0';               -- STATUS bit4: port available to the injector
  ICAP_IDLE      : in  std_logic := '0';               -- STATUS bit5: controller idle = safe freeze point
  -- 2026-09: single-cycle pulses from scrubber_ip. These replace the previous
  -- inference from ecc_captured / SCRUB_DIAG, which was acknowledge- and
  -- mode-dependent and under-counted badly (0-1 where N were expected).
  DETECT_PULSE   : in  std_logic := '0';
  CORRECT_PULSE  : in  std_logic := '0';
  DIAG_PULSES    : in  std_logic_vector(4 downto 0) := (others => '0');
		-- User ports ends
		-- Do not modify the ports beyond this line

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
		S_AXI_WDATA	: in std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
		-- Write strobes. This signal indicates which byte lanes hold
    		-- valid data. There is one write strobe bit for each eight
    		-- bits of the write data bus.
		S_AXI_WSTRB	: in std_logic_vector((C_S_AXI_DATA_WIDTH/8)-1 downto 0);
		-- Write valid. This signal indicates that valid write
    		-- data and strobes are available.
		S_AXI_WVALID	: in std_logic;
		-- Write ready. This signal indicates that the slave
    		-- can accept the write data.
		S_AXI_WREADY	: out std_logic;
		-- Write response. This signal indicates the status
    		-- of the write transaction.
		S_AXI_BRESP	: out std_logic_vector(1 downto 0);
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
end Fault_Injection_v1_0_S00_AXI;

architecture arch_imp of Fault_Injection_v1_0_S00_AXI is

	-- AXI4LITE signals
	signal axi_awaddr	: std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0);
	signal axi_awready	: std_logic;
	signal axi_wready	: std_logic;
	signal axi_bresp	: std_logic_vector(1 downto 0);
	signal axi_bvalid	: std_logic;
	signal axi_araddr	: std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0);
	signal axi_arready	: std_logic;
	signal axi_rdata	: std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal axi_rresp	: std_logic_vector(1 downto 0);
	signal axi_rvalid	: std_logic;

	-- Example-specific design signals
	-- local parameter for addressing 32 bit / 64 bit C_S_AXI_DATA_WIDTH
	-- ADDR_LSB is used for addressing 32/64 bit registers/memories
	-- ADDR_LSB = 2 for 32 bits (n downto 2)
	-- ADDR_LSB = 3 for 64 bits (n downto 3)
	constant ADDR_LSB  : integer := (C_S_AXI_DATA_WIDTH/32) +1;
	constant OPT_MEM_ADDR_BITS : integer := 2;
	------------------------------------------------
	---- Signals for user logic register space example
	--------------------------------------------------
	---- Number of Slave Registers 4
	signal slv_reg0	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal slv_reg1	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal slv_reg2	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal slv_reg3	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal slv_reg4	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal slv_reg5	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal slv_reg6	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal slv_reg7	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal slv_reg_rden	: std_logic;
	signal slv_reg_wren	: std_logic;
	signal reg_data_out	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal byte_index	: integer;

	--User component

     component fault_Injection
         generic(
            frame_width : integer := 7;
            words_per_frame: integer:=101;
            bits_per_word: integer:=32;
            max_frames_per_group: integer:=64;
            subgroups_per_group: integer:=2;
            frame_addr_width: integer:=26
         );
       Port (CLK         : in  std_logic;
        Start       : in  std_logic;
        desync       : in  std_logic;
        request      : in  std_logic;
        Busy        : out std_logic;
        synced      : out std_logic;
        Far_address_i : in  std_logic_vector(25 downto 0);
        Word_pos_i    : in  std_logic_vector(6 downto 0);
        Fault_Word_i  : in  std_logic_vector(31 downto 0);


          icap_request        : out std_logic;
  icap_grant          : in std_logic;
  icap_start          : out std_logic;
  icap_stop           : out std_logic;
  icap_write_command  : out std_logic;
  icap_register_access: out std_logic;
  icap_desync         : out std_logic;
  icap_busy           : in std_logic;
  icap_synced         : in std_logic;
  icap_data_in_fetch  : in std_logic;
  icap_data_out_valid : in std_logic;
  icap_frame_addr: out std_logic_vector(frame_addr_width-1 downto 0);
  icap_num_of_frames: out std_logic_vector(19 downto 0);
  icap_current_frame_index: in std_logic_vector(19 downto 0);
  icap_current_word_index: in std_logic_vector(log2(words_per_frame)-1 downto 0);
  icap_data_in: out std_logic_vector(bits_per_word-1 downto 0);
  icap_data_out: in std_logic_vector(bits_per_word-1 downto 0);
  rb_addr : in std_logic_vector(6 downto 0);
  rb_data : out std_logic_vector(bits_per_word-1 downto 0)
        );
     end component;
     component SCRUBBER is
  generic(
    mem_addr_width : integer := 7;
    mem_data_width : integer := 32
    );
  Port (
    CLK            :  in std_logic;

    Reset          :  in std_logic;
    Enable         :  in std_logic;

    Error          :  out std_logic;

    CRCERROR       :  in std_logic;
    ECCERROR       :  in std_logic;
    ECCERRORSINGLE :  in std_logic;
    FAR_delay_1    :  in std_logic_vector(25 downto 0);
    SYNDROME       :  in std_logic_vector(12 downto 0);
    SYNDROMEVALID  :  in std_logic;

    ICAPE_CSIB, ICAPE_RDWRB :  out std_logic;
    ICAPE_O       : in  std_logic_vector(31 downto 0);
    ICAPE_I       : out  std_logic_vector(31 downto 0)
   );
end component;

     --User signals
     signal Start,Busy,FI_Active,synced,desync,reset_fifo:std_logic:='0';--FI = Fault injection
     signal Far_address: std_logic_vector(25 downto 0);
     signal Word_pos: std_logic_vector(6 downto 0);
     signal Fault_Word: std_logic_vector(31 downto 0);
    signal  FAR_delay_1,FAR_delay_2                                 : std_logic_vector(25 downto 0);
    signal FI_ICAPE_O, FI_ICAPE_I,SB_ICAPE_O, SB_ICAPE_I : std_logic_vector(31 downto 0);
    signal FI_ICAPE_CSIB, FI_ICAPE_RDWRB,SB_ICAPE_CSIB, SB_ICAPE_RDWRB : std_logic;
    signal ICAPE_MUX_SELECT : std_logic;
    signal fifo_reg5_in,fifo_reg5_out :std_logic_vector(2 downto 0);
    signal fifo_reg6_in,fifo_reg6_out,fifo_reg7_in,fifo_reg7_out :std_logic_vector(25 downto 0);
    signal fifo_empty,fifo_full,Next_framme_ecc:std_logic:='0';
    -- Sticky FRAME_ECC capture (no FIFO): latch first qualifying event until acked
    signal ecc_captured : std_logic := '0';
    signal cap_flags    : std_logic_vector(2 downto 0)  := (others => '0');
    signal cap_far      : std_logic_vector(25 downto 0) := (others => '0');
    signal cap_syn      : std_logic_vector(25 downto 0) := (others => '0');
    -- 2026: hardware-timed latency instrumentation (10ns clock, us ticks)
    signal us_pre       : integer range 0 to 99 := 0;
    signal us_tick      : std_logic := '0';
    signal det_cnt      : std_logic_vector(18 downto 0) := (others => '0'); -- us, Start -> capture
    -- 2026-09 wide instrumentation. The 8-bit/10-bit counters above saturate and
    -- the frame counter outruns JTAG sampling, so these are 32-bit and read
    -- through a debug-select mux (slv_reg3[10:8]) on slv_reg7.
    signal us_timer     : std_logic_vector(31 downto 0) := (others => '0'); -- free-running us
    signal frames_ctr   : std_logic_vector(31 downto 0) := (others => '0');
    signal rb_data      : std_logic_vector(31 downto 0) := (others => '0');
    signal far_geom_ok, far_dynamic, far_ok : std_logic := '0';
    signal inj_reject_invalid, inj_reject_dynamic, start_d_g : std_logic := '0'; -- frame readback (CTRL bit13, word = 0x04) -- SYNDROMEVALID edges (any ICAP client), see scan_counter note
    signal det_ctr      : std_logic_vector(31 downto 0) := (others => '0'); -- capture events
    signal cor_ctr      : std_logic_vector(31 downto 0) := (others => '0'); -- corrections done
    signal t_det        : std_logic_vector(31 downto 0) := (others => '0'); -- us at last capture
    signal t_cor        : std_logic_vector(31 downto 0) := (others => '0'); -- us at last correction
    signal sv_d2        : std_logic := '0';
    signal dbg_word     : std_logic_vector(31 downto 0) := (others => '0');
    type   dcnt_t is array (0 to 4) of std_logic_vector(31 downto 0);
    signal dcnt         : dcnt_t := (others => (others => '0'));
    signal det_run      : std_logic := '0';
    signal cor_cnt      : std_logic_vector(9 downto 0) := (others => '0');  -- us, capture -> ec done
    signal cor_run      : std_logic := '0';
    signal start_d      : std_logic := '0';
    signal captured_d   : std_logic := '0';
    signal diag_done_d  : std_logic_vector(2 downto 0) := (others => '0');
    -- Self-contained scan-activity counter (per-frame, proves scrubber is scanning)
    signal scan_counter    : std_logic_vector(7 downto 0) := (others => '0');
    signal syndromevalid_d : std_logic := '0';
    attribute mark_debug                                                                                                                                                                                                                 : string;
--    attribute mark_debug of slv_reg0,slv_reg5,slv_reg6,slv_reg7,slv_reg_rden,axi_araddr,S_AXI_ARADDR : signal is "false";

--  attribute mark_debug of ECCERROR, CRCERROR, ECCERRORSINGLE, FAR,
--                          SYNBIT, SYNDROMEVALID, SYNWORD,SYNDROME,FAR_delay_1,FAR_delay_2 : signal is "true";
--  attribute mark_debug of fifo_empty,fifo_full,fifo_reg5_in,fifo_reg5_out,Next_framme_ecc: signal is "false";
begin
	-- I/O Connections assignments

	S_AXI_AWREADY	<= axi_awready;
	S_AXI_WREADY	<= axi_wready;
	S_AXI_BRESP	<= axi_bresp;
	S_AXI_BVALID	<= axi_bvalid;
	S_AXI_ARREADY	<= axi_arready;
	S_AXI_RDATA	<= axi_rdata;
	S_AXI_RRESP	<= axi_rresp;
	S_AXI_RVALID	<= axi_rvalid;
	-- Implement axi_awready generation
	-- axi_awready is asserted for one S_AXI_ACLK clock cycle when both
	-- S_AXI_AWVALID and S_AXI_WVALID are asserted. axi_awready is
	-- de-asserted when reset is low.

	process (S_AXI_ACLK)
	begin
	  if rising_edge(S_AXI_ACLK) then
	    if S_AXI_ARESETN = '0' then
	      axi_awready <= '0';
	    else
	      if (axi_awready = '0' and S_AXI_AWVALID = '1' and S_AXI_WVALID = '1') then
	        -- slave is ready to accept write address when
	        -- there is a valid write address and write data
	        -- on the write address and data bus. This design
	        -- expects no outstanding transactions.
	        axi_awready <= '1';
	      else
	        axi_awready <= '0';
	      end if;
	    end if;
	  end if;
	end process;

	-- Implement axi_awaddr latching
	-- This process is used to latch the address when both
	-- S_AXI_AWVALID and S_AXI_WVALID are valid.

	process (S_AXI_ACLK)
	begin
	  if rising_edge(S_AXI_ACLK) then
	    if S_AXI_ARESETN = '0' then
	      axi_awaddr <= (others => '0');
	    else
	      if (axi_awready = '0' and S_AXI_AWVALID = '1' and S_AXI_WVALID = '1') then
	        -- Write Address latching
	        axi_awaddr <= S_AXI_AWADDR;
	      end if;
	    end if;
	  end if;
	end process;

	-- Implement axi_wready generation
	-- axi_wready is asserted for one S_AXI_ACLK clock cycle when both
	-- S_AXI_AWVALID and S_AXI_WVALID are asserted. axi_wready is
	-- de-asserted when reset is low.

	process (S_AXI_ACLK)
	begin
	  if rising_edge(S_AXI_ACLK) then
	    if S_AXI_ARESETN = '0' then
	      axi_wready <= '0';
	    else
	      if (axi_wready = '0' and S_AXI_WVALID = '1' and S_AXI_AWVALID = '1') then
	          -- slave is ready to accept write data when
	          -- there is a valid write address and write data
	          -- on the write address and data bus. This design
	          -- expects no outstanding transactions.
	          axi_wready <= '1';
	      else
	        axi_wready <= '0';
	      end if;
	    end if;
	  end if;
	end process;

	-- Implement memory mapped register select and write logic generation
	-- The write data is accepted and written to memory mapped registers when
	-- axi_awready, S_AXI_WVALID, axi_wready and S_AXI_WVALID are asserted. Write strobes are used to
	-- select byte enables of slave registers while writing.
	-- These registers are cleared when reset (active low) is applied.
	-- Slave register write enable is asserted when valid address and data are available
	-- and the slave is ready to accept the write address and write data.
	slv_reg_wren <= axi_wready and S_AXI_WVALID and axi_awready and S_AXI_AWVALID ;

	process (S_AXI_ACLK)
	variable loc_addr :std_logic_vector(OPT_MEM_ADDR_BITS downto 0);
	begin
	  if rising_edge(S_AXI_ACLK ) then


	    if S_AXI_ARESETN = '0' then
	      slv_reg0 <= (others => '0');
	      slv_reg1 <= (others => '0');
	      slv_reg2 <= (others => '0');
	      slv_reg3 <= (others => '0');
	    elsif Busy='1' then
	       slv_reg3(2) <='0';
	    elsif Next_framme_ecc='1' then
	       slv_reg3(4) <='0';
	    else
				loc_addr := axi_awaddr(ADDR_LSB + OPT_MEM_ADDR_BITS downto ADDR_LSB);
	      if (slv_reg_wren = '1') then
	        case loc_addr is
	          when b"000" =>
	            for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
	              if ( S_AXI_WSTRB(byte_index) = '1' ) then
	                -- Respective byte enables are asserted as per write strobes
	                -- slave registor 0
	                slv_reg0(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
	              end if;
	            end loop;
	          when b"001" =>
	            for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
	              if ( S_AXI_WSTRB(byte_index) = '1' ) then
	                -- Respective byte enables are asserted as per write strobes
	                -- slave registor 1
	                slv_reg1(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
	              end if;
	            end loop;
	          when b"010" =>
	            for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
	              if ( S_AXI_WSTRB(byte_index) = '1' ) then
	                -- Respective byte enables are asserted as per write strobes
	                -- slave registor 2
	                slv_reg2(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
	              end if;
	            end loop;
	          when b"011" =>
                for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
                  if ( S_AXI_WSTRB(byte_index) = '1' ) then
                    -- Respective byte enables are asserted as per write strobes
                    -- slave registor 2
                    slv_reg3(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
                  end if;
                end loop;
	          when others =>
	            slv_reg0 <= slv_reg0;
	            slv_reg1 <= slv_reg1;
                slv_reg2 <= slv_reg2;
	        end case;
	      end if;
	    end if;
	  end if;
	end process;

	-- Implement write response logic generation
	-- The write response and response valid signals are asserted by the slave
	-- when axi_wready, S_AXI_WVALID, axi_wready and S_AXI_WVALID are asserted.
	-- This marks the acceptance of address and indicates the status of
	-- write transaction.

	process (S_AXI_ACLK)
	begin
	  if rising_edge(S_AXI_ACLK) then
	    if S_AXI_ARESETN = '0' then
	      axi_bvalid  <= '0';
	      axi_bresp   <= "00"; --need to work more on the responses
	    else
	      if (axi_awready = '1' and S_AXI_AWVALID = '1' and axi_wready = '1' and S_AXI_WVALID = '1' and axi_bvalid = '0'  ) then
	        axi_bvalid <= '1';
	        axi_bresp  <= "00";
	      elsif (S_AXI_BREADY = '1' and axi_bvalid = '1') then   --check if bready is asserted while bvalid is high)
	        axi_bvalid <= '0';                                 -- (there is a possibility that bready is always asserted high)
	      end if;
	    end if;
	  end if;
	end process;

	-- Implement axi_arready generation
	-- axi_arready is asserted for one S_AXI_ACLK clock cycle when
	-- S_AXI_ARVALID is asserted. axi_awready is
	-- de-asserted when reset (active low) is asserted.
	-- The read address is also latched when S_AXI_ARVALID is
	-- asserted. axi_araddr is reset to zero on reset assertion.

	process (S_AXI_ACLK)
	begin
	  if rising_edge(S_AXI_ACLK) then
	    if S_AXI_ARESETN = '0' then
	      axi_arready <= '0';
	      axi_araddr  <= (others => '1');
	    else
	      if (axi_arready = '0' and S_AXI_ARVALID = '1') then
	        -- indicates that the slave has acceped the valid read address
	        axi_arready <= '1';
	        -- Read Address latching
	        axi_araddr  <= S_AXI_ARADDR;
	      else
	        axi_arready <= '0';
	      end if;
	    end if;
	  end if;
	end process;

	-- Implement axi_arvalid generation
	-- axi_rvalid is asserted for one S_AXI_ACLK clock cycle when both
	-- S_AXI_ARVALID and axi_arready are asserted. The slave registers
	-- data are available on the axi_rdata bus at this instance. The
	-- assertion of axi_rvalid marks the validity of read data on the
	-- bus and axi_rresp indicates the status of read transaction.axi_rvalid
	-- is deasserted on reset (active low). axi_rresp and axi_rdata are
	-- cleared to zero on reset (active low).
	process (S_AXI_ACLK)
	begin
	  if rising_edge(S_AXI_ACLK) then
	    if S_AXI_ARESETN = '0' then
	      axi_rvalid <= '0';
	      axi_rresp  <= "00";
	    else
	      if (axi_arready = '1' and S_AXI_ARVALID = '1' and axi_rvalid = '0') then
	        -- Valid read data is available at the read data bus
	        axi_rvalid <= '1';
	        axi_rresp  <= "00"; -- 'OKAY' response
	      elsif (axi_rvalid = '1' and S_AXI_RREADY = '1') then
	        -- Read data is accepted by the master
	        axi_rvalid <= '0';
	      end if;
	    end if;
	  end if;
	end process;

	-- Implement memory mapped register select and read logic generation
	-- Slave register read enable is asserted when valid address is available
	-- and the slave is ready to accept the read address.
	slv_reg_rden <= axi_arready and S_AXI_ARVALID and (not axi_rvalid) ;

	process (slv_reg0, slv_reg1, slv_reg2, slv_reg3,slv_reg4,slv_reg5,slv_reg6,slv_reg7, dbg_word, axi_araddr, S_AXI_ARESETN, slv_reg_rden)
	variable loc_addr :std_logic_vector(OPT_MEM_ADDR_BITS downto 0);
	begin
		loc_addr := axi_araddr(ADDR_LSB + OPT_MEM_ADDR_BITS downto ADDR_LSB);
	    case loc_addr is
	      when b"000" =>
	        reg_data_out <= slv_reg0;
	      when b"001" =>
	        reg_data_out <= slv_reg1;
	      when b"010" =>
	        reg_data_out <= slv_reg2;
	      when b"011" =>
	        reg_data_out <= slv_reg3;
          when b"100" =>
            reg_data_out <= slv_reg4;
          when b"101" =>
	        reg_data_out <= slv_reg5;
	      when b"110" =>
	        reg_data_out <= slv_reg6;
	      when b"111" =>
	        -- 2026-09: CTRL[10:8] selects an instrumentation word here rather
	        -- than re-driving slv_reg7 (which the AXI write template already
	        -- drives). Select 0 returns the historical layout unchanged, so
	        -- every existing campaign script keeps working.
	        if slv_reg3(10 downto 8) = "000" then
	          reg_data_out <= slv_reg7;
	        else
	          reg_data_out <= dbg_word;
	        end if;
	      when others =>
	        reg_data_out  <= (others => '0');
	    end case;
	end process;

	-- Output register or memory read data
	process( S_AXI_ACLK ) is
	begin
	  if (rising_edge (S_AXI_ACLK)) then
	    if ( S_AXI_ARESETN = '0' ) then
	      axi_rdata  <= (others => '0');
	    else
	      if (slv_reg_rden = '1') then
	        -- When there is a valid read address (S_AXI_ARVALID) with
	        -- acceptance of read address by the slave (axi_arready),
	        -- output the read dada
	        -- Read address mux
	          axi_rdata <= reg_data_out;     -- register read data
	      end if;
	    end if;
	  end if;
	end process;


	-- Add user logic here

--	process(S_AXI_ACLK)
--    begin
--        if rising_edge(S_AXI_ACLK) then
--            if (SYNDROMEVALID='1') then
--                FAR_delay_1<=FAR;
--                FAR_delay_2<=FAR_delay_1;
----                slv_reg5(2 downto 0)<=ECCERRORSINGLE&ECCERROR&CRCERROR;
----                slv_reg6(25 downto 0)<=FAR_delay_2;
----                slv_reg7(25 downto 0)<=SYNDROME&SYNWORD&SYNBIT&SYNDROMEVALID;
--            end if;
--        end if;
--    end process;
    Next_framme_ecc<=slv_reg3(4);
    reset_fifo<=slv_reg3(4) or not S_AXI_ARESETN;
    SCAN_PAUSE<=slv_reg3(5);   -- 1 = pause continuous scan (test isolation)
    HOLD_CORR <=slv_reg3(6);   -- 1 = freeze the corrector (concurrent-upset staging)
    TEST_FREEZE<=slv_reg3(7);  -- 1 = full freeze: scrubber releases the ICAP entirely
    FREEZE_CLK <=slv_reg3(11); -- 1 = stop the scrubber core clock (state frozen exactly)
    -- Sticky FRAME_ECC capture replaces the (commented-out) STD_FIFO path.
    -- slv_reg5/6/7 are NOT written by the AXI write/reset process, so these
    -- continuous assignments are the single driver for those registers.
    -- cap_flags = ECCERRORSINGLE & ECCERROR & CRCERROR ; cap_syn = zero-extended SYNDROME(12:0).
    slv_reg5(2 downto 0)   <= cap_flags;
    slv_reg5(18 downto 3)  <= (others => '0');
    -- 0x14 bits[23:19] = reset-paradox diagnostic word (observation only)
    slv_reg5(23 downto 19) <= RST_DBG;
    -- 0x14 bits[31:24] = parity_calculator FSM diagnostic word (observation only)
    slv_reg5(31 downto 24) <= PCALC_DBG;
    slv_reg6(25 downto 0)  <= cap_far;
    slv_reg6(31 downto 26) <= (others => '0');
    -- slv_reg7: sel 0 preserves the historical layout (cap_syn in [12:0]);
    -- other selects return a full 32-bit instrumentation word.
    dbg_word <= rb_data    when slv_reg3(13) = '1' else
                CORE_LIVE  when slv_reg3(12) = '1' else
                us_timer   when slv_reg3(10 downto 8) = "001" else
                frames_ctr when slv_reg3(10 downto 8) = "010" else
                dcnt(0)    when slv_reg3(10 downto 8) = "011" else
                dcnt(1)    when slv_reg3(10 downto 8) = "100" else
                dcnt(2)    when slv_reg3(10 downto 8) = "101" else
                dcnt(3)    when slv_reg3(10 downto 8) = "110" else
                dcnt(4)    when slv_reg3(10 downto 8) = "111" else
                (others => '0');
    slv_reg7(25 downto 13) <= det_cnt(12 downto 0);
    slv_reg7(31 downto 26) <= det_cnt(18 downto 13);
    slv_reg7(12 downto 0)  <= cap_syn(12 downto 0);

    -- STATUS (slv_reg4) bit3 = fifo_empty: 1 = no ECC event captured, 0 = event captured/held.
    fifo_empty <= not ecc_captured;

    -- Sticky latch: hold the FIRST qualifying ECC event until acked via slv_reg3(4)
    -- (Next_framme_ecc). Survives the ms-scale PS/JTAG poll gap.
    ecc_capture_proc : process(S_AXI_ACLK)
    begin
        if rising_edge(S_AXI_ACLK) then
            if (S_AXI_ARESETN = '0') or (Next_framme_ecc = '1') then
                ecc_captured <= '0';
                cap_flags    <= (others => '0');
                cap_far      <= (others => '0');
                cap_syn      <= (others => '0');
            elsif (ecc_captured = '0') and (SYNDROMEVALID = '1') and
                  (ECCERROR = '1' or CRCERROR = '1' or SYNDROME /= "0000000000000") then
                ecc_captured <= '1';
                cap_flags    <= ECCERRORSINGLE & ECCERROR & CRCERROR;
                cap_far      <= FAR;
                cap_syn      <= (others => '0');
                cap_syn(12 downto 0) <= SYNDROME;   -- zero-extend 13-bit syndrome into 26-bit reg
            end if;
        end if;
    end process;

    -- 2026: latency instrumentation. det_cnt (us) runs from the inject Start
    -- pulse until the sticky capture latches (detection latency, up to ~0.5 s);
    -- cor_cnt (us) runs from the capture until the error_correction_done event
    -- counter in SCRUB_DIAG[6:4] next changes (correction latency, up to ~1 ms
    -- exposed in 4 us units). Values freeze until the next Start / capture.
    lat_proc : process(S_AXI_ACLK)
    begin
        if rising_edge(S_AXI_ACLK) then
            if S_AXI_ARESETN = '0' then
                us_pre <= 0; us_tick <= '0';
                det_cnt <= (others=>'0'); det_run <= '0';
                us_timer <= (others=>'0'); frames_ctr <= (others=>'0');
                det_ctr <= (others=>'0'); cor_ctr <= (others=>'0');
                t_det <= (others=>'0'); t_cor <= (others=>'0'); sv_d2 <= '0';
                cor_cnt <= (others=>'0'); cor_run <= '0';
                start_d <= '0'; captured_d <= '0'; diag_done_d <= (others=>'0');
            else
                if us_pre = 99 then us_pre <= 0; us_tick <= '1';
                else us_pre <= us_pre + 1; us_tick <= '0'; end if;
                -- 2026-09 wide instrumentation
                if us_tick = '1' then us_timer <= us_timer + 1; end if;
                sv_d2 <= SYNDROMEVALID;
                if SYNDROMEVALID = '1' and sv_d2 = '0' then frames_ctr <= frames_ctr + 1; end if;
                if DETECT_PULSE = '1' then
                    det_ctr <= det_ctr + 1; t_det <= us_timer;
                end if;
                if CORRECT_PULSE = '1' then
                    cor_ctr <= cor_ctr + 1; t_cor <= us_timer;
                end if;
                for i in 0 to 4 loop
                    if DIAG_PULSES(i) = '1' then dcnt(i) <= dcnt(i) + 1; end if;
                end loop;
                start_d     <= slv_reg3(2);   -- 2026 fix: gate directly on the
                -- register bit; the Start signal is conditioned elsewhere and
                -- its edge was unreliable (detect counter never reset/stopped).
                captured_d  <= ecc_captured;
                diag_done_d <= SCRUB_DIAG(6 downto 4);
                if slv_reg3(2) = '1' and start_d = '0' then
                    det_run <= '1'; det_cnt <= (others=>'0');
                elsif ecc_captured = '1' and captured_d = '0' then
                    det_run <= '0';
                    cor_run <= '1'; cor_cnt <= (others=>'0');
                elsif det_run = '1' and us_tick = '1' and det_cnt /= "1111111111111111111" then
                    det_cnt <= det_cnt + 1;
                end if;
                if cor_run = '1' then
                    if SCRUB_DIAG(6 downto 4) /= diag_done_d then
                        cor_run <= '0';
                    elsif us_tick = '1' and cor_cnt /= "1111111111" then
                        cor_cnt <= cor_cnt + 1;
                    end if;
                end if;
            end if;
        end if;
    end process;

    -- Free-running scan-activity counter: increments once per rising edge of
    -- SYNDROMEVALID (i.e. once per frame the scrubber reads back). Reset ONLY on
    -- hard reset (S_AXI_ARESETN='0'), NOT on the ecc ack. Reading STATUS twice a
    -- moment apart and seeing bits[15:8] change proves the scrubber is scanning.
    scan_counter_proc : process(S_AXI_ACLK)
    begin
        if rising_edge(S_AXI_ACLK) then
            if (S_AXI_ARESETN = '0') then
                scan_counter    <= (others => '0');
                syndromevalid_d <= '0';
            else
                syndromevalid_d <= SYNDROMEVALID;
                if (SYNDROMEVALID = '1') and (syndromevalid_d = '0') then
                    scan_counter <= scan_counter + 1;   -- free-running 8-bit wrap
                end if;
            end if;
        end if;
    end process;
--    fifo_reg5_in(2 downto 0)<=ECCERRORSINGLE&ECCERROR&CRCERROR;
--    fifo_reg6_in(25 downto 0)<=FAR_delay_2;
--    fifo_reg7_in(12 downto 0)<=SYNDROME;
--     STD_FIFO_reg5 :STD_FIFO
--        Generic map (
--            DATA_WIDTH=>3,
--            FIFO_DEPTH	=> 64
--        )
--        Port map(
--            CLK		=>S_AXI_ACLK,
--            RST		=>reset_fifo,
--            WriteEn	=>SYNDROMEVALID,
--            DataIn	=>fifo_reg5_in,
--            ReadEn	=>Next_framme_ecc,
--            DataOut	=>fifo_reg5_out,
--            Empty	=>fifo_empty,
--            Full	=>fifo_full
--        );
--    STD_FIFO_reg6 :STD_FIFO
--        Generic map (
--            DATA_WIDTH=>26,
--            FIFO_DEPTH	=> 64
--        )
--        Port map(
--            CLK		=>S_AXI_ACLK,
--            RST		=>reset_fifo,
--            WriteEn	=>SYNDROMEVALID,
--            DataIn	=>fifo_reg6_in,
--            ReadEn	=>Next_framme_ecc,
--            DataOut	=>fifo_reg6_out,
--            Empty	=>open,
--            Full	=>open
--        );
--    STD_FIFO_reg7 :STD_FIFO
--        Generic map (
--            DATA_WIDTH=>13,
--            FIFO_DEPTH	=> 64
--        )
--        Port map(
--            CLK		=>S_AXI_ACLK,
--            RST		=>reset_fifo,
--            WriteEn	=>SYNDROMEVALID,
--            DataIn	=>fifo_reg7_in(12 downto 0),
--            ReadEn	=>Next_framme_ecc,
--            DataOut	=>fifo_reg7_out(12 downto 0),
--            Empty	=>open,
--            Full	=>open
--        );
        process(S_AXI_ACLK)
        begin
            if rising_edge(S_AXI_ACLK) then

                icap_ready <=slv_reg3(0);
                icap_request<=slv_reg3(1);
                -- 2026-09-03 injector guard (FINDINGS 18): a read-modify-write at an
                -- address that is not a real, static configuration frame corrupts
                -- its neighbours (invalid minor) or the PS bus (columns 19-24 hold
                -- the AXI interconnect's SRL FIFOs). Refuse such a Start and latch
                -- the reason in STATUS[7:6]: 6 = invalid frame, 7 = dynamic column.
                Start <= slv_reg3(2) and far_ok;
                if slv_reg3(2) = '1' and start_d_g = '0' then
                    inj_reject_invalid <= not far_geom_ok;
                    inj_reject_dynamic <= far_geom_ok and far_dynamic;
                end if;
                start_d_g <= slv_reg3(2);
                desync<=slv_reg3(3);
                Far_address<=slv_reg0(25 downto 0);
                Word_pos<=slv_reg1(6 downto 0);
                Fault_Word<=slv_reg2;
            end if;
        end process;


        fault_Injection_inst :fault_Injection
          Port map(CLK =>S_AXI_ACLK,
                  Start=>Start,
                  desync=>desync,
                  request=>'0',
                  Busy=>Busy,
                  synced=>synced,
                  Far_address_i=>Far_address,
                  Word_pos_i=>Word_pos,
                  Fault_Word_i=>Fault_Word,
                    icap_request=>open,
                    icap_grant=>icap_grant,
                    icap_start=>icap_start,
                    icap_stop=>icap_stop,
                    icap_write_command=>icap_write_command,
                    icap_register_access=>icap_register_access,
                    icap_busy     =>icap_busy,
                    icap_synced   =>icap_synced,
                    icap_desync   =>icap_desync,
                    icap_data_in_fetch =>icap_data_in_fetch,
                    icap_data_out_valid =>icap_data_out_valid,

                    icap_frame_addr =>icap_frame_addr,
                    icap_num_of_frames =>icap_num_of_frames,
                    icap_current_frame_index=>icap_current_frame_index,
                    icap_current_word_index =>icap_current_word_index,

                    icap_data_in =>icap_data_in,
                    icap_data_out=>icap_data_out,
                    rb_addr => slv_reg1(6 downto 0),
                    rb_data => rb_data
                  );
        slv_reg4(3 downto 0)<=fifo_empty & fifo_full& Busy & synced;
    -- STATUS scan-activity: bits[7:4]=0 (reserved), bits[15:8]=scan_counter,
    -- bits[31:16]=0. scan_counter counts SYNDROMEVALID rising edges in the AXI
    -- domain: every frame read through the ICAP by ANY client, the injector's own
    -- read-modify-write included. It is a config-port activity counter, not a
    -- scrubber progress counter (2026-09-03 review, item 5).
    slv_reg4(4)            <= ICAP_FREE;      -- 2026-09: safe-to-inject indicator
    slv_reg4(5)            <= ICAP_IDLE;
    slv_reg4(6)            <= inj_reject_invalid;   -- last Start refused: not a real frame
    slv_reg4(7)            <= inj_reject_dynamic;   -- last Start refused: dynamic (AXI SRL) column

    -- FAR validity: block type 0, row 0, column < 56, minor within the measured
    -- per-column count; dynamic columns 19..24 (both halves) are refused too.
    far_validity_p : process(slv_reg0)
      variable col, minor : integer;
    begin
      col   := conv_integer(slv_reg0(16 downto 7));
      minor := conv_integer(slv_reg0(6 downto 0));
      far_geom_ok <= '0'; far_dynamic <= '0';
      if slv_reg0(25 downto 23) = "000" and slv_reg0(21 downto 17) = "00000" and col < 56 then
        if slv_reg0(22) = '0' then
          if minor < top_col_minors_c(col) then far_geom_ok <= '1'; end if;
        else
          if minor < bot_col_minors_c(col) then far_geom_ok <= '1'; end if;
        end if;
        if col >= 19 and col <= 24 then far_dynamic <= '1'; end if;
      end if;
    end process;
    far_ok <= far_geom_ok and not far_dynamic;
    slv_reg4(15 downto 8)  <= scan_counter;
    -- STATUS bits[23:16] = scrubber-core diagnostic word (observation only).
    slv_reg4(23 downto 16) <= SCRUB_DIAG;
    slv_reg4(31 downto 24) <= cor_cnt(9 downto 2);  -- 2026: correction latency, 4 us units
	-- User logic ends

end arch_imp;
