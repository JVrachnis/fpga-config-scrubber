-- SPDX-License-Identifier: MIT
-- Copyright (c) 2020-2026 John Vrachnis
----------------------------------------------------------------------------------
-- Company:
-- Engineer:
--
-- Create Date: 09/20/2020 05:40:52 PM
-- Design Name:
-- Module Name: syndrome_handler - Behavioral
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
use IEEE.STD_LOGIC_1164.ALL;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_arith.conv_std_logic_vector;
use work.log2_pkg.all;
use work.device_geometry_pkg.all;

entity syndrome_handler is
  Generic (
  tmr_en:	boolean:=	true;  -- 2026-09-03 hardness A/B: false = copy a only
  scanned_groups_without_error: integer:=	128;
  syndromes_mem_entries:	integer:=	128;
  words_per_frame:	integer:=	101;
  bits_per_word:	integer:=	32;
  max_frames_per_group:	integer:=	64;
  subgroups_per_group:	integer:=	2;
  frame_addr_width:	integer:=	26
  );
  Port (
  --Control Interface
  clk:in std_logic;
  reset:in std_logic;
  -- 2026: frame the current SYNDROMEVALID pulse belongs to (registered
  -- attributed_frame computed centrally in scrubber_ip)
  cur_frame_in:in std_logic_vector(frame_addr_width-1 downto 0);
  start_frame_addr:in std_logic_vector(frame_addr_width-1 downto 0);
  end_frame_addr:in std_logic_vector(frame_addr_width-1 downto 0);
  crc_only:out std_logic;
  --FRAME ECC primitive Interface
  fecc_syndromevalid:in std_logic;
  fecc_eccerror:in std_logic;
  fecc_syndrome:in std_logic_vector(log2(words_per_frame)+log2(bits_per_word) downto 0);
  fecc_crcerror:in std_logic;
  fecc_far:in std_logic_vector(frame_addr_width-1 downto 0);
  fecc_synword:in std_logic_vector(log2(words_per_frame)-1 downto 0);
  fecc_synbit:in std_logic_vector(log2(bits_per_word)-1 downto 0);
  fecc_eccerrorsingle:in std_logic;
  --Parity Calculator Interface
  
  group_frame_address:out std_logic_vector(frame_addr_width-1 downto 0);
  start_parity_calc:out std_logic;
  parity_calc_done:in std_logic;
  -- 2026 fix: the parity calculator's ICAP-arbiter request line. The handler's
  -- parity_calc state previously accepted ANY parity_calc_done pulse - the
  -- calculator pulses done both at pass exit AND at desync, so the handler
  -- routinely consumed the trailing pulse of the SCAN pass that detected the
  -- error and started correction with stale (zero) calc parity: the frame was
  -- rewritten verbatim, forever (ILA 2026-09-01, locked_far proof). Same
  -- accept-then-wait handshake the scan driver got in the bounded-pass rework.
  pcalc_req:in std_logic := '0';
  -- 2026 hardening: pass result untrustworthy (golden parity error); do not
  -- start error correction from it.
  parity_poisoned:in std_logic := '0';
  -- simulation-only TMR fault hook: rising edge flips bits in copy A of both
  -- syndrome-memory indices
  sim_flip_tmr:in std_logic := '0';
  parity_initialized: in std_logic;
  --2D EDC Algorithm Interface:
  start_error_correction:out std_logic;
  err_group_address:out std_logic_vector(frame_addr_width-1 downto 0);
  err_frame_count:out std_logic_vector(log2(max_frames_per_group)-1 downto 0);
  single_frame_in_subgr:out std_logic_vector(subgroups_per_group-1 downto 0);
  read_syndromes_mem:in std_logic;
  syndromes_mem_offset:in std_logic_vector(log2(max_frames_per_group)-1 downto 0);
  err_frame_address:out std_logic_vector(log2(max_frames_per_group)-1 downto 0);
  err_frame_synword:out std_logic_vector(6 downto 0);
  err_frame_synbit:out std_logic_vector(4 downto 0);
  odd_errors_in_frame:out std_logic;
  error_correction_done:in std_logic;
  --Scan Driver Interface:
  busy:out std_logic
  );
end syndrome_handler;

