---------------------------------- VHDL Code ----------------------------------
-- package      = N/A
--
-- File         = icap_controller.vhd
--
-- Purpose      = ICAP Controller
--
-- Library      = work
--
-- Dependencies = None
--
-- Author       = J. Vrachnis
--
-- Copyright    = University of Piraeus 2020
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_arith.conv_std_logic_vector;
use work.log2_pkg.all;
use work.scrubber_ip_pkg.all;


entity icap_controller is
   generic
     (
     --total_frames            : integer := 65536; -- Change(1) in the temp notes
     words_per_frame         : integer := 101;
     bits_per_word           : integer := 32;
     dummy_frames            : integer := 1;
     pipeline_words          : integer := 0;
     device_idcode           : std_logic_vector(31 downto 0) := x"13722093";
     frame_addr_width        : integer := 26;
     max_frames_per_group    : integer := 64;
     sync_retries            : integer := 256;
     config_reg_access       : boolean := false
     );
   port
     (
     clk                     : in  std_logic;
     reset                   : in  std_logic;
     -- ICAP primitive Interface
     icap_csn                : out std_logic;
     icap_rd_wrn             : out std_logic;
     icap_wrdata             : out std_logic_vector(bits_per_word-1 downto 0);
     icap_rddata             : in  std_logic_vector(bits_per_word-1 downto 0);
     icap_ready              : in  std_logic;
     icap_clk                : out std_logic;
     -- ICAP Controller Interface
     start                   : in  std_logic;
     stop_command            : in  std_logic;--change(2)
     write_command           : in  std_logic;
     register_access         : in  std_logic;
     desync                  : in  std_logic;
     frame_addr              : in  std_logic_vector(frame_addr_width-1 downto 0);
     num_of_frames           : in  std_logic_vector(19 downto 0);--Change(1)
     data_in                 : in  std_logic_vector(bits_per_word-1 downto 0);
     data_in_fetch           : out std_logic;
     data_out                : out std_logic_vector(bits_per_word-1 downto 0);
     data_out_valid          : out std_logic;
     busy                    : out std_logic;
     synced                  : out std_logic;
     current_frame_index     : out std_logic_vector(19 downto 0);--Change(1)
     current_word_index      : out std_logic_vector(log2(words_per_frame)-1 downto 0)
     -- Monitoring interface
     -- will add monitoring signals
     );
end icap_controller;


architecture behavioral of icap_controller is
type   state_t               is (UNSYNCED_S, SYNC_SEQUENCE_S, SYNCED_S, READ_FRAMES_SEQUENCE_S,
                                 WRITE_FRAMES_SEQUENCE_S, STOP_SEQUENCE_S, DESYNC_SEQUENCE_S,
                                 FAILED_SYNC_S);
signal current_state         : state_t := UNSYNCED_S;
-- 2026 hardening: recover from SEU-induced illegal FSM states (Vivado synthesis attr).
attribute fsm_safe_state : string;
attribute fsm_safe_state of current_state : signal is "reset_state";
signal next_state            : state_t := UNSYNCED_S;
-- state machine main control signals
signal operation_done        : std_logic;
signal operation_stopped     : std_logic;
signal failed_to_sync        : std_logic;--change(3)
signal desync_done           : std_logic;
signal sync_retries_counter  : std_logic_vector(log2(sync_retries)-1 downto 0);
-- sequence control signals
signal sequence_counter      : std_logic_vector(4 downto 0);
signal word_counter          : std_logic_vector(log2(words_per_frame)-1 downto 0);
signal frames_remaining      : std_logic_vector(19 downto 0);
-- outputs
signal synced_i              : std_logic;
signal data_in_fetch_i       : std_logic;
signal data_out_valid_i      : std_logic;
signal data_dummy            : std_logic;
signal word_index            : std_logic_vector(log2(words_per_frame)-1 downto 0);
signal frame_index           : std_logic_vector(19 downto 0);
signal icap_rd_wrn_i         : std_logic;
-- to be used with a constant as output in read/write frames sequence
signal words_to_access       : std_logic_vector(26 downto 0);
signal num_r                 : std_logic_vector(19 downto 0) := (others => '0');
-- status bits
signal abort_in_progress_n   : std_logic;
signal rdback_in_progress    : std_logic;
signal data_aligned          : std_logic;
signal cfgerr_n              : std_logic;


