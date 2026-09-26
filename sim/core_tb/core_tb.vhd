-- ============================================================================
-- core_tb: closed-loop testbench for the ENTIRE scrubber_ip.
--   Real DUT (scan driver + syndrome handler + parity calc + memories +
--   2-D EDC + arbiter + ICAP controller) against a behavioural model of the
--   configuration engine: a real frame memory served over the ICAP pin
--   protocol, plus a FRAME_ECCE2 emulation computed from a golden reference.
--   Demonstrates: golden-parity init, clean scan (no false positives),
--   autonomous single-bit correction, adjacent double-bit (2-D) correction,
--   and two-frame same-subgroup correction.  Self-checking.
-- ============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_arith.all;
use work.log2_pkg.all;
use work.icape_common.all;

entity core_tb is end core_tb;

architecture tb of core_tb is
  constant BW   : integer := 32;
  constant WPF  : integer := 101;
  constant FAW  : integer := 26;
  constant NFR  : integer := 72;          -- modelled frames (two 36-minor columns)
  constant DYN_FRAME : integer := 40;     -- mem index; FAR 0x84 (col1 minor 4)
  constant GRP  : integer := 64;          -- max_frames_per_group
  -- 2026 multi-column geometry (mirrors measured silicon structure):
  -- col0 = FAR 0x00..0x23 (36 minors) -> mem 0..35
  -- col1 = FAR 0x80..0xA3 (36 minors) -> mem 36..71   (jump at the crossing)
  -- FAR >= 0xA4: invalid region (garbage frames, constant 0x653 flags)
  constant COL_MIN : integer := 36;
  -- interleave depth under test (power of two); same-subgroup pair = (PAIR_A, PAIR_A+S)
  constant S_TB    : integer := 2;
  constant G_TB    : integer := 64;
  constant PAIR_A  : integer := 12;
  constant COL1_BASE : integer := 16#80#;
  constant FAR_END : integer := COL1_BASE + COL_MIN;  -- 0xA4

  signal clk    : std_logic := '0';
  signal reset  : std_logic := '1';
  signal sim_done : boolean := false;

  signal icap_csn, icap_rd_wrn, icap_ready, icap_clk : std_logic;
  signal icap_wrdata, icap_rddata : std_logic_vector(BW-1 downto 0);
  signal fecc_valid, fecc_ecc, fecc_single, fecc_crc : std_logic := '0';
  signal fecc_syndrome : std_logic_vector(12 downto 0) := (others=>'0');
  signal fecc_far : std_logic_vector(FAW-1 downto 0) := (others=>'0');
  signal fecc_synword : std_logic_vector(6 downto 0) := (others=>'0');
  signal fecc_synbit  : std_logic_vector(4 downto 0) := (others=>'0');
  signal scrub_diag : std_logic_vector(7 downto 0);
  signal core_live  : std_logic_vector(31 downto 0);
  signal skip_seen  : std_logic := '0';
  signal pcalc_dbg  : std_logic_vector(7 downto 0);

  signal inj_req   : std_logic := '0';
  signal inj_frame : integer := 0;
  signal inj_word  : integer := 0;
  signal inj_mask  : std_logic_vector(BW-1 downto 0) := (others=>'0');
  signal inj_ack   : std_logic := '0';
  signal frames_dirty : integer := 0;
  signal wr_commits   : integer := 0;
  -- golden-store fault hook (2026 hardening check)
  signal gm_hit  : std_logic := '0';
  signal gm_addr : integer := 0;
  signal gm_mask : std_logic_vector(35 downto 0) := (others => '0');
  signal tmr_flip : std_logic := '0';
  signal tb_hang  : std_logic := '0';

  type frame_arr_t is array (0 to NFR-1) of frame_t;

  function gword(f, w : integer) return std_logic_vector is
    variable v : integer;
  begin
    v := (f*131071 + w*8191 + 12345) mod 1073741824;
    return conv_std_logic_vector(v, BW);
  end;

  function enc_word(w : integer) return integer is
  begin
    if w <= 6 then return w+25;
    elsif w <= 37 then return w+26;
    else return w+27; end if;
  end;

  function bswap(d : std_logic_vector(31 downto 0)) return std_logic_vector is
    variable o : std_logic_vector(31 downto 0);
  begin
    for i in 0 to 3 loop
      for j in 0 to 7 loop
        o(8*i+j) := d(8*i+7-j);
      end loop;
    end loop;
    return o;
  end;

