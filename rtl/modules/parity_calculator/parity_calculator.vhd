-- SPDX-License-Identifier: MIT
-- Copyright (c) 2020-2026 John Vrachnis
----------------------------------------------------------------------------------
-- Company:
-- Engineer:
--
-- Create Date: 09/14/2020 02:37:28 PM
-- Design Name:
-- Module Name: parity_calculator - rtl
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


library IEEE;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_arith.conv_std_logic_vector;
use work.log2_pkg.all;

entity parity_calculator is
  generic(
  tmr_en                : boolean := true;  -- 2026-09-03 hardness A/B
  words_per_frame: integer:=101;
  bits_per_word: integer:=32;
  max_frames_per_group: integer:=64;
  subgroups_per_group: integer:=2;
  frame_addr_width: integer:=26;
  pre_initialized : std_logic:='0'
  );
  Port (
  ----Control Interface----
  clk                   : in std_logic;
  reset                 : in std_logic;
  start_frame_addr      : in std_logic_vector(frame_addr_width-1 downto 0);
  end_frame_addr        : in std_logic_vector(frame_addr_width-1 downto 0);
  ----FRAME ECC primitive Interface----
  fecc_far              : in std_logic_vector(frame_addr_width-1 downto 0);
  ----Syndromes Handler Interface----
  group_frame_addr      : in std_logic_vector(frame_addr_width-1 downto 0);
  start_parity_calc     : in std_logic;
  parity_calc_done      : out std_logic;
  parity_initialized    : out std_logic;
  -- 2026 hardening: asserted with parity_calc_done when the pass consumed a
  -- golden word that failed its parity check. The pass result (calc memory
  -- contents) must not be used for correction; `initialized` is dropped in
  -- the same cycle, triggering a full golden re-init sweep.
  parity_poisoned       : out std_logic;
  ----Golden Parity Memory Interface----
  pmem_word_write         : out std_logic;
  pmem_new_frame_write    : out std_logic;
  pmem_group_wr_addr      : out std_logic_vector(frame_addr_width-1 downto 0);
  pmem_subgroup_wr_addr   : out std_logic_vector(log2(subgroups_per_group)-1 downto 0);
  pmem_word_wr_data       : out std_logic_vector(bits_per_word-1 downto 0);
  pmem_word_read          : out std_logic;
  pmem_new_frame_read     : out std_logic;
  pmem_group_rd_addr      : out std_logic_vector(frame_addr_width-1 downto 0);
  pmem_subgroup_rd_addr   : out std_logic_vector(log2(subgroups_per_group)-1 downto 0);
  pmem_word_rd_valid      : in std_logic;
  pmem_word_rd_data       : in std_logic_vector(bits_per_word-1 downto 0);
  -- 2026 hardening: byte-parity error flag from the golden parity memory,
  -- aligned with pmem_word_rd_data.
  pmem_word_rd_perr       : in std_logic := '0';
  -- simulation-only TMR fault hook: rising edge flips copy A of `initialized`
  sim_flip_tmr            : in std_logic := '0';
  -- 2026-09-01: high while the WATCHDOG is asserting its recovery reset.
  -- The golden parity store lives in BRAM and survives a soft reset, so the
  -- watchdog must NOT force a golden re-init: rebuilding golden from
  -- configuration memory that may still hold an uncorrected upset LEARNS THAT
  -- UPSET AS GOLDEN, after which calc = golden XOR current = 0 and the frame
  -- is permanently uncorrectable. Keep `initialized` through the soft reset
  -- and resume scrubbing against the golden we already trust.
  preserve_init           : in std_logic := '0';

  ----Calculated Parity Memory Interface----
  calc_word_read          : out std_logic;
  calc_word_rd_addr       : out std_logic_vector(log2(words_per_frame)-1 downto 0);
  calc_subgroup_rd_addr   : out std_logic_vector(log2(subgroups_per_group)-1 downto 0);
  calc_word_rd_data       : in std_logic_vector(bits_per_word-1 downto 0);
  calc_word_write         : out std_logic;
  calc_word_wr_addr       : out std_logic_vector(log2(words_per_frame)-1 downto 0);
  calc_subgroup_wr_addr   : out std_logic_vector(log2(subgroups_per_group)-1 downto 0);
  calc_word_wr_data       : out std_logic_vector(bits_per_word-1 downto 0);

  ----ICAP Arbiter Interface----
  icap_request             : out std_logic;
  icap_grant               : in std_logic;
  icap_start               : out std_logic;
  icap_stop                : out std_logic;
  icap_write_command       : out std_logic;
  icap_register_access     : out std_logic;
  icap_desync              : out std_logic;
  icap_busy                : in std_logic;
  icap_synced              : in std_logic;
  icap_data_in_fetch       : in std_logic;
  icap_data_out_valid      : in std_logic;
  icap_frame_addr          : out std_logic_vector(frame_addr_width-1 downto 0);
  icap_num_of_frames       : out std_logic_vector(19 downto 0); --change(1)
  -- 2026: bounded scan passes. Nonzero = exact frame count for this pass
  -- (from the measured column geometry); 0 = legacy unbounded read.
  pass_frames              : in  std_logic_vector(19 downto 0) := (others => '0');
  icap_current_frame_index : in std_logic_vector(19 downto 0); --change(1)
  icap_current_word_index  : in std_logic_vector(log2(words_per_frame)-1 downto 0);
  icap_data_in             : out std_logic_vector(bits_per_word-1 downto 0);
  icap_data_out            : in std_logic_vector(bits_per_word-1 downto 0);
  ----Diagnostic Interface (observation only)----
  pcalc_dbg                : out std_logic_vector(7 downto 0)

  );
