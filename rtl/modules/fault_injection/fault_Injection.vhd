-- SPDX-License-Identifier: MIT
-- Copyright (c) 2021-2026 John Vrachnis
library IEEE;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_arith.conv_std_logic_vector;
use work.log2_pkg.all;

library UNISIM;
use UNISIM.VComponents.all;

library work;
use work.icape_common.all;

entity fault_Injection is
  generic(
    frame_width : integer := 7;
      words_per_frame: integer:=101;
      bits_per_word: integer:=32;
      max_frames_per_group: integer:=64;
      subgroups_per_group: integer:=2;
      frame_addr_width: integer:=26
    );
  port (
  CLK         : in  std_logic;
  Start       : in  std_logic;
  desync      : in  std_logic;
  request     : in  std_logic;
  Busy        : out std_logic;
  synced      : out std_logic;
  Far_address_i : in  std_logic_vector(frame_addr_width-1 downto 0);
  Word_pos_i    : in  std_logic_vector(frame_width-1 downto 0);
  Fault_Word_i  : in  std_logic_vector(bits_per_word-1 downto 0);


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
  -- 2026-09-03 readback: the frame buffer as captured by the last operation
  -- (post-XOR; mask 0 = the frame as read). Second BRAM port, registered.
  rb_addr : in  std_logic_vector(6 downto 0) := (others => '0');
  rb_data : out std_logic_vector(bits_per_word-1 downto 0)
        );
end fault_Injection;

architecture Behavioral of fault_Injection is
  signal current_frame: frame_t;
  signal Fault_Word,icap_data_in_i: std_logic_vector(31 downto 0);
  signal Far_address  : std_logic_vector(25 downto 0);
  signal Word_pos:std_logic_vector(6 downto 0);
  signal Done,icap_ready,icap_busy_d : std_logic;
  signal FDR                                                                                                                                                                                                                           : std_logic_vector(7 downto 0):=x"64";
  signal address_of_word_of_frame,state,next_state,icap_current_word_index_d: integer;
  signal current_frame_s:frame_t;
--  attribute mark_debug                                                                                                                                                                                                                 : string;
--  attribute mark_debug of Far_address, Word_pos,Fault_Word,
--        address_of_word_of_frame,state,busy,start,icap_busy,synced,icap_start,icap_data_in_fetch,icap_data_out_valid,icap_current_word_index: signal is "true";
begin

  process(CLK)
  variable address: integer;
  begin
    if rising_edge(CLK) then
      state<=next_state;
    end if;
  end process;
  process(icap_busy,icap_busy_d,icap_ready,state,start,icap_grant)
  variable address: integer;
  begin


    case state is
    when 0=>
      if start = '1' and icap_grant='1' then
        next_state<=1;
      else
        next_state<=0;
      end if;
    when 1=>
      if icap_busy = '1' and icap_synced = '1' then
        next_state<=2;
      else
        next_state<=1;
      end if;
    when 2=>
      if icap_busy = '0' then
        next_state<=3;
      else
        next_state<=2;
      end if;
    when 3=>
      if icap_busy = '1' then
        next_state<=4;
      else
        next_state<=3;
      end if;
    when 4=>
      if icap_busy = '0' then
        next_state<=0;
      else
        next_state<=4;
      end if;
    when others=>
      next_state<=0;
    end case;
  end process;
  process(CLK)
  variable address: integer;
  begin
    if rising_edge(CLK) then
      icap_stop<='0';
      icap_desync <= desync;
      icap_ready<= '0';
      synced <= icap_synced;
      busy<='1';
      icap_num_of_frames<=(0=>'1',others=>'0');
      icap_register_access<='0';
      icap_frame_addr<=Far_address;
      icap_current_word_index_d<=conv_integer(icap_current_word_index);
      case state is
      when 0=>
        icap_request<=request;
        busy<='0';
        Fault_Word<=Fault_Word_i;
        Word_pos<=Word_pos_i;
        Far_address<=Far_address_i;
        icap_write_command<='0';
        icap_start<='0';
        Done<='1';
      when 1=>
        icap_write_command<='0';
        icap_start<='1';
        Done<='0';
      when 2=>
        icap_write_command<='0';
        icap_start<='0';
        Done<='0';
        if icap_data_out_valid='1' then
          if Word_pos = icap_current_word_index then
           current_frame_s(conv_integer(icap_current_word_index))<=icap_data_out xor Fault_Word;
          else
           current_frame_s(conv_integer(icap_current_word_index))<=icap_data_out;
          end if;
        end if;
      when 3=>
        icap_write_command<='1';
        icap_start<='1';
        Done<='0';
      when 4=>
        icap_write_command<='0';
        icap_start<='0';
        Done<='0';
        -- FIX(2026): never present DEADBEEF on the write bus; always drive the
        -- real frame word. The old DEADBEEF fallback on non-fetch cycles,
        -- combined with the 2-cycle write pipeline, corrupted one word at the
        -- frame boundary regardless of Word_pos/Fault_Word -- producing a fixed
        -- syndrome even for mask=0. Holding current_frame_s removes that artifact.
        icap_data_in_i<= current_frame_s(conv_integer(icap_current_word_index));
        icap_data_in  <= icap_data_in_i;
      when others=>
        null;
      end case ;
    end if;
  end process;

  readback_p : process(CLK)
  begin
    if rising_edge(CLK) then
      rb_data <= current_frame_s(conv_integer(rb_addr));
    end if;
  end process;

end Behavioral;