begin
  skip_mon: process(clk) begin if rising_edge(clk) then if core_live(3) = '1' then skip_seen <= '1'; end if; end if; end process;
  clk <= not clk after 5 ns when not sim_done else '0';
  icap_ready <= '1';

  dut: entity work.scrubber_ip
    generic map (
      -- TB masked list: frame 40 is modeled as a dynamic frame (see engine)
      masked_frames => (0 => conv_std_logic_vector(COL1_BASE + 4, FAW),  -- DYN_FRAME's FAR
                        1 => conv_std_logic_vector(63, FAW)),
      wd_timeout_cycles => 20000,  -- 200 us in TB (init ~74 us, passes ~10 us)
      -- TB two-column geometry (matches the engine's FAR map)
      top_col_minors => (0 => COL_MIN, 1 => COL_MIN, others => 0),
      bot_col_minors => (others => 0),
      subgroups_per_group => S_TB,
      max_frames_per_group => G_TB,
      syndromes_mem_entries => 2*G_TB
    )
    port map (
      clk => clk, reset => reset,
      enable => '1', golden_pmem_init => '1',
      start_frame_addr => conv_std_logic_vector(0, FAW),
      end_frame_addr   => conv_std_logic_vector(FAR_END, FAW),
      status_state => open, heartbeat => open,
      clk_free => clk, icap_idle => open, test_dbg => open, core_live => core_live,
      scrub_diag => scrub_diag, pcalc_dbg => pcalc_dbg,
      sim_gm_corrupt_pulse => gm_hit, sim_gm_corrupt_addr => gm_addr,
      sim_gm_corrupt_mask => gm_mask, sim_tmr_flip => tmr_flip, sim_hang => tb_hang,
      corr_frame_addr => open, corr_frame_data => open, corr_frame_valid => open,
      parity_frame_addr => open, parity_frame_data => open, parity_frame_valid => open,
      icap_csn => icap_csn, icap_rd_wrn => icap_rd_wrn,
      icap_wrdata => icap_wrdata, icap_rddata => icap_rddata,
      icap_ready => icap_ready, icap_clk => icap_clk,
      fecc_syndromevalid => fecc_valid, fecc_eccerror => fecc_ecc,
      fecc_syndrome => fecc_syndrome, fecc_crcerror => fecc_crc,
      fecc_far => fecc_far, fecc_synword => fecc_synword,
      fecc_synbit => fecc_synbit, fecc_eccerrorsingle => fecc_single,
      inject_request => '0', inject_grant => open, inject_start => '0',
      inject_stop => '0', inject_write_command => '0',
      inject_register_access => '0', inject_desync => '0',
      inject_busy => open, inject_synced => open,
      inject_data_in_fetch => open, inject_data_out_valid => open,
      inject_frame_addr => (others=>'0'), inject_num_of_frames => (others=>'0'),
      inject_cur_frame_index => open, inject_cur_word_index => open,
      inject_data_in => (others=>'0'), inject_data_out => open);

  -- ==========================================================================
  -- Configuration-engine + FRAME_ECC model (single process owns the memory)
  -- ==========================================================================
  engine: process(clk)
    type st_t is (UNSYNCED, PARSE, RSTREAM, WCOLLECT);
    variable st        : st_t := UNSYNCED;
    variable mem       : frame_arr_t;
    variable golden    : frame_arr_t;
    variable inited    : boolean := false;
    variable lastreg   : integer := -1;
    variable payload   : integer := 0;
    variable far_reg   : integer := 0;
    variable rd_words  : integer := 0;
    variable wr_words  : integer := 0;
    variable rf, rw    : integer := 0;
    variable dummy_left: integer := 0;
    variable wf_buf    : frame_t;
    type wraw_t is array(0 to 209) of std_logic_vector(31 downto 0);
    variable wraw : wraw_t;
    variable rpipe1, rpipe2, rpipe3, rnext : std_logic_vector(31 downto 0) := (others=>'0');
    variable far_pend : integer := 0;
    -- fecc pipeline: FRAME_ECCE2 outputs are phase-locked to the readback data,
    -- so they ride the same 3-stage delay as the data pipe
    type farp_t is array(1 to 4) of std_logic_vector(FAW-1 downto 0);
    type synp_t is array(1 to 4) of std_logic_vector(12 downto 0);
    type sl3_t  is array(1 to 4) of std_logic;
    type w7p_t  is array(1 to 4) of std_logic_vector(6 downto 0);
    type b5p_t  is array(1 to 4) of std_logic_vector(4 downto 0);
    variable p_far : farp_t := (others=>(others=>'0'));
    variable p_syn : synp_t := (others=>(others=>'0'));
    variable p_vld, p_ecc, p_sgl : sl3_t := (others=>'0');
    variable p_wrd : w7p_t := (others=>(others=>'0'));
    variable p_bit : b5p_t := (others=>(others=>'0'));
    variable n_far : std_logic_vector(FAW-1 downto 0) := (others=>'0');
    variable n_syn : std_logic_vector(12 downto 0) := (others=>'0');
    variable n_vld, n_ecc, n_sgl : std_logic := '0';
    variable n_wrd : std_logic_vector(6 downto 0) := (others=>'0');
    variable n_bit : std_logic_vector(4 downto 0) := (others=>'0');
    variable wr_idx    : integer := 0;
    variable w         : std_logic_vector(31 downto 0);
    variable diff      : std_logic_vector(31 downto 0);
    variable nbits, fw, fb : integer;
    variable syn       : std_logic_vector(12 downto 0);

    -- FAR -> modelled frame index; -1 = invalid region
    function far2idx(fa : integer) return integer is
    begin
      if fa >= 0 and fa < COL_MIN then return fa; end if;
      if fa >= COL1_BASE and fa < COL1_BASE + COL_MIN then
        return fa - COL1_BASE + COL_MIN;
      end if;
      return -1;
    end function;
    -- device FAR auto-advance incl. the column jump
    function far_next(fa : integer) return integer is
    begin
      if fa = COL_MIN - 1 then return COL1_BASE; end if;
      return fa + 1;
    end function;

    procedure frame_flags(f : integer) is
    begin
      if f = -1 then
        -- invalid-region garbage frame: constant embedded-ECC inconsistency
        n_ecc := '1'; n_sgl := '0';
        n_syn := conv_std_logic_vector(16#0653#, 13);
        n_vld := '1';
        return;
      end if;
      if f = DYN_FRAME then
        n_ecc := '1'; n_sgl := '0';
        n_syn := conv_std_logic_vector(16#0653#, 13);
        n_vld := '1';
        return;
      end if;
      nbits := 0; fw := 0; fb := 0;
      syn := (others=>'0');
      for wi in 0 to WPF-1 loop
        diff := mem(f)(wi) xor golden(f)(wi);
        for bi in 0 to BW-1 loop
          if diff(bi)='1' then
            nbits := nbits + 1;
            fw := wi; fb := bi;
            syn(11 downto 0) := syn(11 downto 0) xor
              (conv_std_logic_vector(enc_word(wi),7) & conv_std_logic_vector(bi,5));
          end if;
        end loop;
      end loop;
      if (nbits mod 2) = 1 then syn(12) := '1'; else syn(12) := '0'; end if;
      if nbits > 0 and now > 460 us then
        report "ENGINE: flags idx=" & integer'image(f) & " nbits=" & integer'image(nbits);
      end if;

      if nbits = 0 then
        n_ecc := '0'; n_sgl := '0'; n_syn := (others=>'0');
      else
        n_ecc := '1';
        if nbits = 1 then n_sgl := '1'; else n_sgl := '0'; end if;
        n_syn := syn;
        n_wrd := conv_std_logic_vector(fw,7);
        n_bit := conv_std_logic_vector(fb,5);
      end if;
      n_vld := '1';
    end procedure;

    procedure count_dirty is
      variable d : integer := 0;
      variable df : std_logic_vector(31 downto 0);
      variable any : boolean;
    begin
      d := 0;
      for f in 0 to NFR-1 loop
        if f /= DYN_FRAME then
          any := false;
          for wi in 0 to WPF-1 loop
            df := mem(f)(wi) xor golden(f)(wi);
            if df /= conv_std_logic_vector(0,BW) then any := true; end if;
          end loop;
          if any then d := d+1; end if;
        end if;
      end loop;
      frames_dirty <= d;
    end procedure;

  begin
    if rising_edge(clk) then
      if not inited then
        for f in 0 to NFR-1 loop
          for wi in 0 to WPF-1 loop
            golden(f)(wi) := gword(f,wi);
            mem(f)(wi)    := gword(f,wi);
          end loop;
        end loop;
        inited := true;
        frames_dirty <= 0;
      end if;

      inj_ack <= '0';

      if inj_req = '1' and inj_ack = '0' then
        mem(inj_frame)(inj_word) := mem(inj_frame)(inj_word) xor inj_mask;
        inj_ack <= '1';
        count_dirty;
        report "ENGINE: injected into frame " & integer'image(inj_frame)
               & " word " & integer'image(inj_word);
      end if;

      if reset = '1' then
        st := UNSYNCED; icap_rddata <= x"000000D0";
      else
        case st is
          when UNSYNCED =>
            icap_rddata <= x"00000000";
            if icap_csn='0' and icap_rd_wrn='0' then
              w := bswap(icap_wrdata);
              if w = SYNC_WORD then
                st := PARSE; lastreg := -1; payload := 0;
              end if;
            end if;

          when PARSE =>
            icap_rddata <= x"000000D0";
            if icap_csn='0' and icap_rd_wrn='0' then
              w := bswap(icap_wrdata);
              if payload > 0 then
                payload := payload - 1;
                if lastreg = 1 then far_reg := conv_integer(w(FAW-1 downto 0));
                elsif lastreg = 4 then
                  if w(4 downto 0) = "01101" then st := UNSYNCED; end if;
                end if;
              elsif w(31 downto 29) = "001" then
                if w(28 downto 27) = "10" then          -- type1 write
                  lastreg := conv_integer(w(17 downto 13));
                  payload := conv_integer(w(10 downto 0));
                elsif w(28 downto 27) = "01" then       -- type1 read (e.g. FDRO)
                  lastreg := conv_integer(w(17 downto 13));
                  payload := 0;
                end if;
              elsif w(31 downto 29) = "010" then
                if lastreg = 3 then
                  rd_words := conv_integer(w(26 downto 0));
                  rf := far_reg; rw := 0; dummy_left := WPF;
                  n_far := conv_std_logic_vector(rf, FAW);
                  far_pend := 0;
                  st := RSTREAM;
                  if now > 460 us then
                    report "ENGINE: RD burst start far=" & integer'image(far_reg)
                           & " words=" & integer'image(conv_integer(w(23 downto 0)));
                  end if;
                elsif lastreg = 2 then
                  wr_words := conv_integer(w(26 downto 0));
                  wr_idx := 0;
                  st := WCOLLECT;
                  if now > 460 us then
                    report "ENGINE: WR burst start far=" & integer'image(far_reg)
                           & " count=" & integer'image(conv_integer(w(23 downto 0)));
                  end if;
                end if;
              end if;
            end if;

          when RSTREAM =>
            if icap_csn='0' and icap_rd_wrn='1' then
              n_vld := '0';
              -- compute the next produced word (3 cycles ahead of the ICAP output,
              -- matching real ICAPE2 read latency: the controller fetches 3 early)
              if dummy_left > 0 then
                rnext := bswap(x"0000BEEF");
                dummy_left := dummy_left - 1;
                if dummy_left = 0 then
                  n_far := conv_std_logic_vector(far_next(rf), FAW);
                end if;
              else
                if far_pend > 1 then
                  far_pend := far_pend - 1;
                elsif far_pend = 1 then
                  -- FAR steps to the next frame's successor a few cycles after
                  -- the pulse (silicon: when readback enters the next frame)
                  n_far := conv_std_logic_vector(far_next(rf), FAW);
                  far_pend := 0;
                end if;
                if far2idx(rf) >= 0 then
                  rnext := bswap(mem(far2idx(rf))(rw));
                else
                  rnext := bswap(x"BAD0BAD0");
                end if;
                rw := rw + 1;
                if rw = WPF then
                  frame_flags(far2idx(rf));
                  rw := 0; rf := far_next(rf);
                  far_pend := 4;
                end if;
              end if;
              -- 3-stage output pipe (advances only while selected for read)
              icap_rddata <= rpipe3;
              rpipe3 := rpipe2;
              rpipe2 := rpipe1;
              rpipe1 := rnext;
              -- fecc rides the same delay
              fecc_far <= p_far(4); fecc_syndrome <= p_syn(4);
              fecc_valid <= p_vld(4); fecc_ecc <= p_ecc(4); fecc_single <= p_sgl(4);
              fecc_synword <= p_wrd(4); fecc_synbit <= p_bit(4);
              p_far(4):=p_far(3); p_far(3):=p_far(2); p_far(2):=p_far(1); p_far(1):=n_far;
              p_syn(4):=p_syn(3); p_syn(3):=p_syn(2); p_syn(2):=p_syn(1); p_syn(1):=n_syn;
              p_vld(4):=p_vld(3); p_vld(3):=p_vld(2); p_vld(2):=p_vld(1); p_vld(1):=n_vld;
              p_ecc(4):=p_ecc(3); p_ecc(3):=p_ecc(2); p_ecc(2):=p_ecc(1); p_ecc(1):=n_ecc;
              p_sgl(4):=p_sgl(3); p_sgl(3):=p_sgl(2); p_sgl(2):=p_sgl(1); p_sgl(1):=n_sgl;
              p_wrd(4):=p_wrd(3); p_wrd(3):=p_wrd(2); p_wrd(2):=p_wrd(1); p_wrd(1):=n_wrd;
              p_bit(4):=p_bit(3); p_bit(3):=p_bit(2); p_bit(2):=p_bit(1); p_bit(1):=n_bit;
            elsif icap_csn='0' and icap_rd_wrn='0' then
              fecc_valid <= '0';
              w := bswap(icap_wrdata);
              st := PARSE; lastreg := -1; payload := 0;
              icap_rddata <= x"000000D0";
              if now > 460 us then
                report "ENGINE: RD burst end at rf=" & integer'image(rf)
                       & " rw=" & integer'image(rw) & " dummy_left=" & integer'image(dummy_left);
              end if;
            end if;

          when WCOLLECT =>
            if icap_csn='0' and icap_rd_wrn='0' then
              w := bswap(icap_wrdata);
              if wr_idx < WPF then
                wf_buf(wr_idx) := w;
              end if;
              if wr_idx < 210 then wraw(wr_idx) := w; end if;
              wr_idx := wr_idx + 1;
              wr_words := wr_words - 1;
              if wr_idx = WPF then
                assert far2idx(far_reg) /= DYN_FRAME
                  report "FAIL: correction targeted the MASKED dynamic frame"
                  severity failure;
                assert far2idx(far_reg) >= 0
                  report "FAIL: correction targeted an INVALID FAR"
                  severity failure;
                if far2idx(far_reg) >= 0 then
                  for wi in 0 to WPF-1 loop
                    mem(far2idx(far_reg))(wi) := wf_buf(wi);
                  end loop;
                  wr_commits <= wr_commits + 1;
                  count_dirty;
                  report "ENGINE: FDRI commit to frame idx " & integer'image(far2idx(far_reg))
                         & " (far " & integer'image(far_reg) & ")";
                  for wi in 0 to WPF-1 loop
                    diff := mem(far2idx(far_reg))(wi) xor golden(far2idx(far_reg))(wi);
                    if diff /= conv_std_logic_vector(0,BW) then
                      report "ENGINE: DIFF w=" & integer'image(wi)
                             & " raw=" & integer'image(conv_integer(wraw(wi)(23 downto 0)))
                             & " gold=" & integer'image(conv_integer(golden(far2idx(far_reg))(wi)(23 downto 0)));
                    end if;
                  end loop;
                end if;
              end if;
              if wr_words <= 0 then
                st := PARSE; lastreg := -1; payload := 0;
              end if;
            end if;
        end case;
      end if;
    end if;
  end process;

  -- progress monitor: report DUT diagnostic state changes (bounded)
  mon: process(clk)
    variable last_d : std_logic_vector(7 downto 0) := (others=>'U');
    variable last_p : std_logic_vector(7 downto 0) := (others=>'U');
    variable n : integer := 0;
  begin
    if rising_edge(clk) and n < 400 then
      if scrub_diag /= last_d then
        report "MON t=" & time'image(now) & " sm_state=" & integer'image(conv_integer(scrub_diag(4 downto 1)))
               & " ec_busy=" & std_logic'image(scrub_diag(5))
               & " fifo_empty=" & std_logic'image(scrub_diag(6))
               & " fifo_rd=" & std_logic'image(scrub_diag(7));
        last_d := scrub_diag; n := n+1;
      end if;
      if pcalc_dbg /= last_p then
        report "MON t=" & time'image(now) & " pcalc_state=" & integer'image(conv_integer(pcalc_dbg(2 downto 0)))
               & " start_ec=" & std_logic'image(pcalc_dbg(5))
               & " ec_done=" & std_logic'image(pcalc_dbg(6))
               & " sh_busy=" & std_logic'image(pcalc_dbg(7));
        last_p := pcalc_dbg; n := n+1;
      end if;
    end if;
  end process;

  -- ==========================================================================
  -- Stimulus & checker
  -- ==========================================================================
  check: process
    variable wc0 : natural;
    variable t_wd : time;
    procedure inject(f, w : integer; m : std_logic_vector(31 downto 0)) is
    begin
      inj_frame <= f; inj_word <= w; inj_mask <= m;
      inj_req <= '1';
      wait until inj_ack = '1' for 1 us;
      assert inj_ack='1' report "inject ack timeout" severity failure;
      inj_req <= '0';
      wait until rising_edge(clk);
    end procedure;
    procedure wait_clean(timeout : time; tag : string) is
      variable t0 : time;
    begin
      t0 := now;
      while frames_dirty /= 0 loop
        wait for 10 us;
        assert (now - t0) < timeout
          report "TIMEOUT waiting for correction: " & tag severity failure;
      end loop;
      report "PASS: " & tag & " corrected (t=" & time'image(now) & ")";
    end procedure;
  begin
    reset <= '1'; wait for 100 ns; reset <= '0';

    wait until scrub_diag(0) = '1' for 5 ms;
    assert scrub_diag(0)='1' report "golden-parity init never completed" severity failure;
    report "PASS: golden-parity initialization complete (t=" & time'image(now) & ")";

    wait for 300 us;
    assert wr_commits = 0 report "FALSE POSITIVE: write-back during clean scan" severity failure;
    report "PASS: clean scan, no false positives";

    inject(5, 10, x"00000008");
    wait_clean(3 ms, "single-bit (frame 5, word 10, bit 3)");

    inject(9, 10, x"00000030");
    wait_clean(3 ms, "adjacent double-bit (frame 9, word 10, bits 4-5) via 2-D code");

    inject(PAIR_A, 3, x"00000001");
    inject(PAIR_A + S_TB, 7, x"00000002");
    wait_clean(4 ms, "two frames same subgroup (PAIR_A & PAIR_A+S)");

    -- column-LAST frame (idx 35 = FAR 0x23, last minor of col0): at its
    -- SYNDROMEVALID pulse the FAR has already jumped to col1's base, so plain
    -- FAR-1 attribution fails; the measured-geometry lookup must resolve it.
    inject(COL_MIN-1, 10, x"00000008");
    wait_clean(4 ms, "COLUMN-LAST frame (idx 35, far 0x23) single-bit");

    -- first frame of the second column (idx 36 = FAR 0x80): exercises
    -- cross-column addressing on the correction write path.
    inject(COL_MIN, 20, x"00000030");
    wait_clean(4 ms, "cross-column frame (idx 36, far 0x80) adjacent double-bit");

    -- S-specific capability: a run of S ADJACENT frames upset at once - every
    -- frame lands in a distinct subgroup, so all are parity-reconstructable.
    -- (At S=2 this pattern would put two frames in each subgroup.)
    if S_TB >= 4 then
      inject(20, 11, x"00000010");
      inject(21, 22, x"00000100");
      inject(22, 33, x"00001000");
      inject(23, 44, x"00010000");
      wait_clean(6 ms, "FOUR adjacent frames (20..23) simultaneously - S=4 capability");
    end if;

    -- ==== golden-store upset (2026 hardening) ============================
    -- Flip one stored data bit in the golden parity BRAM: column 1, subgroup-0
    -- bank, word 50 (mem addr 1*101+50). The next scan pass over column 1
    -- reads golden while accumulating calc parity, the byte-parity check
    -- fires, the pass is poisoned and `initialized` drops - the full golden
    -- re-init then rebuilds the store from the (clean) frames. No frame is
    -- ever written: the upset heals with zero corrections.
    wc0 := wr_commits;
    gm_mask <= x"000000020";  -- data bit 5 of word 50, column 1's slot
    gm_addr <= 151;           -- 1*101 + 50
    gm_hit  <= '1';
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    gm_hit  <= '0';
    wait until scrub_diag(0) = '0' for 40 ms;
    assert scrub_diag(0) = '0'
      report "golden-store upset never detected (initialized never dropped)" severity failure;
    report "PASS: golden-store upset detected on scan pass - re-init triggered (t=" & time'image(now) & ")";
    wait until scrub_diag(0) = '1' for 10 ms;
    assert scrub_diag(0) = '1' report "golden re-init never completed" severity failure;
    assert wr_commits = wc0
      report "unexpected frame write-back during golden-upset handling" severity failure;
    report "PASS: golden re-init complete, no spurious frame writes";
    -- and the 2-D machinery still works on the rebuilt golden store:
    inject(37, 60, x"00000800");
    wait_clean(6 ms, "post-golden-re-init single-bit (frame 37, col 1)");

    -- ==== TMR fault injection (2026 hardening) ===========================
    -- Flip copy A of the TMR'd registers (pcalc `initialized`, handler's two
    -- syndrome-memory indices) while the scrubber is quietly scanning. The
    -- majority vote must mask the flip (no init drop, no false activity) and
    -- the feedback voter heals the copy within a cycle.
    wc0 := wr_commits;
    tmr_flip <= '1';
    wait until rising_edge(clk); wait until rising_edge(clk);
    tmr_flip <= '0';
    wait for 50 us;
    assert scrub_diag(0) = '1'
      report "TMR flip caused an initialized drop (vote failed to mask)" severity failure;
    assert wr_commits = wc0
      report "TMR flip caused frame write-back activity" severity failure;
    report "PASS: TMR flip at rest masked by majority vote (no disturbance)";

    -- and again in the middle of an error-handling episode: inject, flip
    -- while detection/handling is in flight, and require normal correction.
    inject(6, 42, x"00000080");
    wait for 30 us;
    tmr_flip <= '1';
    wait until rising_edge(clk); wait until rising_edge(clk);
    tmr_flip <= '0';
    wait_clean(6 ms, "single-bit (frame 6) corrected with TMR flip mid-episode");

    -- 2026-09-03: the two checks above pass with the voters BYPASSED (generic
    -- tmr_enable=false): the at-rest flip lands on indices that the next
    -- episode resets, and the mid-episode flip lands in a single-entry
    -- episode where sm_last is never consulted. A check that cannot fail is
    -- not a test. This one stores TWO entries in one group and lands the flip
    -- at several points after the handler goes busy - in store, in the parity
    -- pass, in correction - so a wrong index has consequences. It must fail
    -- with tmr_enable=false (verified: it does) and pass with it true.
    for k in 1 to 5 loop
      inject(PAIR_A, 3, x"00000100");
      inject(PAIR_A + S_TB, 7, x"00000200");
      wait until pcalc_dbg(7) = '1' for 2 ms;       -- handler busy: episode started
      assert pcalc_dbg(7) = '1' report "TMR-multi: episode never started" severity failure;
      case k is
        when 1 => wait for 300 ns;
        when 2 => wait for 2 us;
        when 3 => wait for 8 us;
        when 4 => wait for 25 us;
        when others => wait for 60 us;
      end case;
      tmr_flip <= '1';
      wait until rising_edge(clk); wait until rising_edge(clk);
      tmr_flip <= '0';
      wait_clean(6 ms, "TMR flip #" & integer'image(k) & " inside a two-entry episode: both frames corrected");
    end loop;
    report "PASS: TMR discriminating check (two-entry episode, five flip points)";

    -- ==== watchdog self-reset (2026 hardening) ===========================
    -- Starve the parity calculator's arbiter request: scan passes stop
    -- completing, the progress watchdog must fire, soft-reset the core, and
    -- recovery is the normal boot path (golden re-init) once the hang clears.
    tb_hang <= '1';
    wait until scrub_diag(0) = '0' for 2 ms;
    assert scrub_diag(0) = '0'
      report "watchdog never fired on a starved scrubber" severity failure;
    -- NOTE: scrub_diag is cleared by core_reset, so this dip only proves the
    -- watchdog asserted its recovery reset - it does NOT prove anything about
    -- golden. Time how long init stays low to tell the two apart:
    --   ~16 cycles  -> golden PRESERVED across the soft reset (correct)
    --   ~74 us      -> a full golden re-init ran (the 2026-09-01 defect: it
    --                  re-learns any uncorrected upset as golden)
    t_wd := now;
    tb_hang <= '0';
    wait until scrub_diag(0) = '1' for 5 ms;
    assert scrub_diag(0) = '1' report "core never recovered after watchdog" severity failure;
    assert (now - t_wd) < 5 us
      report "watchdog reset triggered a FULL GOLDEN RE-INIT (" & time'image(now - t_wd)
           & ") - golden must be preserved across a soft reset" severity failure;
    report "PASS: watchdog fired, core recovered with golden PRESERVED (down "
           & time'image(now - t_wd) & ")";
    inject(8, 55, x"00000400");
    wait_clean(6 ms, "post-watchdog single-bit (frame 8)");

    -- ==== repeat error, same frame (silicon 2026-08-29 finding) ==========
    -- On silicon builds 4-5 the FIRST error in a frame corrects but every
    -- SUBSEQUENT error in the same frame loops uncorrected. Reproduce here.
    inject(17, 40, x"00000100");
    wait_clean(4 ms, "repeat-check: first error (frame 17)");
    wait for 200 us;
    inject(17, 70, x"00002000");
    wait_clean(4 ms, "repeat-check: SECOND error same frame (frame 17)");
    wait for 200 us;
    inject(17, 40, x"00000001");
    wait_clean(4 ms, "repeat-check: THIRD error same frame (frame 17)");

    -- ==== bit flips DURING a correction episode ==========================
    -- The question the hardware cannot yet answer: what happens if an upset
    -- lands while the corrector is mid-episode? scrub_diag(4) is the LIVE
    -- parity-calculator arbiter request - high exactly while the compare pass
    -- that drives a correction is running - so the flip can be placed inside
    -- it. (diag(5..7) are sticky latches and cannot serve as a live busy.)
    report "---- mid-correction injection experiments ----";

    -- (a) second upset in a DIFFERENT frame while frame 5 is being corrected
    wc0 := wr_commits;
    inject(5, 10, x"00000008");
    if scrub_diag(4) /= '1' then wait until scrub_diag(4) = '1' for 3 ms; end if;
    assert scrub_diag(4) = '1' report "compare pass never started (a)" severity failure;
    inject(21, 30, x"00000040");          -- lands mid-episode, other subgroup
    wait_clean(8 ms, "MID-CORRECTION upset in another frame (both corrected)");

    -- (b) second upset in the SAME frame that is being corrected
    inject(9, 15, x"00000010");
    if scrub_diag(4) /= '1' then wait until scrub_diag(4) = '1' for 3 ms; end if;
    assert scrub_diag(4) = '1' report "compare pass never started (b)" severity failure;
    inject(9, 70, x"00000200");           -- same frame, while it is being fixed
    wait_clean(8 ms, "MID-CORRECTION second upset in the SAME frame");

    -- (c) golden-store upset while a correction is in flight: the reference is
    -- being read exactly then, so this is the worst-case interleaving.
    inject(13, 44, x"00000004");
    if scrub_diag(4) /= '1' then wait until scrub_diag(4) = '1' for 3 ms; end if;
    assert scrub_diag(4) = '1' report "compare pass never started (c)" severity failure;
    gm_mask <= x"000000040"; gm_addr <= 151; gm_hit <= '1';
    wait until rising_edge(clk); wait until rising_edge(clk);
    gm_hit <= '0';
    -- the poisoned pass must be discarded and golden rebuilt; the frame error
    -- must still be gone by the end of it
    wait until scrub_diag(0) = '0' for 20 ms;
    wait until scrub_diag(0) = '1' for 20 ms;
    assert scrub_diag(0) = '1' report "no recovery after mid-correction golden upset" severity failure;
    wait_clean(20 ms, "MID-CORRECTION golden-store upset (recovered)");
    report "PASS: all three mid-correction interleavings handled";
    -- Rev. 1.13 mark-and-skip must never fire in a run where every episode
    -- ends in a correction write
    assert skip_seen = '0' report "FAIL: beyond-capacity skip fired in a clean run" severity failure;
    report "PASS: mark-and-skip stayed quiet";

    report "==== CORE CLOSED-LOOP TB: ALL CHECKS PASSED ====";
    sim_done <= true;
    wait;
  end process;
end architecture;