architecture Behavioral of syndrome_handler is
  component fwft_fifo
  generic
    (
    async_reset        : boolean := true;
    sync_reset         : boolean := true;
    width              : integer := 32;
    depth              : integer := 256;
    progfull_threshold : integer := 128;
    progfull_threshold2: integer := 128;
    progempty_threshold: integer := 128
    );
  port
    (
    clk                : in  std_logic;
    areset_n           : in  std_logic;
    sreset             : in  std_logic;
    write_mem          : in  std_logic;
    read_mem           : in  std_logic;
    data_in            : in  std_logic_vector(width - 1 downto 0);
    data_out           : out std_logic_vector(width - 1 downto 0);
    data_count         : out std_logic_vector(log2(depth) downto 0);
    empty              : out std_logic;
    full               : out std_logic;
    progempty          : out std_logic;
    progfull           : out std_logic;
    progfull2          : out std_logic
    );
  end component;
  type   state_t             is (idle, store_error ,parity_calc, error_correction);

  --fwft_fifo
  signal fifo_write_mem          :  std_logic:='0';
  signal fifo_read_mem           :  std_logic:='0';
  signal fifo_data_in            :  std_logic_vector(bits_per_word - 1 downto 0):= (others => '0');
  signal fifo_data_out           :  std_logic_vector(bits_per_word - 1 downto 0):= (others => '0');
  signal fifo_data_count         :  std_logic_vector(log2(syndromes_mem_entries-max_frames_per_group +1) downto 0):= (others => '0');
  signal fifo_empty              :  std_logic:='0';
  signal fifo_full               :  std_logic:='0';
  signal fifo_progempty          :  std_logic:='0';
  signal fifo_progfull           :  std_logic:='0';
  signal fifo_progfull2          :  std_logic:='0';
  -- mem
  signal mem_rd_addr           : std_logic_vector(log2(syndromes_mem_entries)-1 downto 0) := (others => '0');
  signal mem_wr_addr           : std_logic_vector(log2(syndromes_mem_entries)-1 downto 0) := (others => '0');
  signal mem_wr_data           : std_logic_vector(bits_per_word-1 downto 0) := (others => '0');
  signal mem_rd_data           : std_logic_vector(bits_per_word-1 downto 0) := (others => '0');
  signal mem_write             : std_logic := '0';
  signal mem_read              : std_logic := '0';
  -- state ,machine signals
  signal current_state,next_state: state_t:=idle;
  signal fifo_sreset : std_logic := '0';
  signal pass_accepted : std_logic := '0';
  signal pcalc_req_d   : std_logic := '0';
  signal busy_r : std_logic := '0';
