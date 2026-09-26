-- SPDX-License-Identifier: MIT
-- Copyright (c) 2020-2026 John Vrachnis
----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 09/17/2020 05:08:47 PM
-- Design Name: 
-- Module Name: parity_calculator_tb - Behavioral
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
use ieee.std_logic_unsigned.all;
use ieee.std_logic_arith.conv_std_logic_vector;
use work.log2_pkg.all;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity parity_calculator_tb is
--  Port ( );
end parity_calculator_tb;

architecture Behavioral of parity_calculator_tb is
component golden_parity_mem
   generic
     (
     bits_per_word           : integer := 32;
     words_per_frame         : integer := 101;
     frame_addr_width        : integer := 26;
     col_per_row             : integer := 56; --74;
     top_rows                : integer := 1;
     bot_rows                : integer := 1; --2;
     cols_per_group          : integer := 1;
     subgroups_per_group     : integer := 2;
     frames_per_mem          : integer := 5
     );
   port
     (
     clk                     : in  std_logic;
     reset                   : in  std_logic;
     word_write              : in  std_logic;
     new_frame_write         : in  std_logic;
     group_wr_addr           : in  std_logic_vector(frame_addr_width-1 downto 0);
     subgroup_wr_addr        : in  std_logic_vector(log2(subgroups_per_group)-1 downto 0);
     word_wr_data            : in  std_logic_vector(bits_per_word - 1 downto 0);
     word_read               : in  std_logic;
     new_frame_read          : in  std_logic;
     group_rd_addr           : in  std_logic_vector(frame_addr_width-1 downto 0);
     subgroup_rd_addr        : in  std_logic_vector(log2(subgroups_per_group)-1 downto 0);
     word_rd_valid           : out std_logic;
     word_rd_data            : out std_logic_vector(bits_per_word - 1 downto 0) := (others => '0')
     );
end component;
component parity_calculator
   generic(
  total_frames: integer:=10;
  words_per_frame: integer:=101;
  bits_per_word: integer:=32;
  max_frames_per_group: integer:=64;
  subgroups_per_group: integer:=2;
  frame_addr_width: integer:=26;
  start_frame_addr:std_logic_vector(26-1 downto 0):=(others=>'0');
  end_frame_addr:std_logic_vector(26-1 downto 0):=(25=>'1',others=>'0')
  );
  Port (
  ----Control Interface----
  clk: in std_logic;
  reset: in std_logic;
  ----FRAME ECC primitive Interface----
  fecc_far: in std_logic_vector(frame_addr_width-1 downto 0);
  ----Syndromes Handler Interface----
  group_frame_addr: in std_logic_vector(frame_addr_width-1 downto 0);
  start_parity_calc: in std_logic;
  parity_calc_done: out std_logic;
  ----Golden Parity Memory Interface----
  pmem_word_write: out std_logic;
  pmem_new_frame_write: out std_logic;
  pmem_group_wr_addr: out std_logic_vector(frame_addr_width-1 downto 0);
  pmem_subgroup_wr_addr: out std_logic_vector(log2(subgroups_per_group)-1 downto 0);
  pmem_word_wr_data: out std_logic_vector(bits_per_word-1 downto 0);
  pmem_word_read: out std_logic;
  pmem_new_frame_read: out std_logic;
  pmem_group_rd_addr: out std_logic_vector(frame_addr_width-1 downto 0);
  pmem_subgroup_rd_addr: out std_logic_vector(log2(subgroups_per_group)-1 downto 0);
  pmem_word_rd_valid: in std_logic;
  pmem_word_rd_data: in std_logic_vector(bits_per_word-1 downto 0);

  ----Calculated Parity Memory Interface----
  calc_word_read : out std_logic;
  calc_word_rd_addr:out std_logic_vector(log2(words_per_frame)-1 downto 0);
  calc_subgroup_rd_addr:out std_logic_vector(log2(subgroups_per_group)-1 downto 0);
  calc_word_rd_data :in std_logic_vector(bits_per_word-1 downto 0);
  calc_word_write : out std_logic;
  calc_word_wr_addr: out std_logic_vector(log2(words_per_frame)-1 downto 0);
  calc_subgroup_wr_addr: out std_logic_vector(log2(subgroups_per_group)-1 downto 0);
  calc_word_wr_data : out std_logic_vector(bits_per_word-1 downto 0);

  ----ICAP Arbiter Interface----
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
  icap_num_of_frames: out std_logic_vector(log2(total_frames)-1 downto 0);
  icap_current_frame_index: in std_logic_vector(log2(max_frames_per_group)-1 downto 0);
  icap_current_word_index: in std_logic_vector(log2(words_per_frame)-1 downto 0);
  icap_data_in: out std_logic_vector(bits_per_word-1 downto 0);
  icap_data_out: in std_logic_vector(bits_per_word-1 downto 0)
  );
