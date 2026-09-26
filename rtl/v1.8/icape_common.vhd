library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
use IEEE.NUMERIC_STD.ALL;
--use IEEE.math_real."ceil";
--use IEEE.math_real."log2";


-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

package icape_common is
    constant frame_word_count: integer :=101;
    constant word_bit_count: integer :=32;
    constant DEVICE_ID:std_logic_vector(31 downto 0):=x"13722093";

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

    constant DEVICE_COLUMNS: integer:=56;
    constant DEVICE_MINOR_ADDRESSES: integer:=42;
    constant DEVICE_TOP_BOT:integer:=1;
    constant DEVICE_ROWS:integer:=1;
    constant DEVICE_BLOCK_TYPE:integer:=4;

    --type sequence_t
    type icape_output_t is record
       CSIB : std_logic;
       RDWRB : std_logic;
       WORD : std_logic_vector(word_bit_count-1 downto 0);
    end record;




    type frame_t is array (0 to frame_word_count - 1) of std_logic_vector(word_bit_count-1 downto 0);

    TYPE State_WRITE_type IS (Write_cmd_word,Write_data);

    constant IDLE_STATE_output :std_logic_vector(word_bit_count+1 downto 0) :='0'&'0'&DUMMY_WORD;

    constant IDLE_SYNCED_STATE_output :icape_output_t :=('1','0',DUMMY_WORD);

    TYPE State_SYNC_type IS (WRITE_DUMMY_WORD_0,WRITE_DUMMY_WORD_1,WRITE_DUMMY_WORD_2,WRITE_SYNC_WORD,WRITE_NOOP_WORD,FINISH_SEQ);

    type sequence_node_t is record
        CSIB : std_logic;
       RDWRB : std_logic;
       WORD : std_logic_vector(word_bit_count-1 downto 0);
        next_state : integer;
    end record;

    type sequence_SYNC_node_t is record
        icape_output : icape_output_t;
        next_state : integer;
    end record;

    type sequence_SYNC_type is array(integer) of std_logic_vector(word_bit_count+1 downto 0);

    TYPE State_READ_FRAME_type IS (Go_to_FAR_REGISTER,Write_FAR_Address,Go_to_CMD_REGISTER,Write_RCFG_COMMAND,Go_to_FDRO_REGISTER,Write_word_pos,Switch_To_Read,Read_Dummy,Read_Frame,Switch_To_Write,Abort,Switch_MBOOT_state,FINISH_SEQ);

    type sequence_READ_FRAME_node_t is record
        icape_output : icape_output_t;
        next_state : integer;
    end record;

    type sequence_READ_FRAME_type is array(0 to 10) of sequence_READ_FRAME_node_t;



    TYPE State_WRITE_FRAME_type IS (Go_to_IDCODE_REGISTER,Write_IDCODE,Go_to_FAR_REGISTER,Write_FAR_Address,Go_to_CMD_REGISTER,Write_WCFG_COMMAND,Go_to_FDRI_REGISTER,Write_word_pos,Write_Frame,Write_Dummy,Switch_MBOOT_state,Abort,FINISH_SEQ);

    type sequence_WRITE_FRAME_node_t is record
        icape_output : icape_output_t;
        next_state : State_WRITE_FRAME_type;
    end record;

    type sequence_WRITE_FRAME_type is array(State_WRITE_FRAME_type) of sequence_WRITE_FRAME_node_t;


    TYPE State_DESYNC_type IS (Go_to_CMD_REGISTER,Write_DESYNC_COMMAND,Write_NOOP_WORD_0,Write_NOOP_WORD_1,Write_NOOP_WORD_2,FINISH_SEQ);

    type sequence_DESYNC_node_t is record
        icape_output : icape_output_t;
        next_state : State_DESYNC_type;
    end record;

    type sequence_DESYNC_type is array(State_DESYNC_type) of sequence_DESYNC_node_t;


    TYPE State_Switch_To_Write_type IS (PAUSE_ICAPE,SWITCH_RDWRB,RESUME_ICAPE,FINISH_SEQ);

    type sequence_Switch_To_Write_node_t is record
        icape_output : icape_output_t;
        next_state : State_Switch_To_Write_type;
    end record;

    type sequence_Switch_To_Write_type is array(State_Switch_To_Write_type) of sequence_Switch_To_Write_node_t;


    TYPE State_Switch_To_Read_type IS (PAUSE_ICAPE,SWITCH_RDWRB,RESUME_ICAPE,FINISH_SEQ);

    type sequence_Switch_To_Read_node_t is record
        icape_output : icape_output_t;
        next_state : integer;
    end record;

    type sequence_Switch_To_Read_type is array(integer) of sequence_Switch_To_Read_node_t;