-- Bit swapping within a byte function
function bit_swap(din: std_logic_vector(bits_per_word-1 downto 0)) return std_logic_vector is
   variable dout : std_logic_vector(bits_per_word-1 downto 0);
  begin
   for i in 0 to bits_per_word/8-1 loop
     for j in 0 to 7 loop
       dout(8*i+j) := din(8*i+7-j);
     end loop;
   end loop;
   return dout;
  end bit_swap;


  attribute mark_debug                                                                                                                                                                                                                 : string;
  attribute mark_debug of num_r,num_of_frames,frame_addr,icap_rddata,icap_wrdata,sync_retries_counter,sequence_counter,word_index,word_counter,words_to_access,start,data_aligned,data_in,data_out,busy,synced,desync,operation_done,operation_stopped: signal is "true";

begin


-- controller interface
synced                       <= synced_i;
data_out_valid               <= data_out_valid_i;
data_in_fetch                <= data_in_fetch_i;
current_frame_index          <= frame_index;
current_word_index           <= word_index;

-- icap interface
icap_rd_wrn                  <= icap_rd_wrn_i;
icap_clk                     <= clk;

-- Extracting the status bits.
-- Those bits are valid as status only when icap_rd_wrn =0 note(1)
abort_in_progress_n          <= icap_rddata(4);
rdback_in_progress           <= icap_rddata(5);
data_aligned                 <= icap_rddata(6);
cfgerr_n                     <= icap_rddata(7);


state_update_p: process(clk)
begin
  if rising_edge(clk) then
    if reset ='1' then
      current_state     <= UNSYNCED_S;
    else
      current_state     <= next_state;
    end if;
  end if;
end process;


state_transition_p: process (
  current_state,
  start,
  icap_ready,
  data_aligned,
  --synced_i,useless
  --sync_retries_counter, change(3)
  failed_to_sync,--change(3)
  desync,
  operation_done,
  operation_stopped,
  desync_done,
  write_command,
  stop_command)
begin
  case current_state is
    when UNSYNCED_S =>
      -- idling untile start signal is resived and icape ready
      -- checking the abort_in_progress to see if everything is correct
      -- it will sync if the icape is unsynced and it will move directy to SYNCED
      -- if it is allready synced (i dont know if there is a way for it to happen)
      if start = '1' and icap_ready = '1' and data_aligned = '0' then
        next_state <= SYNC_SEQUENCE_S;
      elsif start = '1' and icap_ready = '1' then
        next_state <= SYNCED_S;
      else
        next_state <= UNSYNCED_S;
      end if;


    when SYNC_SEQUENCE_S =>
      -- executing the sync sequence , checking at the end the status bit for alignment
      -- if correct its moving to SYNCED otherwise it retries untile
      -- no more retries left
      if data_aligned = '1' then -- synced_i = '1' has 1 clock delay that is causing it to move to failed_sync
        next_state <= SYNCED_S;
      elsif failed_to_sync = '1' and (sync_retries /= 0) then --change(3) change(7)
        next_state <= FAILED_SYNC_S;
      else
        next_state <= SYNC_SEQUENCE_S;
      end if;


    when SYNCED_S  =>
      -- waits for next command while the icape is synced , it will try to sync
      -- if the icape desyncs it can move to safe desyncing of the icape
      -- only if another command has been executed first
      -- 2026-09-03 (reverted the same day): honouring ANY desync here was tried
      -- as the fix for an algorithm-channel hang and broke the scrubber within
      -- ~20 corrections: the algorithm interface holds desync HIGH whenever it
      -- is idle, and the arbiter's channel mux passes over it during every
      -- arbitration, so the controller desynced on every pass. The hang is
      -- fixed on the algorithm side instead (algorithm_icap_if IDLE_S timeout).
      if desync = '1' and (operation_done = '1' or operation_stopped = '1') then -- added operation_stopped = '1'
        next_state <= DESYNC_SEQUENCE_S;
      elsif data_aligned = '0' then
        next_state <= SYNC_SEQUENCE_S;
      elsif start = '1' and write_command = '0' then
        next_state <= READ_FRAMES_SEQUENCE_S;
      elsif start = '1' then
        next_state <= WRITE_FRAMES_SEQUENCE_S;
      else
        next_state <= SYNCED_S;
      end if;


    when READ_FRAMES_SEQUENCE_S =>
      -- executing the read sequence, it can be stopped safely and
      -- move to stop sequence
      if stop_command = '1' then --change(2)
        next_state <= STOP_SEQUENCE_S;
      elsif operation_done = '1' then
        next_state <= SYNCED_S;
      else
        next_state <= READ_FRAMES_SEQUENCE_S;
      end if;


    when STOP_SEQUENCE_S =>
      -- executing the stop sequence
      if operation_stopped = '1' then
        next_state <= SYNCED_S;
      else
        next_state <= STOP_SEQUENCE_S;
      end if;


    when WRITE_FRAMES_SEQUENCE_S =>
      -- executing the write sequence
      if operation_done = '1' then
        next_state <= SYNCED_S;
      else
        next_state <= WRITE_FRAMES_SEQUENCE_S;
      end if;


    when DESYNC_SEQUENCE_S  =>
      -- executing the desync sequence
      if desync_done = '1' then
        next_state <= UNSYNCED_S;
      else
        next_state <= DESYNC_SEQUENCE_S;
      end if;


    when FAILED_SYNC_S =>
      -- remain here untile reset
      next_state   <= FAILED_SYNC_S;

  end case;
