library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_arith.all;
use work.log2_pkg.all;

entity injsim_tb is end injsim_tb;

architecture tb of injsim_tb is
  constant BW  : integer := 32;
  constant WPF : integer := 101;
  constant FAW : integer := 26;

  signal clk   : std_logic := '0';
  signal reset : std_logic := '1';

  signal c_start, c_stop, c_wrcmd, c_regacc, c_desync : std_logic;
  signal c_frame_addr : std_logic_vector(FAW-1 downto 0);
  signal c_num_frames : std_logic_vector(19 downto 0);
  signal c_data_in    : std_logic_vector(BW-1 downto 0);
  signal c_data_in_fetch, c_data_out_valid, c_busy, c_synced : std_logic;
  signal c_data_out   : std_logic_vector(BW-1 downto 0);
  signal c_cur_frame  : std_logic_vector(19 downto 0);
  signal c_cur_word   : std_logic_vector(log2(WPF)-1 downto 0);

  signal icap_csn, icap_rd_wrn, icap_ready, icap_clk : std_logic;
  signal icap_wrdata, icap_rddata : std_logic_vector(BW-1 downto 0);

  signal inj_start : std_logic := '0';
  signal Word_pos  : std_logic_vector(6 downto 0)  := (others=>'0');
  signal Fault_Word: std_logic_vector(31 downto 0) := (others=>'0');
  signal inj_busy, inj_synced : std_logic;
  signal tgt_frame : std_logic_vector(FAW-1 downto 0) := (others=>'0');
  signal sim_done : boolean := false;

  function bit_swap(din: std_logic_vector(31 downto 0)) return std_logic_vector is
    variable dout: std_logic_vector(31 downto 0);
  begin
    for i in 0 to 3 loop
      for j in 0 to 7 loop
        dout(8*i+j) := din(8*i+7-j);
      end loop;
    end loop;
    return dout;
  end function;
begin
  clk <= not clk after 5 ns when not sim_done else '0';

  ctrl: entity work.icap_controller
    generic map (words_per_frame=>WPF, bits_per_word=>BW, frame_addr_width=>FAW)
    port map (
      clk=>clk, reset=>reset,
      icap_csn=>icap_csn, icap_rd_wrn=>icap_rd_wrn, icap_wrdata=>icap_wrdata,
      icap_rddata=>icap_rddata, icap_ready=>icap_ready, icap_clk=>icap_clk,
      start=>c_start, stop_command=>c_stop, write_command=>c_wrcmd,
      register_access=>c_regacc, desync=>c_desync, frame_addr=>c_frame_addr,
      num_of_frames=>c_num_frames, data_in=>c_data_in, data_in_fetch=>c_data_in_fetch,
      data_out=>c_data_out, data_out_valid=>c_data_out_valid, busy=>c_busy,
      synced=>c_synced, current_frame_index=>c_cur_frame, current_word_index=>c_cur_word);

  inj: entity work.fault_Injection
    generic map (frame_width=>7, words_per_frame=>WPF, bits_per_word=>BW, frame_addr_width=>FAW)
    port map (
      CLK=>clk, Start=>inj_start, desync=>'0', request=>'1',
      Busy=>inj_busy, synced=>inj_synced,
      Far_address_i=>tgt_frame, Word_pos_i=>Word_pos, Fault_Word_i=>Fault_Word,
      icap_request=>open, icap_grant=>'1',
      icap_start=>c_start, icap_stop=>c_stop, icap_write_command=>c_wrcmd,
      icap_register_access=>c_regacc, icap_desync=>c_desync, icap_busy=>c_busy,
      icap_synced=>c_synced, icap_data_in_fetch=>c_data_in_fetch,
      icap_data_out_valid=>c_data_out_valid, icap_frame_addr=>c_frame_addr,
      icap_num_of_frames=>c_num_frames, icap_current_frame_index=>c_cur_frame,
      icap_current_word_index=>c_cur_word, icap_data_in=>c_data_in, icap_data_out=>c_data_out);

  icap_ready <= '1';
  icap_model: process(clk)
    variable rptr : integer := 0;
    variable wpos : integer := 0;
    variable gap  : integer := 0;
    variable rd   : std_logic_vector(31 downto 0);
  begin
    if rising_edge(clk) then
      if reset='1' then
        rptr := 0;
        icap_rddata <= x"000000D0";
      else
        if icap_csn='0' and icap_rd_wrn='1' then
          icap_rddata <= bit_swap(x"C0DE" & conv_std_logic_vector(rptr, 16));
          rptr := rptr + 1;
        else
          icap_rddata <= x"000000D0";
        end if;
        -- capture writeback; reset the physical-word counter when a write burst
        -- restarts after a gap (so each frame is counted 0..100)
        if icap_csn='0' and icap_rd_wrn='0' then
          rd := bit_swap(icap_wrdata);
          if rd(31 downto 16) = x"C0DE" then
            if gap > 3 then wpos := 0; end if;
            report "WRB word=" & integer'image(wpos) &
                   " marker=" & integer'image(conv_integer(rd(15 downto 0)));
            wpos := wpos + 1;
            gap := 0;
          else
            gap := gap + 1;
          end if;
        end if;
      end if;
    end if;
  end process;

  -- Capture what the injector STORES on the read side (state 2): the marker on
  -- data_out at each valid cycle, tagged with the controller's word index.
  rdcap: process(clk)
  begin
    if rising_edge(clk) then
      if reset='0' and c_data_out_valid='1' then
        if c_data_out(31 downto 16) = x"C0DE" then
          report "RDV word=" & integer'image(conv_integer(c_cur_word)) &
                 " marker=" & integer'image(conv_integer(c_data_out(15 downto 0)));
        end if;
      end if;
    end if;
  end process;

  stim: process
  begin
    reset <= '1'; inj_start <= '0';
    tgt_frame <= conv_std_logic_vector(16#2000#, FAW);
    Word_pos  <= conv_std_logic_vector(10, 7);
    Fault_Word<= x"00000020";   -- single bit (bit5) of word 10
    wait for 53 ns;
    reset <= '0';
    wait for 20 ns;
    inj_start <= '1';
    wait for 120 ns;      -- pulse: enough to enter the sequence once
    inj_start <= '0';
    wait for 20 us;       -- one full read+write frame completes well within this
    report "=== SIM COMPLETE ===";
    sim_done <= true;
    wait;
  end process;
end architecture;
