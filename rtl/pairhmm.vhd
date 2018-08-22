---------------------------------------------------------------------------------------------------
--    _____      _      _    _ __  __ __  __
--   |  __ \    (_)    | |  | |  \/  |  \/  |
--   | |__) |_ _ _ _ __| |__| | \  / | \  / |
--   |  ___/ _` | | '__|  __  | |\/| | |\/| |
--   | |  | (_| | | |  | |  | | |  | | |  | |
--   |_|   \__,_|_|_|  |_|  |_|_|  |_|_|  |_|
---------------------------------------------------------------------------------------------------
-- PairHMM core in which the systolic array is generated
---------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.functions.all;
use work.posit_common.all;
use work.pe_package.all;
use work.pairhmm_package.all;

entity pairhmm is
  port (
    cr : in  cr_in;
    i  : in  pairhmm_in;
    o  : out pairhmm_out
    );
end entity pairhmm;

architecture logic of pairhmm is

  type pe_ins_type is array (0 to PAIRHMM_NUM_PES - 1) of pe_in;
  type pe_outs_type is array (0 to PAIRHMM_NUM_PES - 1) of pe_out;

  signal pe_ins  : pe_ins_type;
  signal pe_outs : pe_outs_type;

  signal en : std_logic;

  signal x : x_array_type := x_array_empty;

  -- Match X ram latency of 2:
  signal pairhmm_in_reg : pe_in               := pe_in_empty;
  signal schedule_reg   : unsigned(PE_DEPTH_BITS-1 downto 0);
  signal x_reg          : bp_type;
  signal pe_y_data_regs : pe_y_data_regs_type := pe_y_data_regs_empty;
  signal pe_out_reg     : pe_out;

  signal posit_infs : std_logic_vector(2 downto 0);

  signal addm_out       : prob;
  signal addm_out_raw   : value_accum;
  signal addm_out_valid : std_logic;

  signal addi_out       : prob;
  signal addi_out_raw   : value_accum;
  signal addi_out_valid : std_logic;

  signal res_acc : prob;

  type res_array is array (0 to PAIRHMM_NUM_PES-1) of value;

  signal res_rst : std_logic;
  signal resm    : res_array;
  signal resi    : res_array;

  signal resbusm_raw, resbusi_raw : value;
  signal resbusm, resbusi         : prob;

  signal lastlast  : std_logic;
  signal lastlast1 : std_logic;

  signal pe_out_mids_ml, pe_out_mids_il : std_logic_vector(31 downto 0);

begin

  -- Connect input to the input register before the first PE
  pe_ins(0).en      <= pairhmm_in_reg.en;
  pe_ins(0).valid   <= pairhmm_in_reg.valid;
  pe_ins(0).cell    <= pairhmm_in_reg.cell;
  pe_ins(0).initial <= pairhmm_in_reg.initial;
  pe_ins(0).tmis    <= pairhmm_in_reg.tmis;
  pe_ins(0).emis    <= pairhmm_in_reg.emis;
  pe_ins(0).mids    <= pairhmm_in_reg.mids;
  pe_ins(0).y       <= pe_y_data_regs(0)(idx(schedule_reg));
  pe_ins(0).x       <= x_reg;

  -- Generate all the PE's
  P:
  for K in 0 to PAIRHMM_NUM_PES-1 generate

    -- Instantiate First PE
    F : if K = 0 generate
      PECORE : entity work.pe generic map (FIRST => '1') port map (cr => cr, i => pe_ins(K), o => pe_outs(K));
    end generate;

    -- Instantiate Other PE's
    O : if K /= 0 generate
      PECORE : entity work.pe port map (cr => cr, i => pe_ins(K), o => pe_outs(K));
    end generate;

    -- Attach output of current PE to Next PE
    -- but only if it's not the last PE
    N : if K /= PAIRHMM_NUM_PES-1 generate
      pe_ins(K+1).en      <= en;
      pe_ins(K+1).valid   <= pe_outs(K).valid;
      pe_ins(K+1).cell    <= pe_outs(K).cell;
      pe_ins(K+1).initial <= pe_outs(K).initial;
      pe_ins(K+1).tmis    <= pe_outs(K).tmis;
      pe_ins(K+1).emis    <= pe_outs(K).emis;
      pe_ins(K+1).mids    <= pe_outs(K).mids;
      pe_ins(K+1).x       <= pe_outs(K).x;
      pe_ins(K+1).y       <= pe_y_data_regs(K+1)(idx(schedule_reg));
    end generate;

  end generate;

  -- Connect last PE outputs to pair-HMM outputs
  o.last  <= pe_out_reg;
  o.ready <= pe_out_reg.ready;

  regs : process(cr.clk)
  begin
    if rising_edge(cr.clk) then
      if cr.rst = '1' then
        pe_out_reg.valid <= '0';
      else
        pe_out_reg <= pe_outs(PAIRHMM_NUM_PES - 1);

        -- Clock in all inputs
        if i.ybus.wren = '1' then
          pe_y_data_regs(idx(i.ybus.addr)) <= i.ybus.data;
        end if;

        pairhmm_in_reg <= i.first;
        x_reg          <= i.x;
        schedule_reg   <= i.schedule;
      end if;
    end if;
  end process;


---------------------------------------------------------------------------------------------------
--  _____                 _ _                                            _       _
-- |  __ \               | | |       /\                                 | |     | |
-- | |__) |___  ___ _   _| | |_     /  \   ___ ___ _   _ _ __ ___  _   _| | __ _| |_ ___  _ __
-- |  _  // _ \/ __| | | | | __|   / /\ \ / __/ __| | | | '_ ` _ \| | | | |/ _` | __/ _ \| '__|
-- | | \ \  __/\__ \ |_| | | |_   / ____ \ (_| (__| |_| | | | | | | |_| | | (_| | || (_) | |
-- |_|  \_\___||___/\__,_|_|\__| /_/    \_\___\___|\__,_|_| |_| |_|\__,_|_|\__,_|\__\___/|_|
---------------------------------------------------------------------------------------------------

-- POSIT NORMALIZATION
  gen_normalize_es2 : if POSIT_ES = 2 generate
    posit_normalize_ml_es2 : posit_normalize port map (
      in1       => resbusm_raw,
      truncated => '0',
      result    => resbusm,
      inf       => open,
      zero      => open
      );
    posit_normalize_il_es2 : posit_normalize port map (
      in1       => resbusi_raw,
      truncated => '0',
      result    => resbusi,
      inf       => open,
      zero      => open
      );
  end generate;
  gen_normalize_es3 : if POSIT_ES = 3 generate
    posit_normalize_ml_es3 : posit_normalize_es3 port map (
      in1       => resbusm_raw,
      truncated => '0',
      result    => resbusm,
      inf       => open,
      zero      => open
      );
    posit_normalize_il_es3 : posit_normalize_es3 port map (
      in1       => resbusi_raw,
      truncated => '0',
      result    => resbusi,
      inf       => open,
      zero      => open
      );
  end generate;

  -- pe_out_0_mids_ml_normalize : posit_normalize port map (
  --   in1       => pe_outs(0).mids.ml,
  --   result    => pe_out_mids_ml,
  --   truncated => '0',
  --   inf       => open,
  --   zero      => open
  --   );
  --
  -- pe_out_0_mids_il_normalize : posit_normalize port map (
  --   in1       => pe_outs(0).mids.il,
  --   result    => pe_out_mids_il,
  --   truncated => '0',
  --   inf       => open,
  --   zero      => open
  --   );

  -- Result bus
  process(cr.clk)
    variable vbusm                : value;
    variable vbusi                : value;
    variable m_nonzero, i_nonzero : std_logic := '0';
  begin
    if rising_edge(cr.clk) then
      -- Go over all PEs
      for K in 0 to PAIRHMM_NUM_PES-1 loop
        -- If its output is at the bottom
        if (pe_outs(K).cell = PE_BOTTOM    -- add when it's bottom PE
            or pe_outs(K).cell = PE_LAST)  -- or last PE
          and pe_outs(K).y /= BP_STOP  -- but not when the PE is bypassing in the horizontal direction
        then
          resm(K) <= pe_outs(K).mids.ml;
          resi(K) <= pe_outs(K).mids.il;
        else
          resm(K) <= value_empty;
          resi(K) <= value_empty;
        end if;
      end loop;

      -- OR everything, latency is 1
      m_nonzero := '0';
      i_nonzero := '0';

      vbusm := (others => '0');
      vbusi := (others => '0');
      for K in 0 to PAIRHMM_NUM_PES-1 loop
        if resm(K)(0) /= '1' then       -- OR if nonzero
          m_nonzero := '1';
          vbusm     := vbusm or resm(K);
        end if;

        if resi(K)(0) /= '1' then       -- OR if nonzero
          i_nonzero := '1';
          vbusi     := vbusi or resi(K);
        end if;
      end loop;

      -- Place on bus, latency is 2
      if m_nonzero = '1' then
        resbusm_raw <= vbusm;
      else
        resbusm_raw <= value_empty;
      end if;

      if i_nonzero = '1' then
        resbusi_raw <= vbusi;
      else
        resbusi_raw <= value_empty;
      end if;

      -- Check if last PE is at last cell update
      if pe_outs(PAIRHMM_NUM_PES-1).cell = PE_LAST then lastlast <= '1';
      else lastlast                                              <= '0';
      end if;

      lastlast1 <= lastlast;            -- match latency of 2
    end if;
  end process;

  gen_accumulator_wide : if POSIT_WIDE_ACCUMULATOR = 1 generate
    signal resaccum_out                               : prob;
    signal resaccum_out_raw                           : value_prod_sum;
    signal resaccum_out_valid, resaccum_out_truncated : std_logic;

    signal res_acc_zero : std_logic;

    type i_delay_type is array (0 to 4 * PE_ADD_CYCLES - 1) of value_product;
    signal i_delay       : i_delay_type;
    signal i_valid_delay : std_logic_vector(5 * PE_ADD_CYCLES - 1 downto 0);

    signal acc : acc_state_wide := resetting;

    signal addm_addi_valid : std_logic;
  begin
    addm_addi_valid <= addm_out_valid and addi_out_valid;

    gen_es2_add : if POSIT_ES = 2 generate
      resaccum_m : positaccum_16_raw port map (
        clk    => cr.clk,
        rst    => res_rst,
        in1    => resbusm_raw,
        start  => '1',
        result => addm_out_raw,
        done   => addm_out_valid
        );
      resaccum_i : positaccum_16_raw port map (
        clk    => cr.clk,
        rst    => res_rst,
        in1    => resbusi_raw,
        start  => '1',
        result => addi_out_raw,
        done   => addi_out_valid
        );
      resaccum : positadd_prod_4_raw port map (
        clk       => cr.clk,
        in1       => i_delay(4 * PE_ADD_CYCLES - 1),
        in2       => accum2prod(addm_out_raw),
        start     => addm_addi_valid,
        result    => resaccum_out_raw,
        done      => resaccum_out_valid,
        truncated => resaccum_out_truncated
        );
    end generate;
    gen_es3_add : if POSIT_ES = 3 generate
      resaccum_m : positaccum_16_raw_es3 port map (
        clk    => cr.clk,
        rst    => res_rst,
        in1    => resbusm_raw,
        start  => '1',
        result => addm_out_raw,
        done   => addm_out_valid
        );
      resaccum_i : positaccum_16_raw_es3 port map (
        clk    => cr.clk,
        rst    => res_rst,
        in1    => resbusi_raw,
        start  => '1',
        result => addi_out_raw,
        done   => addi_out_valid
        );
      resaccum : positadd_prod_4_raw_es3 port map (
        clk       => cr.clk,
        in1       => i_delay(4 * PE_ADD_CYCLES - 1),
        in2       => accum2prod(addm_out_raw),
        start     => addm_addi_valid,
        result    => resaccum_out_raw,
        done      => resaccum_out_valid,
        truncated => resaccum_out_truncated
        );
    end generate;

    -- posit_normalize_1 : posit_normalize port map (
    --   in1       => accum2val(addm_out_raw),
    --   truncated => '0',
    --   result    => addm_out,
    --   inf       => open,
    --   zero      => open
    --   );
    -- posit_normalize_2 : posit_normalize port map (
    --   in1       => accum2val(addi_out_raw),
    --   truncated => '0',
    --   result    => addi_out,
    --   inf       => open,
    --   zero      => open
    --   );
    -- posit_normalize_3 : posit_normalize port map (
    --   in1       => prodsum2val(resaccum_out_raw),
    --   truncated => resaccum_out_truncated,
    --   result    => resaccum_out,
    --   inf       => open,
    --   zero      => open
    --   );

    process(cr.clk)
      variable rescounter   : integer range 0 to PE_DEPTH + PE_ADD_CYCLES := 0;
      variable accumcounter : integer range 0 to 4 * PE_ADD_CYCLES - 1    := 0;
      variable prevlast     : std_logic;
    begin
      if rising_edge(cr.clk) then
        if cr.rst = '1' then
          acc           <= resetting;
          o.score_valid <= '0';
          res_rst       <= '1';
          rescounter    := 0;
        else
          -- Delayed signals:
          i_delay(0) <= accum2prod(addi_out_raw);
          for K in 1 to 4 * PE_ADD_CYCLES - 1 loop
            i_delay(K) <= i_delay(K-1);
          end loop;

          i_valid_delay(0) <= lastlast1;
          for K in 1 to 5 * PE_ADD_CYCLES - 1 loop
            i_valid_delay(K) <= i_valid_delay(K-1);
          end loop;

          case acc is
            when adding =>
              res_rst      <= '0';
              res_acc_zero <= '0';
              if lastlast = '0' and prevlast = '1' then
                acc <= accumulating;
              end if;

            when accumulating =>
              accumcounter := accumcounter + 1;
              res_rst      <= '0';
              res_acc_zero <= '0';
              if accumcounter = 4 * PE_ADD_CYCLES - 1 then
                accumcounter := 0;
                acc          <= reset_accumulator;
              end if;

            when reset_accumulator =>
              rescounter   := rescounter + 1;
              res_rst      <= '1';
              res_acc_zero <= '0';
              acc          <= resetting;

            when resetting =>
              rescounter   := rescounter + 1;
              res_rst      <= '0';
              res_acc_zero <= '0';
              if rescounter >= PE_ADD_CYCLES + 1 then
                res_acc_zero <= '1';
              end if;
              if rescounter = PE_DEPTH then
                rescounter := 0;
                acc        <= adding;
              end if;

          end case;

          prevlast := lastlast1;

          o.score       <= res_acc;
          o.score_valid <= i_valid_delay(5 * PE_ADD_CYCLES - 1);
        end if;
      end if;
    end process;

    gen_accum_normalize_es2 : if POSIT_ES = 2 generate
      posit_normalize_accum_es2 : posit_normalize_prod_sum port map (
        in1       => resaccum_out_raw,
        truncated => resaccum_out_truncated,
        result    => resaccum_out,
        inf       => open,
        zero      => open
        );
    end generate;
    gen_accum_normalize_es3 : if POSIT_ES = 3 generate
      posit_normalize_accum_es3 : posit_normalize_prod_sum_es3 port map (
        in1       => resaccum_out_raw,
        truncated => resaccum_out_truncated,
        result    => resaccum_out,
        inf       => open,
        zero      => open
        );
    end generate;

    res_acc <= resaccum_out when res_acc_zero = '0' else
               (others => '0');
  end generate;

end architecture logic;
