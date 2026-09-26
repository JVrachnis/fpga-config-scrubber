----------------------------------------------------------------------------------
-- Company:
-- Engineer:
--
-- Create Date: 12/05/2019 07:47:18 PM
-- Design Name:
-- Module Name: Fault_injection_AXI - Behavioral
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
-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity Fault_injection_AXI is
  Port (Clk: in std_logic;
        aresetn: in std_logic;

        far_address:in std_logic_vector(23 downto 0);
        word_pos:in std_logic_vector(7 downto 0);
        fault_word:in std_logic_vector(31 downto 0);

        enable:inout std_logic;

        mode: in std_logic_vector(30 downto 0);
        Busy:out std_logic;
        synced :out std_logic;
        status:out std_logic_vector(29 downto 0)
         );
end Fault_injection_AXI;

architecture Behavioral of Fault_injection_AXI is
component ICAP_Fault_Injection
    generic(
        mem_addr_width     : integer := 7;
        mem_data_width     : integer := 32
    );
  Port (CLK :in std_logic;
        Start:in std_logic;
        Busy:out std_logic;
        synced:out std_logic;
        Far_address:in std_logic_vector(23 downto 0);
        Word_pos:in std_logic_vector(7 downto 0);
        Fault_Word:in std_logic_vector(31 downto 0)
        );
end component;
    signal Start:std_logic;
    signal Far_address_r: std_logic_vector(23 downto 0);
    signal Word_pos_r: std_logic_vector(7 downto 0);
    signal Fault_Word_r: std_logic_vector(31 downto 0);
begin
    process(Clk,aresetn)
    begin
        if(aresetn='1') then
            status<=(others=>'0');
        else
            Start<=enable;
            if enable='1' then
                Far_address_r<=far_address;
                Word_pos_r<=word_pos;
                Fault_Word_r<=fault_word;
            end if;

            enable<='0';

        end if;
    end process;
ICAP_Fault_Injection_inst :ICAP_Fault_Injection
  Port map(CLK =>Clk,
          Start=>Start,
          Busy=>Busy,
          synced=>synced,
          Far_address=>Far_address_r,
          Word_pos=>Word_pos_r,
          Fault_Word=>Fault_Word_r
          );

end Behavioral;