-- 2026 hardening: recover from SEU-induced illegal FSM states (Vivado synthesis attr).
attribute fsm_safe_state : string;
attribute fsm_safe_state of current_state : signal is "reset_state";
  Signal error_timeout_counter: std_logic_vector(log2(scanned_groups_without_error)-1 downto 0):=(others=>'0');
  Signal error_timeout: std_logic:='0';
  signal end_of_group:std_logic:='0';
  signal synword_unprossesed :integer:=0;
  -- group data
  signal no_space_for_new_group           : std_logic:='0';
  -- 2026 hardening: both syndrome-memory indices are TMR'd with feedback
  -- voters. They are the longest-lived bookkeeping state in the handler; a
  -- flipped index attributes stored syndromes to the wrong entries and can
  -- turn a correction into a write of the wrong frame. Three DONT_TOUCH
  -- copies each; reads use the majority vote; every copy re-samples the vote
  -- each cycle (specific assignments override), healing a flip in 1 cycle.
  signal syndrome_mem_last_entry_index    : std_logic_vector(log2(syndromes_mem_entries)-1 downto 0);
  signal sm_last_a, sm_last_b, sm_last_c  : std_logic_vector(log2(syndromes_mem_entries)-1 downto 0) := (others => '0');
  signal syndrome_group_first_entry_index : std_logic_vector(log2(syndromes_mem_entries)-1 downto 0);
  signal sg_first_a, sg_first_b, sg_first_c : std_logic_vector(log2(syndromes_mem_entries)-1 downto 0) := (others => '0');
  attribute DONT_TOUCH : string;
  attribute DONT_TOUCH of sm_last_a  : signal is "true";
  attribute DONT_TOUCH of sm_last_b  : signal is "true";
  attribute DONT_TOUCH of sm_last_c  : signal is "true";
  attribute DONT_TOUCH of sg_first_a : signal is "true";
  attribute DONT_TOUCH of sg_first_b : signal is "true";
  attribute DONT_TOUCH of sg_first_c : signal is "true";
  signal syndromes_in_group               : std_logic_vector(log2(max_frames_per_group)-1 downto 0) := (others => '0');
  signal error_in_group: std_logic:='0';
  signal single_frame_subgroup_flag:std_logic_vector(subgroups_per_group-1 downto 0):=(others=>'0');
  signal multiple_frame_subgroup_flag:std_logic_vector(subgroups_per_group-1 downto 0):=(others=>'0');
  signal subgroup:integer:=0;
  -- 2026: settle counter for the empty-fifo bailout in parity_calc
  signal pc_settle  : std_logic_vector(2 downto 0) := (others=>'0');
  -- 2026: group of the stored entries, latched at STORE time. The flush used
  -- delayed_far, which for a pass-end (column-last) error had already shifted
  -- into the NEXT column on silicon - the correction pass then scanned the
  -- wrong column and the EDC corrected a clean frame one column over
  -- (ILA-measured: entry frame 0x23 paired with group 0xA80 instead of 0xA00).
  signal entry_group : std_logic_vector(frame_addr_width-1 downto log2(max_frames_per_group)) := (others=>'0');
  -- fecc --
  signal fecc_syndromevalid_d: std_logic;
  signal delayed_far: std_logic_vector(frame_addr_width-1 downto 0):=(others=>'0');
  signal delayed_far2: std_logic_vector(frame_addr_width-1 downto 0):=(others=>'0');
  signal delayed_far3: std_logic_vector(frame_addr_width-1 downto 0):=(others=>'0');
  attribute mark_debug : string;
  attribute mark_debug of pass_accepted,pcalc_req_d,start_parity_calc,start_error_correction,mem_write,mem_wr_data,err_frame_address,delayed_far,fifo_write_mem,err_group_address,odd_errors_in_frame,single_frame_in_subgr,err_frame_count,fifo_read_mem,error_correction_done,fifo_data_in,subgroup,single_frame_subgroup_flag,multiple_frame_subgroup_flag,mem_read: signal is "true";