end process;


control_logic_p: process(clk)
begin
  if rising_edge(clk) then

    if reset = '1' then
      sequence_counter            <= (others => '0');
      synced_i                    <= '0';
      operation_done              <= '0';
      operation_stopped           <= '0';
      desync_done                 <= '0';
      sync_retries_counter        <= conv_std_logic_vector(sync_retries-1, sync_retries_counter'length);
      failed_to_sync              <= '0';--change(3)
      words_to_access             <= (others => '0');
      frame_index                 <= (others => '0');
      frames_remaining            <= (others => '0');
      word_index                  <= (others => '0');
      word_counter                <= (others => '0');
      busy                        <= '0';
      data_out_valid_i            <= '0';
      data_dummy                  <= '0';
      data_out                    <= (others => '0');
      -- icap_csn                    <= '1'; Cant chech the status if the csn is paused note(2)
      icap_csn                    <= '0';
      icap_rd_wrn_i               <= '0';
      icap_wrdata                 <= (others => '0');
      data_in_fetch_i             <= '0';
    else
      icap_wrdata                 <= bit_swap(NOOP_WORD);
      synced_i                    <= '1';
      case current_state is
        when UNSYNCED_S =>
          icap_csn                <= '0';
          busy                    <= '0';
          synced_i                <= '0';
          operation_done          <= '0';
          operation_stopped       <= '0';
          desync_done             <= '0';
          icap_rd_wrn_i           <= '0';
          icap_wrdata             <= bit_swap(DUMMY_WORD);
          sequence_counter        <= (others => '0');
          sync_retries_counter    <= conv_std_logic_vector(sync_retries-1, sync_retries_counter'length);
          -- set to busy to signal that the controller will not respond to new
          -- commands "until it finished with syncing"
          if start = '1' and icap_ready = '1' and data_aligned = '0' then
            busy                  <= '1';--change(6)
          end if;
        when SYNC_SEQUENCE_S =>
          icap_csn                <= '0';
          icap_rd_wrn_i           <= '0';
          busy                    <= '1';--change(6)
          operation_done          <= '0';
          operation_stopped       <= '0';
          -- updating the synced here as we know it should change
          synced_i                <= data_aligned; --change(4)
          -- This sequence consists of 6 steps
          -- The sequence_counter is reset at the end of SYNC_SEQUENCE in order to
          -- rerun the synchronization process, in case of no synchronization
          if sequence_counter = 7 then
            sequence_counter      <= (others =>'0');
          else
            sequence_counter      <= sequence_counter + 1;
          end if;
          -- canceling the sync_retries logic if the sync_retries is 0
          if sync_retries /= 0 then
            -- going into fail state when no retries left
            if sync_retries_counter=0 then
              failed_to_sync<='1';--change(3)
            else
              -- The sync_retries_counter is decreased by 1 in case of no synchronization
              if sequence_counter = 7 and data_aligned = '0' then-- the data_aligned seems to be valid at the 3rd cycle after the sync word with the current sequence
                sync_retries_counter  <= sync_retries_counter - 1;
              end if;
            end if;
          end if;
          -- when the data is aligned the next state can respond to new commands so
          -- the busy must be droped
          if data_aligned = '1' then
            busy                  <= '0';--change(6)
          end if;
          -- Reset the retries counter if the alignment was successful to be used next time
          if data_aligned = '1' then
            sync_retries_counter  <= conv_std_logic_vector(sync_retries-1, sync_retries_counter'length);
          end if;
          -- ICAP write data for each step of the sequence
          case sequence_counter is
            when "00000" =>
              icap_wrdata         <= bit_swap(DUMMY_WORD);
            when "00001" =>
              icap_wrdata         <= bit_swap(BUS_WIDTH_SYNC);
            when "00010" =>
              icap_wrdata         <= bit_swap(BUS_WIDTH_DETECT);
            when "00011" =>
              icap_wrdata         <= bit_swap(DUMMY_WORD);
            when "00100" =>
              icap_wrdata         <= bit_swap(SYNC_WORD);
            when "00101" =>
              icap_wrdata         <= bit_swap(NOOP_WORD);
            when others =>
              icap_wrdata         <= bit_swap(NOOP_WORD);
          end case;


        when FAILED_SYNC_S =>
          -- icap_csn             <= '1'; Cant chech the status if the csn is paused note(2)
          icap_csn                <= '0';
          icap_rd_wrn_i           <= '0';
          busy                    <= '0';
          synced_i                <= '0';
          icap_wrdata             <= bit_swap(DUMMY_WORD);


        when SYNCED_S =>
          -- icap_csn             <= '1'; Cant chech the status if the csn is paused note(2)
          icap_csn                <= '0';
          icap_rd_wrn_i           <= '0';
          sequence_counter        <= (others => '0');
          word_index              <= (others => '0');
          frame_index             <= (others => '0');
          frames_remaining        <= num_of_frames;
          word_counter            <= (others => '0');
          desync_done             <= '0';

          if start = '1' then
            operation_done        <= '0';
            operation_stopped     <= '0';

            -- 2026 timing: adder fed from num_r (registered copy of num_of_frames).
            -- Safe: all clients lock their command >=1 cycle before level-start.
            words_to_access       <= conv_std_logic_vector(words_per_frame, words_to_access'length) +
                                     ("0000000" & num_r) +
                                     ("00000" & num_r & "00") +
                                     ("00" & num_r & "00000") +
                                     ("0" & num_r & "000000");
          end if;
          if start='1' or (desync='1' and (operation_done='1' or operation_stopped='1')) then
            busy                  <= '1'; --change(5)
          end if;

        when READ_FRAMES_SEQUENCE_S =>
          -- This sequence consists of 20 steps
          -- sequence_counter = 13 corresponds to Read Dummy Frame
          -- sequence_counter = 14 corresponds to Read Frames
          if stop_command = '1' or sequence_counter = 19 then--change(2)
            sequence_counter      <= (others => '0');
          elsif sequence_counter = 13 then
            if word_counter = words_per_frame - 1 then
              sequence_counter    <= sequence_counter + 1;
            end if;
          elsif sequence_counter = 14 then
            if frames_remaining = 1 and word_counter = words_per_frame - 1 then
              sequence_counter    <= sequence_counter + 1;
            end if;
          else
            sequence_counter      <= sequence_counter + 1;
          end if;
          -- word word counter
          -- used to figure out how many words of the frame have been read from
          -- from the icap. resets every frame . used to figure out how many
          -- frames remain
          if sequence_counter = 13 or sequence_counter = 14 then
            if word_counter = words_per_frame - 1 then
              word_counter        <= (others => '0');
            else
              word_counter        <= word_counter + 1;
            end if;
          end if;
          -- calculating the remaining frames to know when to stop reading
          -- and move to the next step of the sequence
          if sequence_counter = 14 and word_counter = words_per_frame - 1 then
            frames_remaining      <= frames_remaining - 1;
          end if;
          -- The ICAP must be paused to change the read/write mode --note(3)
          -- Two cycles are needed for this change (write to read or read to write)
          if sequence_counter = 6  or sequence_counter = 7 or
             sequence_counter = 15 or sequence_counter = 16 then
            icap_csn              <= '1';
          else
            icap_csn              <= '0';
          end if;
          -- changing the icap with icap_csn=0 to cause an abord which will be
          -- handle by the STOP_SEQUENCE_S
          if stop_command = '1' then--change(2)
            icap_rd_wrn_i         <= '0';
          -- Switch from write to read. the status bits will be invalid and the
          -- icap_rddata will output the frame data
          elsif sequence_counter = 7 then
            icap_rd_wrn_i         <= '1';
          -- Switch from read to write to have valid status bits
          elsif sequence_counter = 16 then
            icap_rd_wrn_i         <= '0';
          end if;
          if sequence_counter = 13 then
            data_dummy<='1';
          else
            data_dummy<='0';
          end if;
          
          -- here we have the actual data to give outside of this block
          if sequence_counter = 14 then
            data_out              <= bit_swap(icap_rddata);
            data_out_valid_i      <='1';
          end if;          
          if sequence_counter /= 14 or stop_command = '1' then
            data_out_valid_i      <='0';
            -- added for testing.. its very helpfull while debuging
            data_out              <= X"DEADDEAD";
          end if;

          -- i am keeping this code until we test all the modules together

          --  if word_index = words_per_frame - 1 then
          --    word_index          <= (others => '0');
          --  else
          --    word_index          <= word_index + 1;
          --  end if;

          --  if word_index = words_per_frame - 1 then
          --    frame_index         <= frame_index + 1;
          --  end if;
          --else

          --  frame_index         <= (others => '0');
          --end if ;
--          if (sequence_counter = 13 and word_counter = words_per_frame - 1)then

--          end if;
--          if (sequence_counter = 14 and word_counter = words_per_frame - 1 and frames_remaining = 1) then

--          end if;

          -- counters for the current outputing word and frame to be used as
          -- addresses to memory
          if data_dummy='1' or data_out_valid_i = '1' then 
            if word_index = words_per_frame - 1 then
              word_index          <= (others => '0');
            else
              word_index          <= word_index + 1;
            end if;
          end if;
          if data_out_valid_i = '1'  then
            if word_index = words_per_frame - 1 then
              frame_index         <= frame_index + 1;
            end if;
          else
            frame_index         <= (others => '0');
          end if;
          -- singaling that the operation is done to change the state and
          -- to allow the system to desync if the desync signal is active
          if sequence_counter = 18 then
            operation_done        <= '1';
          end if;
          -- signaling that the countroler can take the next command
          if operation_done = '1' then
            busy                  <= '0';
          end if;

          --the read frame sequence
          case sequence_counter is
            when "00000" =>
              icap_wrdata         <= bit_swap(CFG_PKT_TYPE1 & WRITE_OPCODE & "000000000" & FAR_REGISTER & "0000000000001");
            when "00001" =>
              icap_wrdata         <= bit_swap("000000" & frame_addr);
            when "00010" =>
              icap_wrdata         <= bit_swap(CFG_PKT_TYPE1 & WRITE_OPCODE & "000000000" & CMD_REGISTER & "0000000000001");
            when "00011" =>
              icap_wrdata         <= bit_swap(RCFG_COMMAND);
            when "00100" =>
              icap_wrdata         <= bit_swap(CFG_PKT_TYPE1 & READ_OPCODE & "000000000" & FDRO_REGISTER & "0000000000000");
            when "00101" =>
              icap_wrdata         <= bit_swap(CFG_PKT_TYPE2 & READ_OPCODE & words_to_access);-- note(4)
            when others =>
              null;
          end case;


        when STOP_SEQUENCE_S =>
          icap_csn                <= '0';
          -- the stop sequence .. changing the read/write mode while the
          -- icap is not paused and wait 4 cycles for the abord status bit to fall
          -- see ug470 SelectMAP ABORT (verstion 1.12+) has some more explenations
          if sequence_counter = 4 then
            sequence_counter      <= (others =>'0');
          else
            sequence_counter      <= sequence_counter + 1;
          end if;
          if sequence_counter = 0 then
            icap_rd_wrn_i         <= not icap_rd_wrn_i;
          end if;
          if sequence_counter = 3 then
            operation_stopped     <= '1';
          end if;


        when WRITE_FRAMES_SEQUENCE_S =>
          icap_csn                <= '0';
          icap_rd_wrn_i           <= '0';
          if sequence_counter = 10 then
            sequence_counter      <= (others => '0');
          elsif sequence_counter = 8 then
            -- in this part of the sequence the frame data are writen to the icap
            -- counting how many words and frames are writen
            if frames_remaining = 1 and word_counter = words_per_frame - 1 then
              sequence_counter    <= sequence_counter + 1;
            end if;
          elsif sequence_counter = 9 then
            -- writing the dummy frame
            if word_counter =  words_per_frame - 1 then
              sequence_counter    <= sequence_counter + 1;
            end if;
          else
            sequence_counter      <= sequence_counter + 1;
          end if;
          -- word counter
          -- used to figure out how many words of the frame have been writen
          -- from the icap. resets every frame . used to figure out how many
          -- frames remain
          if sequence_counter = 8 or sequence_counter = 9 then
            if word_counter = words_per_frame - 1 then
              word_counter        <= (others => '0');
            else
              word_counter        <= word_counter + 1;
            end if;
          end if;
          -- calculating the remaining frames to know when to stop writing
          -- and move to the next step of the sequence
          if sequence_counter = 8 and word_counter = words_per_frame - 1 then
            frames_remaining      <= frames_remaining - 1;
          end if;
          -- it 'requests' the data 3 cycles earlier than needed 1 cycle so it has
          -- time to write the correct data to the icap_wrdata and 2 cycles for
          -- the delay of the memories that are expected to be used from the other
          -- blocks. also stops 3 cycles earlier note(5)
          if sequence_counter = 5 then
            data_in_fetch_i       <= '1';
          elsif frames_remaining = 1 and word_counter = words_per_frame - 2 then
            data_in_fetch_i       <= '0';
          end if;
          -- counters for the current outputing word and frame to be used as
          -- addresses to memory
          if data_in_fetch_i = '1' then
            if word_index = words_per_frame - 1 then
              word_index          <= (others => '0');
            else
              word_index          <= word_index + 1;
            end if;
            if word_index = words_per_frame - 1 then
              frame_index         <= frame_index + 1;
            else
              frame_index         <= (others => '0');
            end if;
          end if;
          -- write sequence
          case sequence_counter is
            when "00000" =>
              icap_wrdata         <= bit_swap(CFG_PKT_TYPE1 & WRITE_OPCODE & "000000000" & IDCODE_REGISTER & "0000000000001");
            when "00001" =>
              icap_wrdata         <= bit_swap(device_idcode);
            when "00010" =>
              icap_wrdata         <= bit_swap(CFG_PKT_TYPE1 & WRITE_OPCODE & "000000000" & FAR_REGISTER & "0000000000001");
            when "00011" =>
              icap_wrdata         <= bit_swap("000000" & frame_addr);
            when "00100" =>
              icap_wrdata         <= bit_swap(CFG_PKT_TYPE1 & WRITE_OPCODE & "000000000" & CMD_REGISTER & "0000000000001");
            when "00101" =>
              icap_wrdata         <= bit_swap(WCFG_COMMAND);
            when "00110" =>
              icap_wrdata         <= bit_swap(CFG_PKT_TYPE1 & WRITE_OPCODE & "000000000" & FDRI_REGISTER & "0000000000000");
            when "00111" =>
              icap_wrdata         <= bit_swap(CFG_PKT_TYPE2 & WRITE_OPCODE & words_to_access);
            when "01000" =>
              icap_wrdata         <= bit_swap(data_in);
            when "01001" =>
              icap_wrdata         <= bit_swap(DUMMY_WORD);
            when others =>
              null;
          end case;
          -- singaling that the operation is done to change the state and
          -- to allow the system to desync if the desync signal is active
          if sequence_counter = 9 and word_counter = words_per_frame - 1 then
            operation_done        <= '1';
          end if;
          -- signaling that the countroler can take the next command
          if operation_done = '1' then
            busy                  <= '0';-- change(5)
          end if;


        when DESYNC_SEQUENCE_S =>
          icap_csn                <= '0';
          icap_rd_wrn_i           <= '0';
          -- updating the synced here as we know it should change
          synced_i                <= data_aligned; -- note(6)
          if sequence_counter = 6 then
            sequence_counter      <= (others => '0');
          else
            sequence_counter      <= sequence_counter + 1;
          end if;
          --desync sequence
          if sequence_counter = 0 then
            icap_wrdata           <= bit_swap(CFG_PKT_TYPE1 & WRITE_OPCODE & "000000000" & CMD_REGISTER & "0000000000001");
          elsif sequence_counter = 1 then
            icap_wrdata           <= bit_swap(DESYNC_COMMAND);
          elsif sequence_counter = 6 then
            icap_wrdata           <= bit_swap(DUMMY_WORD);
          end if;
          -- singaling that the desync is done to to move to the unsynced state
          if sequence_counter = 5 then
            desync_done           <= '1';
          end if;
          -- signaling that the countroler can take the next command
          if desync_done = '1' then
            busy                  <= '0';
          end if;
        when others =>
          null;
     end case;
   end if;
  end if;
end process;

  num_r_p: process(clk)  -- 2026 timing: free-running capture of muxed num_of_frames
  begin
    if rising_edge(clk) then
      num_r <= num_of_frames;
    end if;
  end process;

end behavioral;
