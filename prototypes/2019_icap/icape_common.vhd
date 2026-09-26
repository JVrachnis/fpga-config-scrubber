library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

package icape_common is
    constant DUMMY_WORD : std_logic_vector(31 downto 0):= x"FFFFFFFF";
    constant NOOP_WORD : std_logic_vector(31 downto 0):= x"20000000";
    constant SYNC_WORD : std_logic_vector(31 downto 0):= x"AA995566";
    constant BUS_DETECT_1 : std_logic_vector(31 downto 0):= x"000000BB";
    constant BUS_DETECT_2 : std_logic_vector(31 downto 0):= x"11220044";

    constant DESYNC_COMMAND : std_logic_vector(31 downto 0):= x"0000000D";
    constant SHUTDOWN_COMMAND : std_logic_vector(31 downto 0):= x"0000000B";
    constant START_COMMAND : std_logic_vector(31 downto 0):= x"00000005";
    constant RCRC_COMMAND : std_logic_vector(31 downto 0):= x"00000007";
    constant RCFG_COMMAND : std_logic_vector(31 downto 0):= x"00000004";
    constant WCFG_COMMAND : std_logic_vector(31 downto 0):= x"00000001";
    constant READ_REGISTER_WORD : std_logic_vector(11 downto 0):= x"280";
    constant READ_REGISTER_MODE_1 : std_logic_vector(11 downto 0):= x"001";
    constant WRITE_REGISTER_WORD : std_logic_vector(11 downto 0):= x"300";
    constant WRITE_REGISTER_MODE_1 : std_logic_vector(11 downto 0):= x"001";

    constant CMD_REGISTER : std_logic_vector(7 downto 0):= X"08";
    constant IDCODE_REGISTER : std_logic_vector(7 downto 0):= X"18";
    constant STAT_REGISTER : std_logic_vector(7 downto 0):= X"0B";
    constant FAR_REGISTER : std_logic_vector(7 downto 0):= X"02";
    constant FDRO_REGISTER : std_logic_vector(7 downto 0):= X"06";
    constant FDRI_REGISTER : std_logic_vector(7 downto 0):= X"04";
    TYPE State_WRITE_type IS (Write_cmd_word,Write_data);
    TYPE State_MBOOT_type IS (MBOOT_IDLE, MBOOT_START, MBOOT_READ, MBOOT_WRITE,MBOOT_DESYNC,MBOOT_READ_FRAMES, MBOOT_WRITE_FRAMES);
    
    TYPE State_READ_FRAME_type IS (Go_to_FAR_REGISTER,Write_FAR_Address,Go_to_CMD_REGISTER,Write_RCFG_COMMAND,Go_to_FDRO_REGISTER,Write_word_pos,Switch_To_Read,Read_Dummy,Read_Frame,Switch_To_Write,Switch_MBOOT_state);
    TYPE State_WRITE_FRAME_type IS (Go_to_IDCODE_REGISTER,Write_IDCODE,Go_to_FAR_REGISTER,Write_FAR_Address,Go_to_CMD_REGISTER,Write_WCFG_COMMAND,Go_to_FDRI_REGISTER,Write_word_pos,Write_Frame,Write_Dummy,Switch_MBOOT_state);
    pure function rev_f(v : std_logic_vector(31 downto 0))
    return std_logic_vector ;

end package icape_common ;

package body icape_common is

    pure function rev_f(v : std_logic_vector(31 downto 0))
    return std_logic_vector is
        variable j_v : natural;
        variable res_v : std_logic_vector(v'range);
    begin
        for I in v'range loop
            j_v := (7-(I mod 8)) + (I/8)*8;
            res_v(j_v) := v(I);
        end loop;
        return res_v;
    end rev_f;

end package body icape_common ;