begin
  -- busy indicator for the scan driver: high whenever the handler is
  -- storing/correcting an error (i.e. not idle)
  busy <= busy_r;
  fifo_sreset <= reset or (not parity_initialized);
  -- TMR majority voters (bitwise)
  syndrome_mem_last_entry_index    <= (sm_last_a and sm_last_b) or (sm_last_a and sm_last_c) or (sm_last_b and sm_last_c) when tmr_en else sm_last_a;
  syndrome_group_first_entry_index <= (sg_first_a and sg_first_b) or (sg_first_a and sg_first_c) or (sg_first_b and sg_first_c) when tmr_en else sg_first_a;  -- registered replica of (state /= idle): timing (state->busy fed the pcalc/arb/controller cone)
  -- getting the subgroup from the frame
  
  -- getting the word possision from the syndrome
  err_frame_synword     <= mem_rd_data(11 downto 5) - 25 when  mem_rd_data(11 downto 5) <  32
                      else mem_rd_data(11 downto 5) - 26 when  mem_rd_data(11 downto 5) <  64
                      else mem_rd_data(11 downto 5) - 27 when  mem_rd_data(11 downto 5) <= 127
                      else conv_std_logic_vector(102,err_frame_synword'length);
  -- spliting the group data from the fifo
  err_group_address     <= fifo_data_out(frame_addr_width-1 downto log2(max_frames_per_group)) & (log2(max_frames_per_group)-1 downto 0 => '0');  -- 2026: width-generic pad (was a literal "000000")

  err_frame_count       <= fifo_data_out(log2(max_frames_per_group)-1 downto 0);
  single_frame_in_subgr <= fifo_data_out(bits_per_word-1 downto bits_per_word - subgroups_per_group);
  group_frame_address   <= fifo_data_out(frame_addr_width-1 downto log2(max_frames_per_group)) & (log2(max_frames_per_group)-1 downto 0 => '0');  -- 2026: width-generic pad (was a literal "000000")
  -- spliting the frame data from the memory
  err_frame_address     <= mem_rd_data(bits_per_word -1 downto bits_per_word-log2(max_frames_per_group));
  
  synword_unprossesed   <= conv_integer(mem_rd_data(11 downto 5));
  err_frame_synbit      <= mem_rd_data(4 downto 0);
  odd_errors_in_frame   <= mem_rd_data(12) when conv_integer(mem_rd_data(11 downto 0))/= 0 else '0';
  mem_read              <= read_syndromes_mem;
  mem_rd_addr           <= syndromes_mem_offset+syndrome_group_first_entry_index;
  state_transition:process(clk)
  begin
    if rising_edge(clk) then
      if reset='1' then
       current_state <= idle;
      else
       current_state <= next_state;
       if next_state = idle then  -- bit-exact registered busy
         busy_r <= '0';
       else
         busy_r <= '1';
       end if;
      end if;
    end if;
  end process;

  state_machine:process(current_state,parity_initialized,parity_poisoned,pass_accepted,fecc_syndromevalid,fecc_eccerror,fecc_far,end_frame_addr,error_timeout_counter,syndrome_mem_last_entry_index,fifo_empty,fifo_progempty,parity_calc_done,error_correction_done,single_frame_subgroup_flag,multiple_frame_subgroup_flag,subgroup,pc_settle)
  begin
    next_state <= current_state;
    if parity_initialized = '0' then
      -- 2026 hardening: golden store is being (re)built - all in-flight
      -- syndrome bookkeeping is meaningless. Park in idle; the clocked side
      -- clears indices and drains the fifo while this is low.
      next_state <= idle;
    else
    case current_state is
      when idle=>
        -- idling until erroniues syndrome is detected
        if fecc_syndromevalid_d = '1' and fecc_eccerror = '1' and parity_initialized='1' then
          next_state<=store_error;
        end if;
      when store_error=>
        -- storing the error and waiting for others untile timeout is reached or
        -- the end of device is reached or not enouph space left in memory for
        -- another group and the next frame is another group
        if fecc_syndromevalid = '0' and fecc_syndromevalid_d='1'
           and
           ( fecc_far = end_frame_addr or (error_timeout_counter = 0
            and conv_integer(fecc_far(log2(max_frames_per_group)-1 downto 0)) = 0 )--next frame is another group -- small change so we can use error error_timeout_counter from 0 to immediately after the 1st group

              or

           ( syndrome_mem_last_entry_index > (syndromes_mem_entries-max_frames_per_group)
           and conv_integer(fecc_far(log2(max_frames_per_group)-1 downto 0)) = 0 ))--next frame is another group
        then
          next_state <= parity_calc;
        -- 2026: bounded passes end exactly at the column boundary, so an error
        -- in the pass's last frame sees no further pulse to trigger the
        -- boundary conditions above - exit (and flush, clocked side) when the
        -- pass itself completes.
        elsif parity_calc_done = '1' then
          next_state <= parity_calc;
        end if;
      when parity_calc=>
        -- 2026 fix (accept-then-wait): only a done pulse that follows OUR
        -- accepted pass may advance to correction - straggler done pulses
        -- from the scan pass that detected the error are ignored.
        if parity_calc_done='1' and pass_accepted='1' then
          if parity_poisoned = '1' then
            -- 2026 hardening: discard the pass; re-init + re-detection will
            -- handle the frame error against fresh golden parity.
            next_state <= idle;
          else
            next_state <= error_correction;
          end if;
        -- 2026 fix: if no group was ever flushed (e.g. all events masked or a
        -- boundary race), the fifo is empty, start_parity_calc is never
        -- asserted, and this state deadlocked. Bail to idle once the fifo
        -- state has settled.
        elsif pass_accepted='0' and fifo_empty='1' and pc_settle = "111" then
          next_state <= idle;
        end if;
      when error_correction=>
        -- initiate error correction, when error correction is done, if the fifo
        -- is empty it will go idle and wait for erroniues syndrome otherwise
        -- it will move to the parity calculation to calculate the next group
        if error_correction_done='1' then
          if fifo_progempty='1' then
            next_state <= idle;
          else
            next_state <= parity_calc;
          end if;
        end if;
      when others =>
        next_state <= idle;
    end case;
    end if;
  end process;
  main:process(clk)
    -- 2026 fix: subgroup of the frame the current SYNDROMEVALID pulse belongs to.
    -- The registered `subgroup` signal lags by one pulse; pairing it with the
    -- delayed_far2-addressed entries mixed subgroup bookkeeping across frames.
    variable v_subgroup : integer := 0;
    -- synthesis translate_off
    variable v_flip_d : std_logic := '0';
    -- synthesis translate_on
    variable v_cur_frame : std_logic_vector(frame_addr_width-1 downto 0) := (others=>'0');
  begin
    if rising_edge(clk) then
      -- address of the frame the current pulse belongs to (registered
      -- shared attribution from scrubber_ip)
      v_cur_frame := cur_frame_in;
      v_subgroup  := conv_integer(v_cur_frame(log2(max_frames_per_group)-1 downto 0)) mod subgroups_per_group;
      if reset='1' then
        start_parity_calc                <= '0';
        error_in_group                   <= '0';
        error_timeout_counter            <= (others=>'0');
        delayed_far                      <= (others=>'0');
        -- den eimai sigouros an xriazonte edo giati ginonte reset kai otan to
        -- currnet state einai idle
        sg_first_a <= (others =>'0');
        sg_first_b <= (others =>'0');
        sg_first_c <= (others =>'0');
        sm_last_a    <= (others =>'0');
        sm_last_b    <= (others =>'0');
        sm_last_c    <= (others =>'0');
        single_frame_subgroup_flag       <= (others =>'0');
        multiple_frame_subgroup_flag     <= (others =>'0');
        fecc_syndromevalid_d             <= '0';
      else
        start_parity_calc                <= '0';
        -- TMR feedback: copies re-sample the vote each cycle; specific
        -- assignments below override (last assignment wins in a process).
        sm_last_a  <= syndrome_mem_last_entry_index;
        sm_last_b  <= syndrome_mem_last_entry_index;
        sm_last_c  <= syndrome_mem_last_entry_index;
        sg_first_a <= syndrome_group_first_entry_index;
        sg_first_b <= syndrome_group_first_entry_index;
        sg_first_c <= syndrome_group_first_entry_index;
        if parity_initialized = '0' then
          -- 2026 hardening: golden re-init in progress - flush bookkeeping.
          -- (fifo is drained via fifo_sreset below.)
          sg_first_a <= (others =>'0');
          sg_first_b <= (others =>'0');
          sg_first_c <= (others =>'0');
          sm_last_a    <= (others =>'0');
          sm_last_b    <= (others =>'0');
          sm_last_c    <= (others =>'0');
          single_frame_subgroup_flag       <= (others =>'0');
          multiple_frame_subgroup_flag     <= (others =>'0');
          error_in_group                   <= '0';
          error_timeout_counter            <= (others =>'0');
        end if;
        if current_state /= parity_calc then
          pc_settle     <= (others=>'0');
          pass_accepted <= '0';
        end if;
        pcalc_req_d <= pcalc_req;
        fifo_write_mem         <='0';
        fifo_read_mem          <='0';
        mem_write              <='0';
        start_error_correction <='0';
        -- fecc_far shows the next far, delaying it so we can have the address of
        -- the current frame
        if fecc_syndromevalid='1' then
            subgroup    <= conv_integer(delayed_far2(log2(max_frames_per_group)-1 downto 0)) mod subgroups_per_group;
        end if;
        if fecc_syndromevalid_d='1' then
          delayed_far2<= fecc_far;
          delayed_far <= delayed_far2;
        end if;
        fecc_syndromevalid_d<=fecc_syndromevalid;
        

        
        case current_state is
          when idle=>
            -- save the first syndrome and ititialize the error storing
            if fecc_syndromevalid = '1' and fecc_eccerror = '1' then
              sg_first_a <= (others =>'0');
              sg_first_b <= (others =>'0');
              sg_first_c <= (others =>'0');
              -- 2026 fix: this first entry is written at address 0 below, so the
              -- next free slot is 1. The original reset to 0 (while the write
              -- address used the stale pre-reset index) desynchronized entry
              -- storage from the state machine's reads as soon as any earlier
              -- cycle had stored more than one entry - corrections then used
              -- stale entries and rewrote the wrong (clean) frame (ILA-proven
              -- on silicon, 2026-08-28).
              sm_last_a    <= conv_std_logic_vector(1, syndrome_mem_last_entry_index'length);
              sm_last_b    <= conv_std_logic_vector(1, syndrome_mem_last_entry_index'length);
              sm_last_c    <= conv_std_logic_vector(1, syndrome_mem_last_entry_index'length);
              single_frame_subgroup_flag       <= (others =>'0');
              multiple_frame_subgroup_flag     <= (others =>'0');
              error_timeout_counter            <= conv_std_logic_vector(scanned_groups_without_error, error_timeout_counter'length);
              syndromes_in_group <=  (0=>'1',others =>'0');
              -- this means that the subgroup has only one error so far
              single_frame_subgroup_flag(v_subgroup)<='1';
              mem_write          <= '1';
              -- compining the frame data to be writen to the memory
              -- 2026 fix: delayed_far lags the erroneous frame by one (FRAME_ECCE2
              -- shows next-far at the pulse; the two-stage delay lands on N-1).
              -- delayed_far2 is the frame the syndrome belongs to (ILA-verified).
              mem_wr_data(bits_per_word -1 downto bits_per_word -log2(max_frames_per_group))
                                  <= v_cur_frame(log2(max_frames_per_group)-1 downto 0);
              entry_group         <= v_cur_frame(frame_addr_width-1 downto log2(max_frames_per_group));
                
              mem_wr_data(log2(words_per_frame)+log2(bits_per_word) downto 0)
                                  <= fecc_syndrome;
                
              mem_wr_addr           <= (others => '0');
            end if;
          when store_error=>
            -- handling the timeout timer
            -- checking if the group has an error otherwise it will count down
            -- at 0 the storing error will stop
            -- it resets every time there is an erroniues group
            -- so the device doesnt wait a long time before starting to correct

            if conv_integer(v_cur_frame(log2(max_frames_per_group)-1 downto 0)) = 0
               and fecc_syndromevalid = '1'
            then
              error_in_group <= fecc_eccerror;
              if
                ( error_in_group = '1' or fecc_eccerror = '1' or syndromes_in_group > 0)
              then
                error_timeout_counter <= conv_std_logic_vector(scanned_groups_without_error, error_timeout_counter'length);
              elsif error_timeout_counter /= 0 then
                error_timeout_counter <= error_timeout_counter-1;
              end if;
            elsif fecc_syndromevalid = '1' then
              error_in_group <= error_in_group or fecc_eccerror;
            end if;

            -- storing the previus processed group data to the fifo when
            -- the group changes or memory full or the next frame is the end of the device
            -- (2026: or when the bounded pass completes - see the transition note)
            if parity_calc_done = '1' and syndromes_in_group > 0 then
                fifo_write_mem <= '1';
                fifo_data_in(bits_per_word-1 downto bits_per_word - subgroups_per_group)
                               <= single_frame_subgroup_flag;
                fifo_data_in(log2(max_frames_per_group)-1 downto 0)
                               <= syndromes_in_group;
                fifo_data_in(frame_addr_width-1 downto log2(max_frames_per_group))
                               <= entry_group;   -- 2026: group latched at store time
            elsif (fecc_far = end_frame_addr
                or syndrome_mem_last_entry_index = (syndromes_mem_entries-1)
                or conv_integer(fecc_far(log2(max_frames_per_group) -1 downto 0)) = 0)
               and fecc_syndromevalid_d = '1'
               and  syndromes_in_group > 0
            then
                fifo_write_mem <= '1';
                fifo_data_in(bits_per_word-1 downto bits_per_word - subgroups_per_group)
                               <= single_frame_subgroup_flag;
                fifo_data_in(log2(max_frames_per_group)-1 downto 0)
                               <= syndromes_in_group;
                fifo_data_in(frame_addr_width-1 downto log2(max_frames_per_group))
                               <= entry_group;   -- 2026: group latched at store time
            -- initializing the data group data
            elsif conv_integer(v_cur_frame(log2(max_frames_per_group) -1 downto 0)) = 0-- this is so it doesnt get trigerd at the 00000000 frame address
                and fecc_syndromevalid = '1' and fecc_eccerror='1'
            then
              -- initializing the group data for erroniues group
              error_timeout_counter        <= conv_std_logic_vector(scanned_groups_without_error, error_timeout_counter'length);
              syndromes_in_group           <=  (0=>'1',others =>'0');
              single_frame_subgroup_flag   <= (others =>'0');
              single_frame_subgroup_flag(v_subgroup)
                                             <= '1';
              multiple_frame_subgroup_flag <= (others =>'0');
              -- 2026 fix: the first syndrome of the new group was counted but
              -- never written to the syndromes memory - store it like any other.
              mem_write   <= '1';
              mem_wr_data(bits_per_word -1 downto bits_per_word -log2(max_frames_per_group))
                          <= v_cur_frame(log2(max_frames_per_group)-1 downto 0);
              entry_group         <= v_cur_frame(frame_addr_width-1 downto log2(max_frames_per_group));
              mem_wr_data(log2(words_per_frame)+log2(bits_per_word) downto 0)
                          <= fecc_syndrome;
              mem_wr_addr <= syndrome_mem_last_entry_index;
              sm_last_a <= syndrome_mem_last_entry_index + 1;
              sm_last_b <= syndrome_mem_last_entry_index + 1;
              sm_last_c <= syndrome_mem_last_entry_index + 1;
            elsif conv_integer(v_cur_frame(log2(max_frames_per_group) -1 downto 0)) = 0-- this is so it doesnt get trigerd at the 00000000 frame address
                and fecc_syndromevalid = '1' and fecc_eccerror='0'
            then
              -- initializing the group data for "non erroniues" group
              if error_timeout_counter /= 0 then
                error_timeout_counter        <= error_timeout_counter-1;
              end if;
              syndromes_in_group           <= (others =>'0');
              single_frame_subgroup_flag   <= (others =>'0');
              multiple_frame_subgroup_flag <= (others =>'0');

            elsif fecc_syndromevalid = '1'
               and fecc_eccerror = '1'
               and syndrome_mem_last_entry_index < (syndromes_mem_entries-1)
            then
              --reset the timeout counter
              error_timeout_counter         <= conv_std_logic_vector(scanned_groups_without_error, error_timeout_counter'length);
              -- writing to the memory the erroniues syndrome data
              mem_write   <= '1';
              -- compining the frame data to be writen to the memory (2026: delayed_far2, see idle)
              mem_wr_data(bits_per_word -1 downto bits_per_word -log2(max_frames_per_group))
                                  <= v_cur_frame(log2(max_frames_per_group)-1 downto 0);
              entry_group         <= v_cur_frame(frame_addr_width-1 downto log2(max_frames_per_group));
                
              mem_wr_data(log2(words_per_frame)+log2(bits_per_word) downto 0)
                                  <= fecc_syndrome;
                
              mem_wr_addr           <= syndrome_mem_last_entry_index;
              -- calculating the indexing
              sm_last_a <= syndrome_mem_last_entry_index + 1;
              sm_last_b <= syndrome_mem_last_entry_index + 1;
              sm_last_c <= syndrome_mem_last_entry_index + 1;
              syndromes_in_group            <= syndromes_in_group +1;

              -- calculating if there is a single frame erroniues group or not
              if single_frame_subgroup_flag(v_subgroup) = '0'
                 and multiple_frame_subgroup_flag(v_subgroup) = '0'
              then
                single_frame_subgroup_flag(v_subgroup)   <= '1';
              elsif single_frame_subgroup_flag(v_subgroup) = '1'
                    and multiple_frame_subgroup_flag(v_subgroup) = '0'
              then
                single_frame_subgroup_flag(v_subgroup)   <= '0';
                multiple_frame_subgroup_flag(v_subgroup) <= '1';
              end if;
            end if;


          when parity_calc=>
          -- starting the parity calculations
            if pc_settle /= "111" then
              pc_settle <= pc_settle + 1;
            end if;
            -- 2026 fix (accept-then-wait): hold start as a LEVEL until the
            -- calculator's arbiter request rises (our pass accepted), then
            -- release and wait for its done. See the pcalc_req port note.
            if pass_accepted = '0' and fifo_empty = '0' then
              start_parity_calc <= '1';
              -- rising edge required: at episode entry the calculator's
              -- request may still be high for a cycle or two from the pass
              -- that detected the error - a level check would false-accept.
              if pcalc_req = '1' and pcalc_req_d = '0' then
                pass_accepted     <= '1';
                start_parity_calc <= '0';
              end if;
            end if;
          when error_correction=>
            -- starting the error correction, when done.. it reads the next group
            -- data from the fifo to prepare it for calculation
            if error_correction_done = '1' then
              sg_first_a <= syndrome_group_first_entry_index
                  +conv_integer(fifo_data_out(log2(max_frames_per_group)-1 downto 0));
              sg_first_b <= syndrome_group_first_entry_index
                  +conv_integer(fifo_data_out(log2(max_frames_per_group)-1 downto 0));
              sg_first_c <= syndrome_group_first_entry_index
                  +conv_integer(fifo_data_out(log2(max_frames_per_group)-1 downto 0));

              fifo_read_mem                    <= '1';
            else
              start_error_correction           <= '1';
            end if;
          when others =>
          null;
        end case;
        -- synthesis translate_off
        if sim_flip_tmr = '1' and v_flip_d = '0' then
          sm_last_a  <= sm_last_a  xor conv_std_logic_vector(3, sm_last_a'length);
          sg_first_a <= sg_first_a xor conv_std_logic_vector(5, sg_first_a'length);
          report "SHDBG TMR flip: sm_last_a/sg_first_a corrupted";
        end if;
        v_flip_d := sim_flip_tmr;
        -- synthesis translate_on
      end if;
    end if;
  end process;
  -- synthesis translate_off
  sh_dbg: process(clk)
    variable sec_d : std_logic := '0';
  begin
    if rising_edge(clk) then
      if mem_write='1' then
        report "SHDBG entry addr=" & integer'image(conv_integer(mem_wr_addr))
             & " frame=" & integer'image(conv_integer(mem_wr_data(bits_per_word-1 downto bits_per_word-log2(max_frames_per_group))))
             & " syn=" & integer'image(conv_integer(mem_wr_data(12 downto 0)));
      end if;
      if fifo_write_mem='1' then
        report "SHDBG flush group_hi=" & integer'image(conv_integer(fifo_data_in(frame_addr_width-1 downto log2(max_frames_per_group))))
             & " count=" & integer'image(conv_integer(fifo_data_in(log2(max_frames_per_group)-1 downto 0)))
             & " sflags=" & integer'image(conv_integer(fifo_data_in(bits_per_word-1 downto bits_per_word-subgroups_per_group)));
      end if;
      if start_error_correction='1' and sec_d='0' then
        report "SHDBG start_ec (first_idx=" & integer'image(conv_integer(syndrome_group_first_entry_index)) & ")";
      end if;
      sec_d := start_error_correction;
    end if;
  end process;
  -- synthesis translate_on
  fifo:fwft_fifo
  generic
  map
    (
    async_reset        => false,
    sync_reset         => true,
    width              => 32,
    depth              => syndromes_mem_entries-max_frames_per_group+1,
    progfull_threshold => syndromes_mem_entries-max_frames_per_group+1,
    progfull_threshold2=> syndromes_mem_entries-max_frames_per_group+1,
    progempty_threshold=> 2
    )
  port
    map
    (
    areset_n           =>'0',
    clk                =>clk,
    sreset             =>fifo_sreset,  -- 2026 hardening: also drains during golden re-init
    write_mem          =>fifo_write_mem,
    read_mem           =>fifo_read_mem,
    data_in            =>fifo_data_in,
    data_out           =>fifo_data_out,
    data_count         =>fifo_data_count,
    empty              =>fifo_empty,
    full               =>fifo_full,
    progempty          =>fifo_progempty,
    progfull           =>fifo_progfull,
    progfull2          =>fifo_progfull2
    );
    mem_module : entity work.dualportmem
      generic map
        (
        addr_width     => log2(syndromes_mem_entries),
        data_width     => bits_per_word
        )
      port map
        (
        clk            => clk,
        wr_en          => mem_write,
        wr_addr        => mem_wr_addr,
        data_in        => mem_wr_data,
        rd_en          => mem_read,
        rd_addr        => mem_rd_addr,
        data_out       => mem_rd_data
        );
end Behavioral;