end parity_calculator;

architecture rtl of parity_calculator is

 -- types --
 type   state_t is (idle, read_mem ,parity_calc, stop_read_mem);

 ---- group change detection ----
 -- the group is determent by the msb of fecc_far
 signal next_far                   : std_logic_vector(frame_addr_width-1 downto 0);
 signal current_far                : std_logic_vector(frame_addr_width-1 downto 0);
 signal delay_far                  : std_logic_vector(frame_addr_width-1 downto 0);
 signal locked_far                 : std_logic_vector(frame_addr_width-1 downto 0);

 signal next_far_group             : std_logic_vector(frame_addr_width-log2(max_frames_per_group)-1 downto 0);
 signal current_far_group          : std_logic_vector(frame_addr_width-log2(max_frames_per_group)-1 downto 0);
 signal icap_busy_d           : std_logic := '0';
signal delay_far_group            : std_logic_vector(frame_addr_width-log2(max_frames_per_group)-1 downto 0);
 signal locked_far_group           : std_logic_vector(frame_addr_width-log2(max_frames_per_group)-1 downto 0);

 signal next_subgroup              : std_logic_vector(log2(subgroups_per_group)-1 downto 0);
 signal current_subgroup           : std_logic_vector(log2(subgroups_per_group)-1 downto 0);
 signal delay_subgroup             : std_logic_vector(log2(subgroups_per_group)-1 downto 0);
 signal locked_subgroup            : std_logic_vector(log2(subgroups_per_group)-1 downto 0);
 signal next_far_group_change      : std_logic;
 ---- state machine ----
 signal current_state               : state_t := idle;
-- 2026 hardening: recover from SEU-induced illegal FSM states via Hamming-
-- distance-protected safe-state encoding (Vivado synthesis attribute).
attribute fsm_safe_state : string;
attribute fsm_safe_state of current_state : signal is "reset_state";
 signal next_state                  : state_t := idle;
 ---- status ----
 -- 2026 hardening: `initialized` is TMR'd with a feedback voter. A 0->1 flip
 -- during the init sweep would truncate golden silently (parity-consistent,
 -- wrong content -> wrong corrections); a 1->0 flip costs a spurious 15 ms
 -- re-init. Three DONT_TOUCH copies; every read uses the majority vote; each
 -- copy re-samples the vote every cycle so a flipped copy heals in 1 cycle.
 signal initialized                 : std_logic;   -- voted (combinational)
 signal initialized_a               : std_logic := pre_initialized;
 signal initialized_b               : std_logic := pre_initialized;
 signal initialized_c               : std_logic := pre_initialized;
 attribute DONT_TOUCH : string;
 attribute DONT_TOUCH of initialized_a : signal is "true";
 attribute DONT_TOUCH of initialized_b : signal is "true";
 attribute DONT_TOUCH of initialized_c : signal is "true";
 -- 2026 hardening: sticky per-pass golden-parity-error flag
 signal pass_poisoned               : std_logic := '0';
 signal poison_events               : std_logic_vector(1 downto 0) := "00";
 signal initialized_frame_of_group  : std_logic_vector(log2(subgroups_per_group)-1 downto 0);

 
 signal calc_word_rd_addr_i         : std_logic_vector(log2(words_per_frame)-1 downto 0);
 signal start_calc                  : std_logic;
 ---- diagnostic (observation only) ----
 -- internal mirror of the icap_request output so it can be observed on pcalc_dbg
 signal icap_request_i              : std_logic;
 
 
 --change(7)
 --signal next_word_subgroup          : std_logic_vector(log2(subgroups_per_group)-1 downto 0);
 --signal next_word_index             : std_logic_vector(log2(words_per_frame)-1 downto 0);
 --signal pmem_group_wr_addr_l        : std_logic_vector(frame_addr_width-1 downto 0);
 --signal pmem_subgroup_wr_addr_l     : std_logic_vector(log2(subgroups_per_group)-1 downto 0);
 --signal pmem_group_rd_addr_l        : std_logic_vector(frame_addr_width-1 downto 0);
 --signal pmem_subgroup_rd_addr_l     : std_logic_vector(log2(subgroups_per_group)-1 downto 0);
 --signal calc_word_wr_addr_l         : std_logic_vector(log2(words_per_frame)-1 downto 0);
 --signal calc_subgroup_wr_addr_l     : std_logic_vector(log2(subgroups_per_group)-1 downto 0);

