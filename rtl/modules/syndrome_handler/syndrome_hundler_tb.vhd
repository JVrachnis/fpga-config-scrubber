-- SPDX-License-Identifier: MIT
-- Copyright (c) 2020-2026 John Vrachnis
----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 09/25/2020 09:31:10 AM
-- Design Name: 
-- Module Name: syndrome_hundler_tb - Behavioral
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

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity syndrome_hundler_tb is
--  Port ( );
end syndrome_hundler_tb;

architecture Behavioral of syndrome_hundler_tb is
component syndrome_handler
  Generic (
  scanned_groups_without_error: integer:=	64;
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
  error_correction_done:in std_logic
  );
end component;
  constant scanned_groups_without_error: integer:=	128;
  constant syndromes_mem_entries:	integer:=	128;
  constant words_per_frame:	integer:=	101;
  constant bits_per_word:	integer:=	32;
  constant max_frames_per_group:	integer:=	64;
  constant subgroups_per_group:	integer:=	2;
  constant frame_addr_width:	integer:=	26;
  signal clk: std_logic:='0';
  signal reset: std_logic:='0';
  signal start_frame_addr: std_logic_vector(frame_addr_width-1 downto 0):=(others=>'0');
  signal end_frame_addr: std_logic_vector(frame_addr_width-1 downto 0):=(25=>'1',others=>'0');
  signal crc_only: std_logic:='0';
  --FRAME ECC primitive Interface
  signal fecc_syndromevalid: std_logic:='0';
  signal fecc_eccerror: std_logic:='0';
  signal fecc_syndrome: std_logic_vector(log2(words_per_frame)+log2(bits_per_word) downto 0):=(others=>'0');
  signal fecc_crcerror: std_logic:='0';
  signal fecc_far: std_logic_vector(frame_addr_width-1 downto 0):=(others=>'0');
  signal fecc_synword: std_logic_vector(log2(words_per_frame)-1 downto 0):=(others=>'0');
  signal fecc_synbit: std_logic_vector(log2(bits_per_word)-1 downto 0):=(others=>'0');
  signal fecc_eccerrorsingle: std_logic:='0';
  --Parity Calculator Interface
  signal group_frame_address: std_logic_vector(frame_addr_width-1 downto 0):=(others=>'0');
  signal start_parity_calc: std_logic:='0';
  signal parity_calc_done: std_logic:='0';
  --2D EDC Algorithm Interface:
  signal start_error_correction: std_logic:='0';
  signal err_group_address: std_logic_vector(frame_addr_width-1 downto 0):=(others=>'0');
  signal err_frame_count: std_logic_vector(log2(max_frames_per_group)-1 downto 0):=(others=>'0');
  signal single_frame_in_subgr: std_logic_vector(subgroups_per_group-1 downto 0):=(others=>'0');
  signal read_syndromes_mem: std_logic:='0';
  signal syndromes_mem_offset: std_logic_vector(log2(max_frames_per_group)-1 downto 0):=(others=>'0');
  signal err_frame_address: std_logic_vector(log2(max_frames_per_group)-1 downto 0):=(others=>'0');
  signal err_frame_synword: std_logic_vector(6 downto 0):=(others=>'0');
  signal err_frame_synbit: std_logic_vector(4 downto 0):=(others=>'0');
  signal odd_errors_in_frame: std_logic:='0';
  signal error_correction_done: std_logic:='0';
  
  
  signal current_word_index: std_logic_vector(log2(words_per_frame)-1 downto 0):=(others=>'0');
begin
clk <= not clk after 5 ns;
reset <= '1', '0' after 101 ns;
fecc_eccerror<='1' when (conv_integer(fecc_far) mod 2)=0 else '0';
fecc_syndrome<="1011101011101";
process(clk)
begin
    
    if rising_edge(clk) then
        
        fecc_syndromevalid<='0';
        error_correction_done<='0';
        if start_parity_calc='1' then
            parity_calc_done<='1';
            
        end if;
        if  start_parity_calc='1' then
            fecc_far<=(0=>'1',1=>'0',others=>'0');
        elsif reset='1' or start_error_correction='1' then
            fecc_syndromevalid<='1';
            fecc_far<=(0=>'1',1=>'0',others=>'0');
        elsif conv_integer(current_word_index)=100 then
            fecc_syndromevalid<='1';
            fecc_far<=conv_std_logic_vector(conv_integer(fecc_far)+1,fecc_far'length);
        end if;
        
        if reset='1'  or start_parity_calc='1' or conv_integer(current_word_index)=100 then
            current_word_index <= (others=>'0');
        else
            current_word_index <= conv_std_logic_vector(conv_integer(current_word_index)+1,current_word_index'length);
        end if;
        
        if start_error_correction='1' then
            if conv_integer(current_word_index)=100 then
                error_correction_done<='1';
            end if;
            read_syndromes_mem <='1';
            syndromes_mem_offset<=(2=>'1',others=>'0');
        end if;
    end if;
end process;
  
syndrome_handler_inst:syndrome_handler
  Generic map(
  scanned_groups_without_error =>	128,
  syndromes_mem_entries =>	128,
  words_per_frame =>	101,
  bits_per_word =>	32,
  max_frames_per_group =>	64,
  subgroups_per_group =>	2,
  frame_addr_width =>	26
  )
  Port map(
  --Control Interface
  clk =>clk,
  reset =>reset,
  start_frame_addr =>start_frame_addr,
  end_frame_addr =>end_frame_addr,
  crc_only =>crc_only,
  --FRAME ECC primitive Interface
  fecc_syndromevalid =>fecc_syndromevalid,
  fecc_eccerror =>fecc_eccerror,
  fecc_syndrome =>fecc_syndrome,
  fecc_crcerror =>fecc_crcerror,
  fecc_far =>fecc_far,
  fecc_synword =>fecc_synword,
  fecc_synbit =>fecc_synbit,
  fecc_eccerrorsingle =>fecc_eccerrorsingle,
  --Parity Calculator Interface
  group_frame_address =>group_frame_address,
  start_parity_calc =>start_parity_calc,
  parity_calc_done =>parity_calc_done,
  --2D EDC Algorithm Interface:
  start_error_correction =>start_error_correction,
  err_group_address =>err_group_address,
  err_frame_count =>err_frame_count,
  single_frame_in_subgr =>single_frame_in_subgr,
  read_syndromes_mem =>read_syndromes_mem,
  syndromes_mem_offset =>syndromes_mem_offset,
  err_frame_address =>err_frame_address,
  err_frame_synword =>err_frame_synword,
  err_frame_synbit =>err_frame_synbit,
  odd_errors_in_frame =>odd_errors_in_frame,
  error_correction_done =>error_correction_done
  );
end Behavioral;