end component;
component calc_parity_mem
   generic
     (
     bits_per_word           : integer := 32;
     words_per_frame         : integer := 101;
     subgroups_per_group     : integer := 2
     );
   port
     (
     clk                     : in  std_logic;
     reset                   : in  std_logic;
     -- Parity Calculator Interface
     calc_word_write         : in  std_logic;
     calc_word_wr_addr       : in  std_logic_vector(log2(words_per_frame)-1 downto 0);
     calc_subgroup_wr_addr   : in  std_logic_vector(log2(subgroups_per_group)-1 downto 0);
     calc_word_wr_data       : in  std_logic_vector(bits_per_word - 1 downto 0);
     -- Algorithm Calculator Interface
     alg_word_write          : in  std_logic;
     alg_word_wr_addr        : in  std_logic_vector(log2(words_per_frame)-1 downto 0);
     alg_subgroup_wr_addr    : in  std_logic_vector(log2(subgroups_per_group)-1 downto 0);
     alg_select_wr_bank      : in  std_logic;
     alg_word_wr_data        : in  std_logic_vector(bits_per_word - 1 downto 0);
     alg_word_read           : in  std_logic;
     alg_word_rd_addr        : in  std_logic_vector(log2(words_per_frame)-1 downto 0);
     alg_subgroup_rd_addr    : in  std_logic_vector(log2(subgroups_per_group)-1 downto 0);
     alg_select_rd_bank      : in  std_logic;
     alg_word_rd_data        : out std_logic_vector(bits_per_word - 1 downto 0)
     );
end component;
constant total_frames: integer:=5153;
constant words_per_frame: integer:=101;
constant bits_per_word: integer:=32;
constant max_frames_per_group: integer:=64;
constant subgroups_per_group: integer:=2;
constant frame_addr_width: integer:=26;
constant start_frame_addr:std_logic_vector(frame_addr_width-1 downto 0):=(others=>'0');
constant end_frame_addr:std_logic_vector(frame_addr_width-1 downto 0):=(0=>'1',1=>'1',2=>'1',9=>'1',others=>'0');
signal clk                     : std_logic := '1';
signal reset                   : std_logic := '0';
----FRAME ECC primitive Interface----
  signal fecc_far: std_logic_vector(frame_addr_width-1 downto 0):=(others=>'0');
  ----Syndromes Handler Interface----
  signal group_frame_addr: std_logic_vector(frame_addr_width-1 downto 0):=(others=>'0');
  signal start_parity_calc: std_logic;
  signal parity_calc_done: std_logic;
  
  ----Golden Parity Memory Interface----
signal word_write              : std_logic := '0';
signal new_frame_write         : std_logic := '0';
signal group_wr_addr           : std_logic_vector(25 downto 0) := (others => '0');
signal word_wr_data            : std_logic_vector(31 downto 0) := (others => '0');
signal word_read               : std_logic := '0';
signal new_frame_read          : std_logic := '0';
signal group_rd_addr           : std_logic_vector(25 downto 0) := (others => '0');
signal word_rd_data            : std_logic_vector(31 downto 0) := (others => '0');
signal word_rd_valid           : std_logic;

