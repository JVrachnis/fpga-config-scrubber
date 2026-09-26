library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

use work.icape_common.all;

package icape_com_producers is
    procedure WRITE_REGISTER_f(
        Address:in std_logic_vector(7 downto 0) ;
        DATA :in std_logic_vector(31 downto 0);
        signal CSIB,RDWRB:out std_logic;
        DONE : out std_logic;
        signal Word :out std_logic_vector(31 downto 0)
    );
       
end package icape_com_producers;

package body icape_com_producers is

    procedure WRITE_REGISTER_f(
        Address:in std_logic_vector(7 downto 0) ;
        DATA :in std_logic_vector(31 downto 0);
        signal CSIB,RDWRB:out std_logic;
        DONE : out std_logic;
        signal Word :out std_logic_vector(31 downto 0)
    )is
    variable State_WRITE : State_WRITE_type:=Write_cmd_word;
    begin
        case State_WRITE is
            when Write_cmd_word=>
                DONE:='0';
                CSIB<='0';
                RDWRB<='0';
                Word<=WRITE_REGISTER_WORD & Address & WRITE_REGISTER_MODE_1;
                State_WRITE:=Write_data;
            when Write_data=>
                DONE:='1';
                CSIB<='0';
                RDWRB<='0';
                Word<=DATA;
                State_WRITE:=Write_cmd_word;
            when others =>
                DONE:='1';
                State_WRITE:=Write_cmd_word;
        end case;
    end WRITE_REGISTER_f;

end package body icape_com_producers; 