--    constant Switch_To_Read_SEQUENCE :sequence_SYNC_type(integer):=(
--    1=>(('1','0',NOOP_WORD),2),
--    2=>(('1','1',NOOP_WORD),3),
--    3=>(('0','1',NOOP_WORD),4),
--    4=>(('0','0',NOOP_WORD),4)
--    );

    TYPE State_MBOOT_type IS (MBOOT_IDLE, MBOOT_SYNC,MBOOT_IDLE_SYNCED, MBOOT_READ, MBOOT_WRITE,MBOOT_DESYNC,MBOOT_READ_FRAMES, MBOOT_WRITE_FRAMES);

    type MBOOT_node_t is record
        icape_output :icape_output_t;
        next_MBOOT_state : State_MBOOT_type;
    end record;


    pure function rev_f(v : std_logic_vector(31 downto 0))
    return std_logic_vector ;
    pure function get_word_pos(syndrome_word : std_logic_vector(7 downto 0))
    return std_logic_vector ;

    pure function get_group(address : std_logic_vector(31 downto 0))
    return integer ;
    pure function get_start_far(v : std_logic_vector(31 downto 0))
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


    pure function get_word_pos(syndrome_word : std_logic_vector(7 downto 0))
    return std_logic_vector is
        variable word_pos : std_logic_vector(syndrome_word'range);
    begin
        if syndrome_word < X"A0" then
        word_pos:=std_logic_vector(unsigned(syndrome_word(7 downto 0)) - X"99");
        elsif syndrome_word < X"C0" then
        word_pos:=std_logic_vector(unsigned(syndrome_word(7 downto 0)) - X"9A");
        elsif syndrome_word <= X"FF" then
        word_pos:=std_logic_vector(unsigned(syndrome_word(7 downto 0)) - X"9B");
        end if;
        return word_pos;
    end get_word_pos;

    pure function get_group(address : std_logic_vector(31 downto 0))
    return integer is
        variable block_type: std_logic_vector(2 downto 0);
        variable Top_bot:integer;
        variable Row_address: integer;
        variable column_address:integer;
        --variable minor_address:integer;
        variable group_index:integer;
    begin
        block_type:=address(25 downto 23);
        top_bot:=to_integer(unsigned'('0' & address(22)));
        row_address:= to_integer(unsigned(address(21 downto 17)));
        column_address:=to_integer(unsigned(address(16 downto 7)));
        --minor_address:=to_integer(unsigned(address(6 downto 0)));
        if block_type="000" then
          group_index:=column_address+(Row_address+Top_bot)*DEVICE_COLUMNS;
        elsif block_type="010" then
          group_index:=2*DEVICE_COLUMNS+Top_bot;
        elsif block_type="011" then
          group_index:=2*DEVICE_COLUMNS+2+Top_bot;
        end if;
        return group_index;
    end get_group;
    pure function get_start_far(v : std_logic_vector(31 downto 0))
    return std_logic_vector is
        variable sv : std_logic_vector(v'range):=(others=>'0');
    begin
        sv(31 downto 7):=v(31 downto 7);
        return sv;
    end get_start_far;
end package body icape_common ;