signal subgroup_wr_addr        : std_logic_vector(log2(subgroups_per_group)-1 downto 0);
signal subgroup_rd_addr        : std_logic_vector(log2(subgroups_per_group)-1 downto 0);
----Calculated Parity Memory Interface----
  signal calc_word_read : std_logic;
  signal calc_word_rd_addr: std_logic_vector(log2(words_per_frame)-1 downto 0);
  signal calc_subgroup_rd_addr: std_logic_vector(log2(subgroups_per_group)-1 downto 0);
  signal calc_word_rd_data : std_logic_vector(bits_per_word-1 downto 0);
  signal calc_word_write :  std_logic;
  signal calc_word_wr_addr:  std_logic_vector(log2(words_per_frame)-1 downto 0);
  signal calc_subgroup_wr_addr:  std_logic_vector(log2(subgroups_per_group)-1 downto 0);
  signal calc_word_wr_data :  std_logic_vector(bits_per_word-1 downto 0);

  ----ICAP Arbiter Interface----
  signal icap_request        :  std_logic;
  signal icap_grant          :  std_logic:='0';
  signal icap_start          :  std_logic;
  signal icap_stop           :  std_logic;
  signal icap_write_command  :  std_logic;
  signal icap_register_access:  std_logic;
  signal icap_desync         :  std_logic;
  signal icap_busy           :  std_logic:='0';
  signal icap_synced         :  std_logic:='0';
  signal icap_data_in_fetch  :  std_logic:='0';
  signal icap_data_out_valid :  std_logic:='0';
  signal icap_frame_addr:  std_logic_vector(frame_addr_width-1 downto 0);
  signal icap_num_of_frames:  std_logic_vector(log2(total_frames)-1 downto 0);
  signal icap_current_frame_index:  std_logic_vector(log2(max_frames_per_group)-1 downto 0):=(others=>'0');
  signal icap_current_word_index:  std_logic_vector(log2(words_per_frame)-1 downto 0):=(others=>'0');
  signal icap_data_in:  std_logic_vector(bits_per_word-1 downto 0);
  signal icap_data_out:  std_logic_vector(bits_per_word-1 downto 0):=(0=>'1',others=>'0');
  --local
begin

clk <= not clk after 5 ns;
reset <= '1', '0' after 101 ns;

