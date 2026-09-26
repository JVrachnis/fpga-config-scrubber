----------------------------------------------------------------------------------
-- Company:
-- Engineer:
--
-- Create Date: 11/06/2019 12:19:42 PM
-- Design Name:
-- Module Name: ICAP_COM - Behavioral
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
use IEEE.NUMERIC_STD.ALL;

library UNISIM;
use UNISIM.VComponents.all;

library work;
use work.icape_common.ALL;
use work.icape_com_producers.ALL;

entity ICAP_COM is
    generic(
        mem_addr_width     : integer := 7;
        mem_data_width     : integer := 32
    );
  Port (CLK :in std_logic;
        readback_en:in std_logic;
        r_we:in std_logic;
        Start:in std_logic;
        Busy:out std_logic;
        Not_synced,synced:out std_logic;
        in_readback:out std_logic
        );
end ICAP_COM;

architecture Behavioral of ICAP_COM is

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
 Signal CSIB,RDWRB,CRCERROR,ECCERROR,ECCERRORSINGLE,SYNDROMEVALID:std_logic;
 signal FAR :std_logic_vector(25 downto 0);
 signal SYNBIT :std_logic_vector(4 downto 0);
 signal SYNDROME :std_logic_vector(12 downto 0);
 signal SYNWORD :std_logic_vector(6 downto 0);
 
 signal State_MBOOT : State_MBOOT_type:=MBOOT_IDLE;
 signal State: integer := 0;
 signal Out_ready,readback_on,write_mem,read_mem: std_logic := '0';

 signal mem_in,mem_out :std_logic_vector(mem_data_width-1 downto 0):=X"DEADBEEF";
 signal mem_address_read,mem_address_write : std_logic_vector(mem_addr_width-1 downto 0);

 signal address: std_logic_vector(7 downto 0):=IDCODE_REGISTER;
 signal data_in:std_logic_vector(31 downto 0):=X"DEADBEEF";
 attribute mark_debug :string;
 attribute mark_debug of ECCERROR,CRCERROR:signal is "true";
begin

