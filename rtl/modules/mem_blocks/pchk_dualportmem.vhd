---------------------------------- VHDL Code ----------------------------------
-- File         = pchk_dualportmem.vhd
--
-- Purpose      = Dual Port Memory with per-byte parity protection (detect-only).
--                Drop-in replacement for dualportmem in the golden parity
--                store: each 32-bit word is stored as 36 bits (32 data +
--                4 per-byte even parity), which is exactly the native RAMB18
--                512x36 aspect -- zero BRAM growth. On read, parity is
--                re-checked and a `perr` flag is output aligned with data_out.
--
--                Policy rationale (2026 hardening, see HARDENING_RESEARCH.md):
--                the golden parity memory is the one store that configuration
--                scrubbing cannot protect, and a corrupted golden word causes
--                *wrong corrections*. Detection is sufficient because golden
--                parity is always regenerable from the (scrubbed, clean)
--                configuration frames: on perr the parity calculator drops
--                `initialized`, which re-runs the full golden init sweep
--                (<15 ms measured on xc7z010).
--
--                The memory array type lives in pchk_mem_pkg so the closed-
--                loop testbench can corrupt stored words through VHDL-2008
--                external names (the only way to create a true storage upset
--                in simulation).
--
-- Library      = work
-- Author       = J. Vrachnis (2026 hardening branch)
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

package pchk_mem_pkg is
  -- sized for the golden parity store: 101 words x 5 frames -> 512 deep,
  -- 32 data + 4 parity bits wide.
  constant pchk_data_width_c  : integer := 32;
  constant pchk_bytes_c       : integer := pchk_data_width_c/8;
  constant pchk_store_width_c : integer := pchk_data_width_c + pchk_bytes_c;
  constant pchk_depth_c       : integer := 512;
  type pchk_mem_array_t is array (0 to pchk_depth_c-1)
    of std_logic_vector(pchk_store_width_c-1 downto 0);

  function byte_parity(d : std_logic_vector(pchk_data_width_c-1 downto 0))
    return std_logic_vector;
end package pchk_mem_pkg;

package body pchk_mem_pkg is
  function byte_parity(d : std_logic_vector(pchk_data_width_c-1 downto 0))
    return std_logic_vector is
    variable p : std_logic_vector(pchk_bytes_c-1 downto 0);
    variable x : std_logic;
  begin
    for b in 0 to pchk_bytes_c-1 loop
      x := '0';
      for i in 0 to 7 loop
        x := x xor d(b*8+i);
      end loop;
      p(b) := x;
    end loop;
    return p;
  end function;
end package body pchk_mem_pkg;

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use work.pchk_mem_pkg.all;

entity pchk_dualportmem is
   generic
     (
     addr_width  : integer := 9;   -- must satisfy 2**addr_width <= pchk_depth_c
     data_width  : integer := 32;  -- must equal pchk_data_width_c
     check_en    : boolean := true -- 2026-09-03: false = store parity but never flag (hardness A/B)
     );
   port
     (
     clk         : in  std_logic;
     wr_en       : in  std_logic;
     wr_addr     : in  std_logic_vector(addr_width - 1 downto 0);
     data_in     : in  std_logic_vector(data_width - 1 downto 0);
     rd_en       : in  std_logic;
     rd_addr     : in  std_logic_vector(addr_width - 1 downto 0);
     data_out    : out std_logic_vector(data_width - 1 downto 0) := (others => '0');
     perr        : out std_logic := '0';  -- parity error, aligned with data_out
     -- simulation-only fault hook (defaults keep it inert; synthesis trims
     -- the constant-'0' branch). Driven from the closed-loop TB to create a
     -- true storage upset.
     sim_corrupt_pulse : in std_logic := '0';
     sim_corrupt_addr  : in integer   := 0;
     sim_corrupt_mask  : in std_logic_vector(pchk_store_width_c-1 downto 0) := (others => '0')
     );
end pchk_dualportmem;

architecture rtl of pchk_dualportmem is

signal mem_array : pchk_mem_array_t := (others => (others => '0'));
signal rd_word   : std_logic_vector(pchk_store_width_c-1 downto 0) := (others => '0');


begin

memory_write_process:
  process(clk)
    -- synthesis translate_off
    variable corrupt_d : std_logic := '0';
    -- synthesis translate_on
    begin
      if clk'event and clk = '1' then
        if wr_en = '1' then
          mem_array(conv_integer(wr_addr)) <= byte_parity(data_in) & data_in;
        end if;
        -- sim-only fault hook (rising-edge triggered). MUST stay inside
        -- translate_off: the read-modify-write of mem_array would otherwise
        -- defeat BRAM inference and flatten the store into flip-flops.
        -- synthesis translate_off
        if sim_corrupt_pulse = '1' and corrupt_d = '0' then
          mem_array(sim_corrupt_addr) <= mem_array(sim_corrupt_addr) xor sim_corrupt_mask;
        end if;
        corrupt_d := sim_corrupt_pulse;
        -- synthesis translate_on
      end if;
    end process memory_write_process;

memory_read_process:
  process(clk)
    begin
      if clk'event and clk = '1' then
        if rd_en = '1' then
          rd_word <= mem_array(conv_integer(rd_addr));
        end if;
      end if;
    end process memory_read_process;

-- combinational check after the read register: data_out/perr keep the
-- original dualportmem 1-cycle read latency.
data_out <= rd_word(data_width-1 downto 0);
perr     <= '0' when (not check_en) or
                     rd_word(pchk_store_width_c-1 downto data_width)
                     = byte_parity(rd_word(data_width-1 downto 0))
            else '1';

end rtl;
