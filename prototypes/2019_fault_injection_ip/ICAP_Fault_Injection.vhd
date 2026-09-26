library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library UNISIM;
use UNISIM.VComponents.all;

library work;
use work.icape_common.ALL;
use work.icape_com_producers.ALL;

entity ICAP_Fault_Injection is
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
end ICAP_Fault_Injection;

architecture Behavioral of ICAP_Fault_Injection is

component dual_port_mem
  generic
    (
    addr_width     : integer := mem_addr_width;
    data_width     : integer := mem_data_width
    );
  port
    (
    clk            : in  std_logic;
    wr_en          : in  std_logic;
    wr_addr        : in  std_logic_vector(addr_width-1 downto 0);
    data_in        : in  std_logic_vector(data_width-1 downto 0);
    rd_en          : in  std_logic;
    rd_addr        : in  std_logic_vector(addr_width-1 downto 0);
    data_out       : out std_logic_vector(data_width-1 downto 0)
    );
end component;

 signal O,Output_r,Output,I,Word:std_logic_vector(31 downto 0);
 signal write_register_o :std_logic_vector(34 downto 0);
 Signal CSIB,RDWRB:std_logic;

 signal State_MBOOT : State_MBOOT_type:=MBOOT_IDLE;
 signal State_Read_Frame : State_READ_FRAME_type:=Go_to_FAR_REGISTER;
 signal State_Write_Frame : State_WRITE_FRAME_type:=Go_to_IDCODE_REGISTER;
 signal State: integer := 0;
 signal Out_ready,readback_on,write_mem,read_mem: std_logic := '0';

 signal mem_in,mem_out :std_logic_vector(mem_data_width-1 downto 0):=X"DEADBEEF";
 signal mem_address_read,mem_address_write : std_logic_vector(mem_addr_width-1 downto 0);

 signal data_in:std_logic_vector(31 downto 0):=X"DEADBEEF";
begin

    -- ICAPE2: Internal Configuration Access Port
-- 7 Series
-- Xilinx HDL Language Template, version 2019.2
ICAPE2_inst : ICAPE2
generic map (
 DEVICE_ID => X"13722093", -- Specifies the pre-programmed Device ID value to be used for simulation
 -- purposes.
 ICAP_WIDTH => "X32", -- Specifies the Word and output data width.
 SIM_CFG_FILE_NAME => "NONE" -- Specifies the Raw Bitstream (RBT) file to be parsed by the simulation
 -- model.
)
port map (
 O => O, -- 32-bit output: Configuration data output bus
 CLK => CLK, -- 1-bit Word: Clock Word
 CSIB => CSIB, -- 1-bit Word: Active-Low ICAP Enable
 I => I, -- 32-bit Word: Configuration data Word bus
 RDWRB => RDWRB -- 1-bit Word: Read/Write Select Word
);
-- End of ICAPE2_inst instantiation