FRAME_ECCE2_inst : FRAME_ECCE2
generic map (
 FARSRC => "EFAR", -- Determines if the output of FAR[25:0] configuration register points
 -- to the FAR or EFAR. Sets configuration option register bit CTL0[7].
 FRAME_RBT_IN_FILENAME => "NONE" -- This file is output by the ICAP_E2 model and it contains Frame Data
 -- information for the Raw Bitstream (RBT) file. The FRAME_ECCE2 model
 -- will parse this file, calculate ECC and output any error conditions.
)
port map (
 CRCERROR => CRCERROR, -- 1-bit output: Output indicating a CRC error.
 ECCERROR => ECCERROR, -- 1-bit output: Output indicating an ECC error.
 ECCERRORSINGLE => ECCERRORSINGLE, -- 1-bit output: Output Indicating single-bit Frame ECC error detected.
 FAR => FAR, -- 26-bit output: Frame Address Register Value output.
 SYNBIT => SYNBIT, -- 5-bit output: Output bit address of error.
 SYNDROME => SYNDROME, -- 13-bit output: Output location of erroneous bit.
 SYNDROMEVALID => SYNDROMEVALID, -- 1-bit output: Frame ECC output indicating the SYNDROME output is
 -- valid.
 SYNWORD => SYNWORD -- 7-bit output: Word output in the frame where an ECC error has been
 -- detected.
);

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
                            if readback_en='1'then
                              Out_ready<='0';
                              State_MBOOT<=MBOOT_READ_FRAMES;
                            elsif r_we='1' then
                                State_MBOOT<=MBOOT_WRITE;
                            else
                                Out_ready<='0';
                                State_MBOOT<=MBOOT_READ;
                            end if;
                        end if;
                    when others =>
                        State<=0;
                        State_MBOOT<=MBOOT_IDLE;
                end case;
            when MBOOT_READ =>
                case State is
                    when 0=>
                        CSIB<='0';
                        RDWRB<='0';
                        Word<=READ_REGISTER_WORD&Address&READ_REGISTER_MODE_1;
                        State<=1;
                    when 1=>
                        CSIB<='0';
                        RDWRB<='0';
                        Word<=NOOP_WORD;
                        State<=2;
                    when 2=>
                        CSIB<='0';
                        RDWRB<='0';
                        Word<=NOOP_WORD;
                        State<=3;
                    when 3=>-- Set idle
                        CSIB<='1';
                        RDWRB<='0';
                        Word<=NOOP_WORD;
                        State<=4;
                    when 4=>
                        CSIB<='1';
                        RDWRB<='1';
                        Word<=NOOP_WORD;
                        State<=5;
                    when 5=>
                        CSIB<='0';
                        RDWRB<='1';
                        Word<=NOOP_WORD;
                        State<=6;
                    when 6=>
                        CSIB<='0';
                        RDWRB<='1';
                        Word<=NOOP_WORD;
                        State<=7;
                    when 7=>
                        CSIB<='0';
                        RDWRB<='1';
                        Word<=NOOP_WORD;
                        State<=8;
                    when 8=>
                        CSIB<='0';
                        RDWRB<='1';
                        Word<=NOOP_WORD;
                        State<=9;
                    when 9=>--Output Ready
                        Out_ready<='1';
                        CSIB<='0';
                        RDWRB<='1';
                        Word<=NOOP_WORD;
                        State<=10;
                    when 10=>
                        Out_ready<='0';
                        CSIB<='1';
                        RDWRB<='1';
                        Word<=NOOP_WORD;
                        State<=11;
                    when 11=>
                        CSIB<='1';
                        RDWRB<='0';
                        Word<=NOOP_WORD;
                        State<=12;
                    when 12=>
                        CSIB<='0';
                        RDWRB<='0';
                        Word<=NOOP_WORD;
                        State_MBOOT<=MBOOT_DESYNC;
                        State<=0;
                    when others =>
                        State<=0;
                        CSIB<='1';
                        RDWRB<='1';
                        Word<=NOOP_WORD;
                end case;
            when MBOOT_READ_FRAMES =>
                    case State is
                        when 0=>
                            CSIB<='0';
                            RDWRB<='0';
                            Word<=WRITE_REGISTER_WORD & FAR_REGISTER & WRITE_REGISTER_MODE_1;
                            State<=1;
                        when 1=>
                            CSIB<='0';
                            RDWRB<='0';
                            Word<=x"00000A85";--far address ,usefull A84
                            State<=2;
                        when 2=>
                            CSIB<='0';
                            RDWRB<='0';
                            Word<=WRITE_REGISTER_WORD & CMD_REGISTER & WRITE_REGISTER_MODE_1;
                            State<=3;
                        when 3=>
                            CSIB<='0';
                            RDWRB<='0';
                            Word<=RCFG_COMMAND;
                            State<=4;
                        when 4=>
                            CSIB<='0';
                            RDWRB<='0';
                            Word<=READ_REGISTER_WORD& FDRO_REGISTER & x"000";
                            State<=5;
                        when 5=>
                            CSIB<='0';
                            RDWRB<='0';
                            Word<=x"48"& x"0000CA";
                            State<=6;
                        when 6=>-- Set idle
                            CSIB<='1';
                            RDWRB<='0';
                            Word<=NOOP_WORD;
                            State<=7;
                        when 7=>
                            CSIB<='1';
                            RDWRB<='1';
                            Word<=NOOP_WORD;
                            State<=8;
                        when 8=>
                            CSIB<='0';
                            RDWRB<='1';
                            Word<=NOOP_WORD;
                            State<=9;
                        when 9=>
                            CSIB<='0';
                            RDWRB<='1';
                            Word<=NOOP_WORD;
                            State<=10;
                        when 10=>
                             CSIB<='0';
                             RDWRB<='1';
                             Word<=NOOP_WORD;
                             State<=11;
                        when 11=>
                             CSIB<='0';
                             RDWRB<='1';
                             Word<=NOOP_WORD;
                             State<=12;
                        when 12 to 112=>--DUMMY FRAME
                            CSIB<='0';
                            RDWRB<='1';
                            State<=State+1;
                        when 113 to 213=>--DESIRED FRAME
                            Out_ready<='1';
                            CSIB<='0';
                            RDWRB<='1';
                            Word<=NOOP_WORD;
                            State<=State+1;
                        when 214=>
                            Out_ready<='0';
                            CSIB<='1';
                            RDWRB<='1';
                            Word<=NOOP_WORD;
                            State<=215;
                        when 215=>
                            CSIB<='1';
                            RDWRB<='0';
                            Word<=NOOP_WORD;
                            State<=216;
                        when 216=>
                            CSIB<='0';
                            RDWRB<='0';
                            Word<=NOOP_WORD;
                            if r_we='1' then
                              State_MBOOT<=MBOOT_WRITE_FRAMES;
                            else
                              State_MBOOT<=MBOOT_DESYNC;
                            end if;
                            State<=0;
                        when others =>
                            State<=0;
                            CSIB<='1';
                            RDWRB<='1';
                            Word<=NOOP_WORD;
                    end case;
            when MBOOT_WRITE =>
                case state is
                    when 0=>
                        CSIB<='0';
                        RDWRB<='0';
                        Word<=WRITE_REGISTER_WORD & address & WRITE_REGISTER_MODE_1;
                        State<=1;
                    when 1=>
                        CSIB<='0';
                        RDWRB<='0';
                        Word<=data_in;
                        State<=0;
                        State_MBOOT<=MBOOT_DESYNC;
                    when others =>
                        State<=0;
                        State_MBOOT<=MBOOT_IDLE;
                end case;
                when MBOOT_WRITE_FRAMES =>
                case State is
                    when 0=>
                        CSIB<='0';
                        RDWRB<='0';
                        Word<=WRITE_REGISTER_WORD & IDCODE_REGISTER & WRITE_REGISTER_MODE_1;
                        State<=1;
                    when 1=>
                        CSIB<='0';
                        RDWRB<='0';
                        Word<=x"13722093";
                        State<=2;
                    when 2=>
                        CSIB<='0';
                        RDWRB<='0';
                        Word<=WRITE_REGISTER_WORD & FAR_REGISTER & WRITE_REGISTER_MODE_1;
                        State<=3;
                    when 3=>
                        CSIB<='0';
                        RDWRB<='0';
                        Word<=x"00000A85";--far address ,usefull A84
                        State<=4;
                    when 4=>
                        CSIB<='0';
                        RDWRB<='0';
                        Word<=WRITE_REGISTER_WORD & CMD_REGISTER & WRITE_REGISTER_MODE_1;
                        State<=5;
                    when 5=>
                        CSIB<='0';
                        RDWRB<='0';
                        Word<=WCFG_COMMAND;
                        State<=6;
                    when 6=>
                        CSIB<='0';
                        RDWRB<='0';
                        Word<=WRITE_REGISTER_WORD& FDRI_REGISTER & x"000";
                        read_mem<='1';
                        State<=7;
                    when 7=>
                        CSIB<='0';
                        RDWRB<='0';
                        read_mem<='1';
                        Word<=x"48"& x"0000CA";
                        State<=8;
                    when 8 to 108=>--WRITE FRAME
                        CSIB<='0';
                        RDWRB<='0';
                        read_mem<='1';
                        
                        if State=9 then
                            Word<=mem_out xor x"00000001";
                        else
                            Word<=mem_out;
                        end if;
                        State<=State+1;
                    when 109 to 209=>--WRITE DUMMY FRAME
                        read_mem<='0';
                        CSIB<='0';
                        RDWRB<='0';
                        Word<=DUMMY_WORD;
                        State<=State+1;
                    when 210=>
                        CSIB<='0';
                        RDWRB<='0';
                        Word<=NOOP_WORD;
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
process(CLK)
begin
    if rising_edge(CLK) then
        if Out_ready='1' then
            Output<=Output_r;
            if r_we='1' and readback_en='1' then

            end if;
        else
            Output<=x"00000000";
        end if;


    end if;
end process;
mem_in<= Output_r;
write_mem<=Out_ready and readback_en and r_we;
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

not_synced<=not Output_r(1) when RDWRB='0' else '0';
synced<=Output_r(1) when RDWRB='0' else '0';
in_readback<=Output_r(2) when RDWRB='0' else '0';
readback_on<=Output_r(2);
Output_r<=rev_f(O);
I<=rev_f(Word);

end Behavioral;
