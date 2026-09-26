-------------------------------------------------------------------------------
-- Measured xc7z010 column geometry (2026-08-29, SYNDROMEVALID-qualified ILA
-- capture of the init sweep; see devicefiles/Zynq7010_column_map.txt).
-- Minor counts per column, per half. Columns outside the scrubber's range
-- (top cols 0..17) read 0 and are treated as invalid.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package device_geometry_pkg is
  type col_minors_arr_t is array (0 to 55) of natural;
  -- Frame a SYNDROMEVALID pulse belongs to, from the 1-cycle-delayed FAR:
  -- normally far_d - 1; when far_d sits at a column base (minor = 0) the
  -- just-finished frame is the LAST minor of the PREVIOUS column
  -- (ILA-measured identity, exact with the measured geometry).
  function attributed_frame(far_d : std_logic_vector(25 downto 0);
                            top   : col_minors_arr_t;
                            bot   : col_minors_arr_t)
    return std_logic_vector;
  constant top_col_minors_c : col_minors_arr_t := (
    0 => 0,
    1 => 0,
    2 => 0,
    3 => 0,
    4 => 0,
    5 => 0,
    6 => 0,
    7 => 0,
    8 => 0,
    9 => 0,
    10 => 0,
    11 => 0,
    12 => 0,
    13 => 0,
    14 => 0,
    15 => 0,
    16 => 0,
    17 => 0,
    18 => 36,  -- capture began at the col-18 first pulse; true count is 36
    19 => 36,
    20 => 36,
    21 => 36,
    22 => 28,
    23 => 36,
    24 => 36,
    25 => 28,
    26 => 36,
    27 => 36,
    28 => 36,
    29 => 36,
    30 => 36,
    31 => 36,
    32 => 36,
    33 => 36,
    34 => 30,
    35 => 36,
    36 => 36,
    37 => 36,
    38 => 36,
    39 => 30,
    40 => 36,
    41 => 36,
    42 => 28,
    43 => 36,
    44 => 36,
    45 => 36,
    46 => 28,
    47 => 36,
    48 => 36,
    49 => 28,
    50 => 36,
    51 => 36,
    52 => 36,
    53 => 36,
    54 => 30,
    55 => 43
  );
  constant bot_col_minors_c : col_minors_arr_t := (
    0 => 43,
    1 => 30,
    2 => 36,
    3 => 36,
    4 => 36,
    5 => 36,
    6 => 28,
    7 => 36,
    8 => 36,
    9 => 28,
    10 => 36,
    11 => 36,
    12 => 36,
    13 => 36,
    14 => 28,
    15 => 36,
    16 => 36,
    17 => 28,
    18 => 36,
    19 => 36,
    20 => 36,
    21 => 36,
    22 => 28,
    23 => 36,
    24 => 36,
    25 => 28,
    26 => 36,
    27 => 36,
    28 => 36,
    29 => 36,
    30 => 36,
    31 => 36,
    32 => 36,
    33 => 36,
    34 => 30,
    35 => 36,
    36 => 36,
    37 => 36,
    38 => 36,
    39 => 30,
    40 => 36,
    41 => 36,
    42 => 28,
    43 => 36,
    44 => 36,
    45 => 36,
    46 => 28,
    47 => 36,
    48 => 36,
    49 => 28,
    50 => 36,
    51 => 36,
    52 => 36,
    53 => 36,
    54 => 30,
    55 => 43
  );
end package device_geometry_pkg;

package body device_geometry_pkg is
  function attributed_frame(far_d : std_logic_vector(25 downto 0);
                            top   : col_minors_arr_t;
                            bot   : col_minors_arr_t)
    return std_logic_vector is
    variable col  : integer;
    variable half : std_logic;
    variable m    : integer;
    variable r    : std_logic_vector(25 downto 0);
  begin
    if far_d(6 downto 0) /= "0000000" then
      return std_logic_vector(unsigned(far_d) - 1);
    end if;
    col  := to_integer(unsigned(far_d(16 downto 7)));
    half := far_d(22);
    if col > 0 then
      col := col - 1;
    elsif half = '1' then
      half := '0'; col := 55;
    end if;
    if half = '0' then m := top(col); else m := bot(col); end if;
    if m = 0 then m := 1; end if;
    r := (others => '0');
    r(22) := half;
    r(16 downto 7) := std_logic_vector(to_unsigned(col, 10));
    r(6 downto 0)  := std_logic_vector(to_unsigned(m - 1, 7));
    return r;
  end function;
end package body device_geometry_pkg;