process(CLK,Output,Word)
variable write_register_done :std_logic;
begin
    if rising_edge(CLK) then

        case State_MBOOT is
            when MBOOT_IDLE =>
                CSIB<='1';
                RDWRB<='1';
                Word<=DUMMY_WORD;
                State<=0;
                Out_ready<='0';
                if start ='1' and Output_r(3 downto 0)="1001" then
                    Busy<='1';
                    State_MBOOT <=MBOOT_START;
                end if;
            when MBOOT_START =>

                Case State is
                    when 0 =>
                        CSIB<='1';
                        RDWRB<='1';
                        Word<=DUMMY_WORD;
                        State<=1;
                    when 1 =>
                        CSIB<='1';
                        RDWRB<='0';
                        Word<=DUMMY_WORD;
                        State<=2;
                    when 2 =>
                        CSIB<='0';
                        RDWRB<='0';
                        Word<=DUMMY_WORD;
                        State<=3;
                    when 3 =>
                        CSIB<='0';
                        RDWRB<='0';
                        Word<=SYNC_WORD;
                        State<=4;
                    when 4 =>
                        CSIB<='0';
                        RDWRB<='0';
                        Word<=NOOP_WORD;
                        State<=0;
                        if Output_r(3 downto 0)="1011" then--No abort ,no readback ,sync word received , no configuration error
                            synced<='0';
                            State_MBOOT<=MBOOT_READ_FRAMES;
                        end if;
                    when others =>
                        State<=0;
                        State_MBOOT<=MBOOT_IDLE;
                end case;
            when MBOOT_READ_FRAMES =>
                case State_READ_FRAME is
                    when Go_to_FAR_REGISTER =>
                        CSIB<='0';
                        RDWRB<='0';
                        Word<=WRITE_REGISTER_WORD & FAR_REGISTER & WRITE_REGISTER_MODE_1;
                        State_READ_FRAME<=Write_FAR_Address;
                    when Write_FAR_Address=>
                        CSIB<='0';
                        RDWRB<='0';
                        Word<=x"00"&Far_address;--far address ,usefull A84
                        State_READ_FRAME<=Go_to_CMD_REGISTER;
                    when Go_to_CMD_REGISTER=>
                        CSIB<='0';
                        RDWRB<='0';
                        Word<=WRITE_REGISTER_WORD & CMD_REGISTER & WRITE_REGISTER_MODE_1;
                        State_READ_FRAME<=Write_RCFG_COMMAND;
                    when Write_RCFG_COMMAND=>
                        CSIB<='0';
                        RDWRB<='0';
                        Word<=RCFG_COMMAND;
                        State_READ_FRAME<=Go_to_FDRO_REGISTER;
                    when Go_to_FDRO_REGISTER=>
                        CSIB<='0';
                        RDWRB<='0';
                        Word<=READ_REGISTER_WORD& FDRO_REGISTER & x"000";
                        State_READ_FRAME<=Write_word_pos;
                    when Write_word_pos=>
                        CSIB<='0';
                        RDWRB<='0';
                        Word<=x"48"& x"0000" & Word_pos;
                        State_READ_FRAME<=Switch_To_Read;
                    when Switch_To_Read =>
                    case State is
                        when 0=>-- Set idle
                            CSIB<='1';
                            RDWRB<='0';
                            Word<=NOOP_WORD;
                            State<=1;
                        when 1=>
                            CSIB<='1';
                            RDWRB<='1';
                            Word<=NOOP_WORD;
                            State<=2;
                        when 2=>
                            CSIB<='0';
                            RDWRB<='1';
                            Word<=NOOP_WORD;
                            State<=3;
                        when 3=>
                            CSIB<='0';
                            RDWRB<='1';
                            Word<=NOOP_WORD;
                            State<=4;
                        when 4=>
                             CSIB<='0';
                             RDWRB<='1';
                             Word<=NOOP_WORD;
                             State<=5;
                        when 5=>
                             CSIB<='0';
                             RDWRB<='1';
                             Word<=NOOP_WORD;
                             State<=0;
                             State_READ_FRAME<=Read_Dummy;
                        when others =>
                            State_MBOOT<=MBOOT_DESYNC;
                            State<=0;
                            CSIB<='1';
                            RDWRB<='1';
                            Word<=NOOP_WORD;
                        end case;
                    when Read_Dummy=>
                        if State<100 then--DUMMY FRAME
                            CSIB<='0';
                            RDWRB<='1';
                            State<=State+1;
                        else
                            CSIB<='0';
                            RDWRB<='1';
                            State<=0;
                            State_READ_FRAME<=Read_Frame;
                        end if;
                    when Read_Frame=>
                        if State<to_integer(unsigned(Word_pos)) then--DESIRED FRAME
                            CSIB<='0';
                            RDWRB<='1';
                            State<=State+1;
                        else
                            CSIB<='0';
                            RDWRB<='1';
                            State<=0;
                            State_READ_FRAME<=Switch_To_Write;
                        end if;
                    when Switch_To_Write =>
                        case State is
                            when 0=>
                                CSIB<='1';
                                RDWRB<='1';
                                Word<=NOOP_WORD;
                                State<=1;
                            when 1=>
                                CSIB<='1';
                                RDWRB<='0';
                                Word<=NOOP_WORD;
                                State<=2;
                            when 2=>
                                CSIB<='0';
                                RDWRB<='0';
                                Word<=NOOP_WORD;
                                State_MBOOT<=MBOOT_WRITE_FRAMES;
                                State_READ_FRAME<=Go_to_FAR_REGISTER;
                                State<=0;
                            when others =>
                                State_MBOOT<=MBOOT_DESYNC;
                                State<=0;
                                CSIB<='1';
                                RDWRB<='0';
                                Word<=NOOP_WORD;
                                State_READ_FRAME<=Go_to_FAR_REGISTER;
                            end case;
                    when others =>
                        State_READ_FRAME<=Go_to_FAR_REGISTER;
                        State_MBOOT<=MBOOT_DESYNC;
                        State<=0;
                        CSIB<='1';
                        RDWRB<='0';
                        Word<=NOOP_WORD;
                end case;

                when MBOOT_WRITE_FRAMES =>
                case State_Write_Frame is
                    when Go_to_IDCODE_REGISTER=>
                        CSIB<='0';
                        RDWRB<='0';
                        Word<=WRITE_REGISTER_WORD & IDCODE_REGISTER & WRITE_REGISTER_MODE_1;
                        State_Write_Frame<=Write_IDCODE;
                    when Write_IDCODE=>
                        CSIB<='0';
                        RDWRB<='0';
                        Word<=x"13722093";
                        State_Write_Frame<=Go_to_FAR_REGISTER;
                    when Go_to_FAR_REGISTER=>
                        CSIB<='0';
                        RDWRB<='0';
                        Word<=WRITE_REGISTER_WORD & FAR_REGISTER & WRITE_REGISTER_MODE_1;
                        State_Write_Frame<=Write_FAR_Address;
                    when Write_FAR_Address=>
                        CSIB<='0';
                        RDWRB<='0';
                        Word<=x"00"&Far_address;--far address ,usefull A84
                        State_Write_Frame<=Go_to_CMD_REGISTER;
                    when Go_to_CMD_REGISTER=>
                        CSIB<='0';
                        RDWRB<='0';
                        Word<=WRITE_REGISTER_WORD & CMD_REGISTER & WRITE_REGISTER_MODE_1;
                        State_Write_Frame<=Write_WCFG_COMMAND;
                    when Write_WCFG_COMMAND=>
                        CSIB<='0';
                        RDWRB<='0';
                        Word<=WCFG_COMMAND;
                        State_Write_Frame<=Go_to_FDRI_REGISTER;
                    when Go_to_FDRI_REGISTER=>
                        CSIB<='0';
                        RDWRB<='0';
                        Word<=WRITE_REGISTER_WORD& FDRI_REGISTER & x"000";
                        read_mem<='1';
                        State_Write_Frame<=Write_word_pos;
                    when Write_word_pos=>

                        CSIB<='0';
                        RDWRB<='0';
                        read_mem<='1';
                        Word<=x"48"& x"0000" & Word_pos;
                        State_Write_Frame<=Write_Frame;
                    when Write_Frame=>--WRITE FRAME
                        if State<to_integer(unsigned(Word_pos)) then
                            CSIB<='0';
                            RDWRB<='0';
                            read_mem<='1';
                            Word<=mem_out;
                            State<=State+1;
                        else
                            Word<=mem_out xor Fault_Word;
                            State<=0;
                            State_Write_Frame<=Write_Dummy;
                        end if;
                    when Write_Dummy=>--WRITE DUMMY FRAME
                        if State <100 then
                            CSIB<='0';
                            RDWRB<='0';
                            Word<=DUMMY_WORD;
                            State<=State+1;
                        else
                            CSIB<='0';
                            RDWRB<='0';
                            Word<=DUMMY_WORD;
                            State<=State+1;
                            State<=0;
                            State_Write_Frame<=Switch_MBOOT_state;
                        end if;
                    when Switch_MBOOT_state=>
                        CSIB<='0';
                        RDWRB<='0';
                        Word<=NOOP_WORD;
                        State_Write_Frame<=Go_to_IDCODE_REGISTER;
                        State_MBOOT<=MBOOT_DESYNC;
                        State<=0;
                    when others =>
                        State<=0;
                        CSIB<='1';
                        RDWRB<='1';
                        Word<=NOOP_WORD;
                        State_MBOOT<=MBOOT_DESYNC;
                end case;
            when  MBOOT_DESYNC =>
                case state is
                    when 0 =>
                        CSIB<='0';
                        RDWRB<='0';
                        Word<=WRITE_REGISTER_WORD & CMD_REGISTER & WRITE_REGISTER_MODE_1;
                        State<=1;
                    when 1 =>
                        CSIB<='0';
                        RDWRB<='0';
                        Word<=DESYNC_COMMAND;
                        State<=2;
                    when 2 =>
                        CSIB<='0';
                        RDWRB<='0';
                        Word<=NOOP_WORD;
                        State<=3;
                   when 3 =>
                        CSIB<='0';
                        RDWRB<='0';
                        Word<=NOOP_WORD;
                        State<=4;
                   when 4 =>
                         CSIB<='0';
                         RDWRB<='0';
                         Word<=NOOP_WORD;
                         State<=5;
                   when 5 =>
                        CSIB<='1';
                        RDWRB<='1';
                        Word<=NOOP_WORD;
                        State<=6;
                   when 6 =>
                        CSIB<='1';
                        RDWRB<='1';
                        Word<=DUMMY_WORD;
                        State<=0;
                        State_MBOOT<=MBOOT_IDLE;
                        Busy<='0';
                        synced<='1';
                    when others =>
                        State<=0;
                        State_MBOOT<=MBOOT_IDLE;
                end case;
            when others=>
                CSIB<='1';
                RDWRB<='1';
                Word<=DUMMY_WORD;
                State<=0;
                State_MBOOT<=MBOOT_IDLE;
                Busy<='0';
        end case;
    end if;
end process;

mem_in<= Output_r;
write_mem<= '1' when State_READ_FRAME = Read_Frame else '0';
mem_address_write<=std_logic_vector(to_unsigned(State-114, mem_address_write'length));
mem_address_read<=std_logic_vector(to_unsigned(State-7, mem_address_write'length));
dual_port_mem_inst : dual_port_mem
  generic map
  (
  addr_width     => mem_addr_width,
  data_width     => mem_data_width
  )
port map
  (
  clk         =>clk,
  wr_en       =>write_mem,
  wr_addr     =>mem_address_write,
  data_in     =>mem_in,
  rd_en       =>read_mem,
  rd_addr     =>mem_address_read,
  data_out    =>mem_out
  );

Output_r<=rev_f(O);
I<=rev_f(Word);

end Behavioral;