-- attribute mark_debug : string;
 attribute mark_debug : string;
 attribute mark_debug of locked_far,pmem_word_rd_data,pmem_word_rd_valid,pmem_word_rd_perr,calc_word_rd_data,calc_word_wr_data,calc_word_write,calc_word_wr_addr,calc_subgroup_wr_addr,calc_word_read,calc_word_rd_addr,icap_data_out,icap_current_word_index,pass_poisoned: signal is "true";

begin
  -------------------------------------------------------------------------------
  -- Internal Signal Assignments
  -------------------------------------------------------------------------------
 initialized           <= ((initialized_a and initialized_b)
                       or (initialized_a and initialized_c)
                       or (initialized_b and initialized_c)) when tmr_en else initialized_a;  -- TMR majority
 parity_initialized    <= initialized;
 parity_poisoned       <= pass_poisoned;
 -- Diagnostic word (OBSERVATION ONLY): FSM state + ICAP handshake as seen here.
 -- icap_request is driven through the internal mirror icap_request_i (net alias),
 -- so the FSM/scan/ICAP behavior is unchanged.
 icap_request <= icap_request_i;
 with current_state select
   pcalc_dbg(2 downto 0) <= "000" when idle,
                            "001" when read_mem,
                            "010" when parity_calc,
                            "011" when stop_read_mem;
 pcalc_dbg(3) <= initialized;
 pcalc_dbg(4) <= icap_grant;
 pcalc_dbg(5) <= icap_synced;
 pcalc_dbg(6) <= icap_busy;
 pcalc_dbg(7) <= icap_request_i;
 icap_num_of_frames    <= (others => '1') when (initialized = '0' or pass_frames = conv_std_logic_vector(0,20))
                          else pass_frames;
 icap_write_command    <= '0';
 icap_register_access  <= '0';
 icap_data_in          <= (others =>'0');
 
 -- removed the local signals and outputing directy to the interface signals change(7)
 --calc_word_wr_addr     <= calc_word_wr_addr_l;
 --calc_subgroup_wr_addr <= calc_subgroup_wr_addr_l;

 --calc_word_rd_addr     <= next_word_index;
 --calc_subgroup_rd_addr <= next_word_subgroup;

 --pmem_group_wr_addr    <= pmem_group_wr_addr_l;
 --pmem_subgroup_wr_addr <= pmem_subgroup_wr_addr_l;
 --pmem_group_rd_addr    <= pmem_group_rd_addr_l;
 --pmem_subgroup_rd_addr <= pmem_subgroup_rd_addr_l;



 state_transition:process(clk)
 begin
  if rising_edge(clk) then
   if reset='1' then
    current_state <= idle;
   else
    current_state <= next_state;
   end if;
  end if;
 end process;
  state_machine:process(current_state,initialized,start_parity_calc,pass_poisoned,icap_current_word_index,icap_busy,icap_busy_d,icap_grant,next_far,end_frame_addr,next_far_group_change,icap_synced,pass_frames)
  begin
    next_state <= current_state;
    case current_state is
      when idle =>
        -- automaticaly start golden parity calculation if the memory hasnt been initialized
        -- or wait for external signal to start_parity_calc to calculate the temp
        -- parity frame for the given group
        if (initialized = '0' or start_parity_calc ='1') and pass_poisoned = '0' then
          -- 2026 hardening: hold in idle while a pending poison flag is being
          -- consumed (the clocked side drops `initialized` that cycle and
          -- must not miss raising the arbiter request for the re-init pass).
          next_state <= read_mem;
        end if;
      when read_mem =>
        -- wait for the icape to finish reading the dummy frame then move to parity
        -- calculation some memory preparetion/ syncronization is been done
        -- at this state because the memory has a 5 cycle delay to give the first
        -- requested entry
        if icap_current_word_index = words_per_frame-1
           and icap_busy  = '1'
           and icap_grant = '1' then
          next_state <= parity_calc;
        end if;
      when parity_calc =>
        -- calculating the parity frame(s) depeding if the memory was
        -- been initialized or not it will initialze here
        -- or it will calculate the temp parity frame for the given group
        if initialized = '1'
           and icap_current_word_index = words_per_frame-1
           and next_far_group_change = '1' then
            next_state <= stop_read_mem;
        elsif icap_current_word_index=words_per_frame-1
              and next_far = end_frame_addr then
            next_state <= stop_read_mem;
        -- 2026: bounded pass completed - the controller read exactly the
        -- requested frame count (measured geometry), including the
        -- column-last frame the boundary detection used to cut off.
        elsif initialized = '1' and pass_frames /= conv_std_logic_vector(0,20)
              and icap_busy = '0' and icap_busy_d = '1' then
            next_state <= stop_read_mem;
        end if;
      when stop_read_mem =>
        -- its waiting for the icape to be desyncronised safely
        if icap_synced='0' then
          next_state <= idle;
        end if;
    end case;
  end process;
 main:process(clk)
 -- synthesis translate_off
 variable flip_d : std_logic := '0';
 -- synthesis translate_on
 begin
  if rising_edge(clk) then
   if reset = '1' then
    if preserve_init = '0' then
      initialized_a      <= pre_initialized;
      initialized_b      <= pre_initialized;
      initialized_c      <= pre_initialized;
    end if;
    pass_poisoned        <= '0';
    next_far_group_change<= '0';
    icap_request_i       <= '1';
    icap_start           <= '0';
    icap_desync          <= '0';
    icap_stop            <= '0';
    parity_calc_done     <= '0';
    pmem_word_read       <= '0';
    pmem_new_frame_write <= '0';
    pmem_new_frame_read  <= '0';
    pmem_word_write      <= '0';
    calc_word_write      <= '0';
    calc_word_wr_data    <= (others =>'0');
    pmem_word_wr_data    <= (others =>'0');
    current_far          <= (others =>'0');
    current_subgroup     <= (others =>'0');
    calc_subgroup_rd_addr<= (others =>'0');
    calc_word_rd_addr    <= (others =>'0');
    pmem_group_wr_addr   <= (others =>'0');
    pmem_subgroup_wr_addr<= (others =>'0');
    pmem_group_rd_addr   <= (others =>'0');
    pmem_subgroup_rd_addr<= (others =>'0');
    calc_word_wr_addr    <= (others =>'0');
    calc_subgroup_wr_addr<= (others =>'0');
    calc_word_rd_addr_i  <= (others =>'0');
    start_calc           <= '0';
    initialized_frame_of_group <= (others =>'0');
   else
    -- default values --
    -- TMR feedback: every copy re-samples the majority vote each cycle, so a
    -- flipped copy is scrubbed within one cycle. Specific assignments below
    -- override (last assignment wins within a process).
    initialized_a        <= initialized;
    initialized_b        <= initialized;
    initialized_c        <= initialized;

    parity_calc_done     <= '0';
    icap_desync          <= '0';
    icap_stop            <= '0';
    pmem_new_frame_write <= '0';
    pmem_new_frame_read  <= '0';
    pmem_word_write      <= '0';
    calc_word_write      <= '0';
    ---- group change detection ----
    -- detecting the group change is important to bring the next group frame
    -- from the memory --allowd the change(1) to happen easier
    -- 2026 fix: the flag used to auto-clear on the next same-group FAR step.
    -- On silicon, column crossings insert a pad-frame FAR step and pipeline
    -- stalls shift word_index so the (word_index=100 AND change) exit window
    -- closed one cycle before word_index arrived - passes overran their group
    -- into invalid FAR space, flooding the handler with garbage 0x0653 entries
    -- every sweep (ILA-measured). The flag is now sticky until consumed.
    if delay_far /= next_far then
      -- sticky group-change flag: backstop exit for unbounded passes. Note the
      -- FAR leads the streamed frame by one, so this exit cuts off the
      -- column-last frame; bounded passes (pass_frames /= 0, from the measured
      -- geometry) end on op completion instead and include it.
      if delay_far_group /= next_far_group then
        next_far_group_change <= '1';
      end if;
    end if;
    -- calculating the next word index so it can be pre-loaded from the memory
    calc_word_rd_addr    <= calc_word_rd_addr_i;
    
    icap_busy_d           <= icap_busy;   -- 2026: for the bounded-pass op-done exit
    -- delaying the fecc_far to be syncronized with the icap output
    delay_far             <= fecc_far;
    delay_far_group       <= fecc_far(frame_addr_width-1 downto log2(max_frames_per_group));
    delay_subgroup        <= conv_std_logic_vector(conv_integer(fecc_far) mod subgroups_per_group,next_subgroup'length);
    -- delaying once more to be syncronized with the icap output
    next_far              <= delay_far;
    next_far_group        <= delay_far_group;
    -- calculating the next subgroup so it can be pre-loaded from the memory
    next_subgroup         <= delay_subgroup;
    
    -- fecc_far shows the next far, delaying it so we can have the address of
    -- the current frame
    current_far           <= next_far;
    current_far_group     <= next_far_group;
    current_subgroup      <= next_subgroup;
    if icap_current_word_index = words_per_frame-1 then
        locked_far<=next_far;
        locked_far_group<=next_far_group;
        locked_subgroup<=next_subgroup;
    end if;
    
    
    -- requesting from the icape the whole device if the memory hasnt been initialized
    -- or a group given externaly by the syndrome handler                          
    if initialized = '0' then
     icap_frame_addr    <= start_frame_addr;

    else
     icap_frame_addr    <= group_frame_addr;
     --icap_num_of_frames <= conv_std_logic_vector(max_frames_per_group,icap_num_of_frames'length);-- change(1)
    end if;
    -- counter for the calc_word_wr_addr, it was to start 1 cycle before needed
    if start_calc='1' then
        if calc_word_rd_addr_i = words_per_frame - 1 then
          calc_word_rd_addr_i        <= (others => '0');
        else
          calc_word_rd_addr_i        <= calc_word_rd_addr_i + 1;
        end if;
    else
        calc_word_rd_addr_i        <= (others => '0');
    end if;
    
    if calc_word_rd_addr_i = 0 then
        calc_subgroup_rd_addr <= current_subgroup;
    end if;
    -- 2026 hardening: latch a golden parity error while comparing (only
    -- meaningful when golden holds committed data, i.e. initialized='1').
    if pmem_word_rd_valid = '1' and pmem_word_rd_perr = '1' and initialized = '1' then
      pass_poisoned <= '1';
    end if;
    case current_state is
      when idle =>
        icap_request_i  <= '0';
        next_far_group_change <= '0';   -- 2026: consume/clear the sticky flag
        if pass_poisoned = '1' then
          -- 2026 hardening: the finished pass consumed a golden word that
          -- failed its parity check - the golden store is corrupt and the
          -- pass result was discarded by the handler. Drop `initialized`
          -- HERE (not at done: the poisoned pass's own stop_read_mem would
          -- otherwise see initialized='0' and re-set it, believing it had
          -- just completed an init pass). The next idle cycle launches the
          -- full golden re-init sweep.
          initialized_a <= '0';
          initialized_b <= '0';
          initialized_c <= '0';
          pass_poisoned <= '0';
          poison_events <= poison_events + 1;
          -- synthesis translate_off
          report "PCDBG POISONED pass consumed -> dropping initialized (re-init)";
          -- synthesis translate_on
        elsif initialized = '0' or start_parity_calc ='1' then
          icap_request_i  <= '1';
        end if;
      when read_mem =>
        calc_word_read  <= '1';
        next_far_group_change <= '0';   -- 2026: no stale flag at pass start
        icap_start      <= '1';
        -- for pipeline reasons start reading from the memory before the icap
        -- needs the data. the Golden Parity Memory takes 5 cycles to output valid data
        -- after it recived the pmem_word_read command 
        if icap_current_word_index = words_per_frame-6
           and icap_busy = '1'
           and icap_data_out_valid = '0' then
          pmem_word_read          <= '1';
          pmem_new_frame_read     <= '1';
          pmem_group_rd_addr      <= next_far_group & (log2(max_frames_per_group)-1 downto 0 => '0');
          pmem_subgroup_rd_addr   <= next_subgroup;
        end if;
        if icap_current_word_index = words_per_frame-3 and initialized = '1' then
          start_calc<='1';
        end if;
      when parity_calc =>
        
        -- handling memory addresses
        calc_word_wr_addr     <= icap_current_word_index;
        if icap_current_word_index = 0 then
            calc_subgroup_wr_addr <= locked_subgroup;
        end if;
        pmem_group_wr_addr    <= locked_far_group & (log2(max_frames_per_group)-1 downto 0 => '0');
        pmem_subgroup_wr_addr <= locked_subgroup;
        -- enebling the correct memory for the data to be read from and write to
        -- if unitialized then the Golden Parity Memory will be initialized
        -- otherwise the Calculated Parity Memory will be calculated
        if initialized = '0' then
          pmem_word_write <= icap_data_out_valid;
        else
          calc_word_write <= icap_data_out_valid;
        end if;
        
        pmem_new_frame_write  <= '0';
        if icap_current_word_index = 0 then
          pmem_new_frame_write  <= '1';
        end if;
        --initial_frame_of_group;
        -- first frame of each SUBGROUP within the group initializes its parity
        -- accumulator (2026: was hard-coded '<2', breaking any S /= 2)
        if  locked_far(log2(max_frames_per_group)-1 downto 0) < subgroups_per_group then
          if initialized = '0' then
            -- doing the parity calculation to calculate the golden parity memory
            pmem_word_wr_data <= icap_data_out;
          else
            -- doing the parity calculation to calculate the temp parity group frame
            calc_word_wr_data <= icap_data_out xor pmem_word_rd_data;
         end if;
        else
          if initialized = '0' then
            -- doing the parity calculation to calculate the golden parity memory
            pmem_word_wr_data <= icap_data_out xor pmem_word_rd_data;
          else
            -- doing the parity calculation to calculate the temp parity group frame
            calc_word_wr_data <= icap_data_out xor calc_word_rd_data;
         end if;
        end if;
        -- for pipeline reasons starting to read the next frame from the
        -- Golden Parity Memory to have it ready for the icap at the correct time
        
        pmem_new_frame_read <= '0';
        
        if icap_current_word_index = words_per_frame-6 then
          pmem_new_frame_read   <= '1';
          pmem_group_rd_addr    <= next_far_group & (log2(max_frames_per_group)-1 downto 0 => '0');
          pmem_subgroup_rd_addr <= next_subgroup;
        end if;
        
        
        -- finishing the calculation when the last word of the group is reached
        -- if calculating one group or when the last word of the end frame
        -- if calculating the memory -- this allows for the change(1) to work
        if initialized = '1'
           and icap_current_word_index = words_per_frame-1
           and next_far_group_change = '1' then
          parity_calc_done        <= '1';
          start_calc              <= '0';
          pmem_word_read          <= '0';
        elsif icap_current_word_index = words_per_frame-1
              and next_far = end_frame_addr then
          parity_calc_done        <= '1';
          pmem_word_read          <= '0';
        elsif initialized = '1' and pass_frames /= conv_std_logic_vector(0,20)
              and icap_busy = '0' and icap_busy_d = '1' then
          parity_calc_done        <= '1';
          start_calc              <= '0';
          pmem_word_read          <= '0';
        end if;
      when stop_read_mem =>
        --safely desyncronising the icape and then freeing the Arbiter
        calc_word_read   <= '0';
        icap_start       <= '0';
        icap_request_i   <= '0';
        icap_desync      <= '1';
        icap_stop        <= '1';
        if icap_synced = '0' then
          if initialized = '1' then
            parity_calc_done <= '1';
          else
            initialized_a    <= '1';
            initialized_b    <= '1';
            initialized_c    <= '1';
          end if;
        end if;
      when others=> null;
    end case;

    -- synthesis translate_off
    if sim_flip_tmr = '1' and flip_d = '0' then
      initialized_a <= not initialized_a;   -- TMR fault injection (sim only)
      report "PCDBG TMR flip: initialized_a inverted";
    end if;
    flip_d := sim_flip_tmr;
    -- synthesis translate_on
   end if;
  end if;
 end process;
end rtl;