icap_grant <= icap_request;
process(clk)
begin
    if rising_edge(clk) then
        if icap_busy='0' then
            fecc_far<=(0=>'0',1=>'0',others=>'0');
        elsif conv_integer(icap_current_word_index)=100 then
            fecc_far<=conv_std_logic_vector(conv_integer(fecc_far)+1,fecc_far'length);
        end if;
        if conv_integer(icap_current_word_index)=100 and icap_data_out_valid='0' then
            icap_data_out_valid<='1';
        elsif icap_desync='1' then
            icap_data_out_valid<='0';
        end if;
        
        if icap_busy='0' or conv_integer(icap_current_word_index)=100 then
            icap_current_word_index <= (others=>'0');
        else
            icap_current_word_index <= conv_std_logic_vector(conv_integer(icap_current_word_index)+1,icap_current_word_index'length);
        end if;
    end if;
end process;
icap_busy <= icap_start or icap_busy when icap_desync='0' else '0';
icap_synced <= icap_start or icap_busy when icap_desync='0' else '0';

start_parity_calc<='0','1' after 16500 ns;
calc_parity :calc_parity_mem
   port map
     (
     clk                     =>clk,
     reset                   =>reset,
     -- Parity Calculator Interface
     calc_word_write         =>calc_word_write,
     calc_word_wr_addr       =>calc_word_wr_addr,
     calc_subgroup_wr_addr   =>calc_subgroup_wr_addr,
     calc_word_wr_data       =>calc_word_wr_data,
     -- Algorithm Calculator Interface
     alg_word_write          =>'0',
     alg_word_wr_addr        =>(others=>'0'),
     alg_subgroup_wr_addr    =>(others=>'0'),
     alg_select_wr_bank      =>'0',
     alg_word_wr_data        =>(others=>'0'),
     alg_word_read           =>calc_word_read,
     alg_word_rd_addr        =>calc_word_rd_addr,
     alg_subgroup_rd_addr    =>calc_subgroup_rd_addr,
     alg_select_rd_bank      =>'0',
     alg_word_rd_data        =>calc_word_rd_data
     
     );
golden_parity: golden_parity_mem
   generic map
     (
     bits_per_word           => 32,
     words_per_frame         => 101,
     frame_addr_width        => 26,
     col_per_row             => 74,
     top_rows                => 1,
     bot_rows                => 2,
     subgroups_per_group     => 2,
     frames_per_mem          => 5
     )
   port map
     (
     clk                     => clk,
     reset                   => reset,
     word_write              => word_write,
     new_frame_write         => new_frame_write,
     group_wr_addr           => group_wr_addr,
     subgroup_wr_addr        => subgroup_wr_addr,
     word_wr_data            => word_wr_data,
     word_read               => word_read,
     new_frame_read          => new_frame_read,
     group_rd_addr           => group_rd_addr,
     subgroup_rd_addr        => subgroup_rd_addr,
     word_rd_valid           => word_rd_valid,
     word_rd_data            => word_rd_data
     );
     
parity_calculator_inst:parity_calculator
  generic map(
  total_frames=> total_frames,
  start_frame_addr=>start_frame_addr,
  end_frame_addr=>end_frame_addr
  )
  Port map(
  ----Control Interface----
  clk=>clk,
  reset=>reset,
  ----FRAME ECC primitive Interface----
  fecc_far=>fecc_far,
  ----Syndromes Handler Interface----
  group_frame_addr=>group_frame_addr,
  start_parity_calc=>start_parity_calc,
  parity_calc_done=>parity_calc_done,
  
  ----Golden Parity Memory Interface----
  pmem_word_write=>word_write,
  pmem_new_frame_write=>new_frame_write,
  pmem_group_wr_addr=>group_wr_addr,
  pmem_subgroup_wr_addr=>subgroup_wr_addr,
  pmem_word_wr_data=>word_wr_data,
  pmem_word_read=>word_read,
  pmem_new_frame_read=>new_frame_read,
  pmem_group_rd_addr=>group_rd_addr,
  pmem_subgroup_rd_addr=>subgroup_rd_addr,
  pmem_word_rd_valid=>word_rd_valid,
  pmem_word_rd_data=>word_rd_data,

  ----Calculated Parity Memory Interface----
  calc_word_read =>calc_word_read,
  calc_word_rd_addr=>calc_word_rd_addr,
  calc_subgroup_rd_addr=>calc_subgroup_rd_addr,
  calc_word_rd_data =>calc_word_rd_data,
  calc_word_write =>calc_word_write,
  calc_word_wr_addr=>calc_word_wr_addr,
  calc_subgroup_wr_addr=>calc_subgroup_wr_addr,
  calc_word_wr_data =>calc_word_wr_data,

  ----ICAP Arbiter Interface----
  icap_request        =>icap_request,
  icap_grant          =>icap_grant,
  icap_start          =>icap_start,
  icap_stop           =>icap_stop,
  icap_write_command  =>icap_write_command,
  icap_register_access=>icap_register_access,
  icap_desync         =>icap_desync,
  icap_busy           =>icap_busy,
  icap_synced         =>icap_synced,
  icap_data_in_fetch  =>icap_data_in_fetch,
  icap_data_out_valid =>icap_data_out_valid,
  icap_frame_addr     =>icap_frame_addr,
  icap_num_of_frames  =>icap_num_of_frames,
  icap_current_frame_index =>icap_current_frame_index,
  icap_current_word_index  =>icap_current_word_index,
  icap_data_in             =>icap_data_in,
  icap_data_out            =>icap_data_out
  );
end Behavioral;
