---------------------------------------------------------------------------------------------------
--    _____      _      _    _ __  __ __  __
--   |  __ \    (_)    | |  | |  \/  |  \/  |
--   | |__) |_ _ _ _ __| |__| | \  / | \  / |
--   |  ___/ _` | | '__|  __  | |\/| | |\/| |
--   | |  | (_| | | |  | |  | | |  | | |  | |
--   |_|   \__,_|_|_|  |_|  |_|_|  |_|_|  |_|
---------------------------------------------------------------------------------------------------
-- Processing Element
---------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.functions.all;
use work.posit_common.all;
use work.pe_package.all;                -- Posit configuration specific

entity pe is
  generic (
    FIRST           : std_logic := '0';  -- Not first processing element by default
    DISABLE_THETA   : std_logic := '1';  -- Theta is disabled by default
    DISABLE_UPSILON : std_logic := '1'  -- Upsilon is disabled by default
    );
  port (
    cr : in  cr_in;
    i  : in  pe_in;
    o  : out pe_out
    );
end pe;

architecture rtl of pe is
  -- Intermediate signals
  signal step     : step_type;
  signal step_raw : step_raw_type;

  -- Shift Registers (SRs)
  signal initial_sr : initial_array_pe_raw    := (others => value_empty);
  signal mids_sr    : mids_raw_array          := (others => mids_raw_empty);
  signal tmis_sr    : transmissions_raw_array := (others => tmis_raw_empty);
  signal emis_sr    : emissions_raw_array     := (others => emis_raw_empty);
  signal valid_sr   : valid_array             := (others => '0');
  signal cell_sr    : cell_array              := (others => PE_NORMAL);
  signal x_sr       : bps                     := bps_empty;
  signal y_sr       : bps                     := bps_empty;

  -- To select the right input for the last Mult
  signal distm : value;

  -- Potential outputs depening on basepairs:
  signal o_normal : pe_out;
  signal o_bypass : pe_out;
  signal o_buf    : pe_out;

  -- Gamma delay SR to match the delay of alpha + beta adder
  type add_gamma_sr_type is array (0 to PE_ADD_CYCLES - 1) of value_product;
  signal add_gamma_sr : add_gamma_sr_type := (others => value_product_empty);

  type mul_sr_type is array (0 to PE_MUL_CYCLES - 1) of value_prod_sum;
  signal mul_theta_sr             : mul_sr_type                                := (others => value_prod_sum_empty);
  signal mul_theta_truncated_sr   : std_logic_vector(PE_MUL_CYCLES-1 downto 0) := (others => '0');
  signal mul_upsilon_sr           : mul_sr_type                                := (others => value_prod_sum_empty);
  signal mul_upsilon_truncated_sr : std_logic_vector(PE_MUL_CYCLES-1 downto 0) := (others => '0');

  type fp_valids_type is array (0 to 13) of std_logic;
  signal fp_valids : fp_valids_type;

  signal posit_norm : step_type := step_type_init;

  signal distm_norm, emult_m_val, mul_theta_val, mul_upsilon_val, add_albetl_val, initial_val : std_logic_vector(31 downto 0);
  signal posit_truncated                                                                      : std_logic_vector(10 downto 0) := (others => '0');
  signal mids_ml, mids_il, mids_dl, add_albetl                                                : value                         := value_empty;
begin

  ---------------------------------------------------------------------------------------------------
  --    _____                   _
  --   |_   _|                 | |
  --     | |  _ __  _ __  _   _| |_ ___
  --     | | | '_ \| '_ \| | | | __/ __|
  --    _| |_| | | | |_) | |_| | |_\__ \
  --   |_____|_| |_| .__/ \__,_|\__|___/
  --               | |
  --               |_|
  ---------------------------------------------------------------------------------------------------

  gen_es2_normalize_initial : if POSIT_ES = 2 generate
    normalize_initial_es2 : posit_normalize port map (
      in1       => i.initial,
      truncated => '0',
      result    => initial_val,
      inf       => open,
      zero      => open
      );
  end generate;
  gen_es3_normalize_initial : if POSIT_ES = 3 generate
    normalize_initial_es3 : posit_normalize port map (
      in1       => i.initial,
      truncated => '0',
      result    => initial_val,
      inf       => open,
      zero      => open
      );
  end generate;

  step_raw.init.valid <= i.valid;
  step_raw.init.cell  <= i.cell;

  step_raw.init.initial <= i.initial;

  step_raw.init.x <= i.x;
  step_raw.init.y <= i.y;

  step_raw.init.tmis <= i.tmis;
  step_raw.init.emis <= i.emis;

  ----------------------------------------------------------------------------------------------------------------------- Coming from the left
  step_raw.init.mids.ml <= i.mids.ml when i.x /= BP_STOP else o_buf.mids.ml;  -- or own output when x is stop
  step_raw.init.mids.il <= i.mids.il when i.x /= BP_STOP else o_buf.mids.il;  -- or own output when x is stop
  step_raw.init.mids.dl <= i.mids.dl;

  ----------------------------------------------------------------------------------------------------------------------- Coming from the top
  -- All top inputs can be potentially zero when working on the first row of the matrix
  -- step_raw.init.mids.mt <= prod2val(step_raw.emult.m) when i.cell /= PE_TOP else value_empty;
  step.init.mids.mt <= emult_m_val when i.cell /= PE_TOP else (others => '0');
  gen_es2_extract_mt : if POSIT_ES = 2 generate
    extract_mt_es2 : posit_extract_raw port map (
      in1      => step.init.mids.mt,
      absolute => open,
      result   => step_raw.init.mids.mt
      );
  end generate;
  gen_es3_extract_mt : if POSIT_ES = 3 generate
    extract_mt_es3 : posit_extract_raw_es3 port map (
      in1      => step.init.mids.mt,
      absolute => open,
      result   => step_raw.init.mids.mt
      );
  end generate;

  gen_normalize_emult_m_es2 : if POSIT_ES = 2 generate
    posit_normalize_ml_distm : posit_normalize_product_prod_sum_sum port map (
      in1       => step_raw.emult.m,
      result    => emult_m_val,
      truncated => posit_truncated(4),
      inf       => open,
      zero      => open
      );
  end generate;
  gen_normalize_emult_m_es3 : if POSIT_ES = 3 generate
    posit_normalize_ml_distm : posit_normalize_product_prod_sum_sum_es3 port map (
      in1       => step_raw.emult.m,
      result    => emult_m_val,
      truncated => posit_truncated(4),
      inf       => open,
      zero      => open
      );
  end generate;

  gen_normalize_emult_i_es2 : if POSIT_ES = 2 generate
    posit_normalize_mul_theta : posit_normalize_prod_sum port map (
      in1       => mul_theta_sr(PE_MUL_CYCLES-1),
      result    => mul_theta_val,
      truncated => mul_theta_truncated_sr(PE_MUL_CYCLES-1),
      inf       => open,
      zero      => open
      );
  end generate;
  gen_normalize_emult_i_es3 : if POSIT_ES = 3 generate
    posit_normalize_mul_theta : posit_normalize_prod_sum_es3 port map (
      in1       => mul_theta_sr(PE_MUL_CYCLES-1),
      result    => mul_theta_val,
      truncated => mul_theta_truncated_sr(PE_MUL_CYCLES-1),
      inf       => open,
      zero      => open
      );
  end generate;

  gen_normalize_upsilon_es2 : if POSIT_ES = 2 generate
    posit_normalize_mul_upsilon : posit_normalize_prod_sum port map (
      in1       => mul_upsilon_sr(PE_MUL_CYCLES-1),
      truncated => mul_upsilon_truncated_sr(PE_MUL_CYCLES-1),
      result    => mul_upsilon_val,
      inf       => open,
      zero      => open
      );
  end generate;
  gen_normalize_upsilon_es3 : if POSIT_ES = 3 generate
    posit_normalize_mul_upsilon : posit_normalize_prod_sum_es3 port map (
      in1       => mul_upsilon_sr(PE_MUL_CYCLES-1),
      truncated => mul_upsilon_truncated_sr(PE_MUL_CYCLES-1),
      result    => mul_upsilon_val,
      inf       => open,
      zero      => open
      );
  end generate;

  -- gen_normalize_gamma_es2 : if POSIT_ES = 2 generate
  --   posit_normalize_add_gamma : posit_normalize_prod port map (
  --     in1       => add_gamma_sr(PE_ADD_CYCLES-1),
  --     result    => add_gamma_val,
  --     truncated => '0',
  --     inf       => open,
  --     zero      => open
  --     );
  -- end generate;
  -- gen_normalize_gamma_es3 : if POSIT_ES = 3 generate
  --   posit_normalize_add_gamma : posit_normalize_prod_es3 port map (
  --     in1       => add_gamma_sr(PE_ADD_CYCLES-1),
  --     result    => add_gamma_val,
  --     truncated => '0',
  --     inf       => open,
  --     zero      => open
  --     );
  -- end generate;

  gen_normalize_albetl_es2 : if POSIT_ES = 2 generate
    posit_normalize_add_albetl : posit_normalize_prod_sum port map (
      in1       => step_raw.add.albetl,
      result    => step.add.albetl,
      truncated => posit_truncated(0),
      inf       => open,
      zero      => open
      );
  end generate;
  gen_normalize_albetl_es3 : if POSIT_ES = 3 generate
    posit_normalize_add_albetl : posit_normalize_prod_sum_es3 port map (
      in1       => step_raw.add.albetl,
      result    => step.add.albetl,
      truncated => posit_truncated(0),
      inf       => open,
      zero      => open
      );
  end generate;

  -- step_raw.init.mids.it <= prodsum2val(mul_theta_sr(PE_MUL_CYCLES-1))   when i.cell /= PE_TOP else value_empty;
  step.init.mids.it <= mul_theta_val when i.cell /= PE_TOP else (others => '0');
  gen_es2_extract_it : if POSIT_ES = 2 generate
    extract_it_es2 : posit_extract_raw port map (
      in1      => step.init.mids.it,
      absolute => open,
      result   => step_raw.init.mids.it
      );
  end generate;
  gen_es3_extract_it : if POSIT_ES = 3 generate
    extract_it_es3 : posit_extract_raw_es3 port map (
      in1      => step.init.mids.it,
      absolute => open,
      result   => step_raw.init.mids.it
      );
  end generate;

  -- step_raw.init.mids.dt <= prodsum2val(mul_upsilon_sr(PE_MUL_CYCLES-1)) when i.cell /= PE_TOP else i.initial;
  step.init.mids.dt <= mul_upsilon_val when i.cell /= PE_TOP else initial_val;
  gen_es2_extract_dt : if POSIT_ES = 2 generate
    extract_dt_es2 : posit_extract_raw port map (
      in1      => step.init.mids.dt,
      absolute => open,
      result   => step_raw.init.mids.dt
      );
  end generate;
  gen_es3_extract_dt : if POSIT_ES = 3 generate
    extract_dt_es3 : posit_extract_raw_es3 port map (
      in1      => step.init.mids.dt,
      absolute => open,
      result   => step_raw.init.mids.dt
      );
  end generate;


----------------------------------------------------------------------------------------------------------------------- Coming from the top left
  -- Initial Signal for top left; if this is the First PE we get M,I,D [i-1][j-1] from the inputs
  ISF : if FIRST = '1' generate
    step_raw.init.mids.mtl <= mids_sr(PE_CYCLES-1).ml when i.cell /= PE_TOP else i.mids.mtl;
    step_raw.init.mids.itl <= mids_sr(PE_CYCLES-1).il when i.cell /= PE_TOP else i.mids.itl;
  end generate;
  -- Initial Signal; if this is Not the First PE we get M,I,D [i-1][j-1] from the shift registers
  ISNF : if FIRST /= '1' generate
    step_raw.init.mids.mtl <= mids_sr(PE_CYCLES-1).ml when i.cell /= PE_TOP else value_empty;
    step_raw.init.mids.itl <= mids_sr(PE_CYCLES-1).il when i.cell /= PE_TOP else value_empty;
  end generate;

  -- Initial Signal for D:
  step_raw.init.mids.dtl <= mids_sr(PE_CYCLES-1).dl when i.cell /= PE_TOP else i.initial;


  ---------------------------------------------------------------------------------------------------
  --     _____ _               __     __  __       _ _   _       _ _           _   _
  --    / ____| |             /_ |_  |  \/  |     | | | (_)     | (_)         | | (_)
  --   | (___ | |_ ___ _ __    | (_) | \  / |_   _| | |_ _ _ __ | |_  ___ __ _| |_ _  ___  _ __  ___
  --    \___ \| __/ _ \ '_ \   | |   | |\/| | | | | | __| | '_ \| | |/ __/ _` | __| |/ _ \| '_ \/ __|
  --    ____) | ||  __/ |_) |  | |_  | |  | | |_| | | |_| | |_) | | | (_| (_| | |_| | (_) | | | \__ \
  --   |_____/ \__\___| .__/   |_(_) |_|  |_|\__,_|_|\__|_| .__/|_|_|\___\__,_|\__|_|\___/|_| |_|___/
  --                  | |                                 | |
  --                  |_|                                 |_|
  ---------------------------------------------------------------------------------------------------
  -- Transmission probabilties multiplied with M, D, I
  --
  -- 4 CYCLES
  ---------------------------------------------------------------------------------------------------

  gen_es2_mul_alpha : if POSIT_ES = 2 generate
    mul_alpha : positmult_4_raw port map (
      clk    => cr.clk,
      in1    => step_raw.init.tmis.alpha,
      in2    => step_raw.init.mids.mtl,
      start  => step.init.valid,
      result => step_raw.trans.almtl,
      done   => fp_valids(0)
      );
  end generate;
  gen_es3_mul_alpha : if POSIT_ES = 3 generate
    mul_alpha : positmult_4_raw_es3 port map (
      clk    => cr.clk,
      in1    => step_raw.init.tmis.alpha,
      in2    => step_raw.init.mids.mtl,
      start  => step.init.valid,
      result => step_raw.trans.almtl,
      done   => fp_valids(0)
      );
  end generate;

  gen_es2_mul_beta : if POSIT_ES = 2 generate
    mul_beta : positmult_4_raw port map (
      clk    => cr.clk,
      in1    => step_raw.init.tmis.beta,
      in2    => step_raw.init.mids.itl,
      start  => step_raw.init.valid,
      result => step_raw.trans.beitl,
      done   => fp_valids(1)
      );
  end generate;
  gen_es3_mul_beta : if POSIT_ES = 3 generate
    mul_beta : positmult_4_raw_es3 port map (
      clk    => cr.clk,
      in1    => step_raw.init.tmis.beta,
      in2    => step_raw.init.mids.itl,
      start  => step_raw.init.valid,
      result => step_raw.trans.beitl,
      done   => fp_valids(1)
      );
  end generate;

  gen_es2_mul_gamma : if POSIT_ES = 2 generate
    mul_gamma : positmult_4_raw port map (
      clk    => cr.clk,
      in1    => step_raw.init.tmis.beta,
      in2    => step_raw.init.mids.dtl,
      start  => step_raw.init.valid,
      result => step_raw.trans.gadtl,
      done   => fp_valids(2)
      );
  end generate;
  gen_es3_mul_gamma : if POSIT_ES = 3 generate
    mul_gamma : positmult_4_raw_es3 port map (
      clk    => cr.clk,
      in1    => step_raw.init.tmis.beta,
      in2    => step_raw.init.mids.dtl,
      start  => step_raw.init.valid,
      result => step_raw.trans.gadtl,
      done   => fp_valids(2)
      );
  end generate;

  gen_es2_mul_delta : if POSIT_ES = 2 generate
    mul_delta : positmult_4_raw port map (
      clk    => cr.clk,
      in1    => step_raw.init.tmis.delta,
      in2    => step_raw.init.mids.mt,
      start  => step_raw.init.valid,
      result => step_raw.trans.demt,
      done   => fp_valids(3)
      );
  end generate;
  gen_es3_mul_delta : if POSIT_ES = 3 generate
    mul_delta : positmult_4_raw_es3 port map (
      clk    => cr.clk,
      in1    => step_raw.init.tmis.delta,
      in2    => step_raw.init.mids.mt,
      start  => step_raw.init.valid,
      result => step_raw.trans.demt,
      done   => fp_valids(3)
      );
  end generate;

  gen_es2_mul_epsilon : if POSIT_ES = 2 generate
    mul_epsilon : positmult_4_raw port map (
      clk    => cr.clk,
      in1    => step_raw.init.tmis.epsilon,
      in2    => step_raw.init.mids.it,
      start  => step_raw.init.valid,
      result => step_raw.trans.epit,
      done   => fp_valids(4)
      );
  end generate;
  gen_es3_mul_epsilon : if POSIT_ES = 3 generate
    mul_epsilon : positmult_4_raw_es3 port map (
      clk    => cr.clk,
      in1    => step_raw.init.tmis.epsilon,
      in2    => step_raw.init.mids.it,
      start  => step_raw.init.valid,
      result => step_raw.trans.epit,
      done   => fp_valids(4)
      );
  end generate;

  gen_es2_mul_zeta : if POSIT_ES = 2 generate
    mul_zeta : positmult_4_raw port map (
      clk    => cr.clk,
      in1    => step_raw.init.tmis.zeta,
      in2    => step_raw.init.mids.ml,
      start  => step_raw.init.valid,
      result => step_raw.trans.zeml,
      done   => fp_valids(5)
      );
  end generate;
  gen_es3_mul_zeta : if POSIT_ES = 3 generate
    mul_zeta : positmult_4_raw_es3 port map (
      clk    => cr.clk,
      in1    => step_raw.init.tmis.zeta,
      in2    => step_raw.init.mids.ml,
      start  => step_raw.init.valid,
      result => step_raw.trans.zeml,
      done   => fp_valids(5)
      );
  end generate;

  gen_es2_mul_eta : if POSIT_ES = 2 generate
    mul_eta : positmult_4_raw port map (
      clk    => cr.clk,
      in1    => step_raw.init.tmis.eta,
      in2    => step_raw.init.mids.dl,
      start  => step_raw.init.valid,
      result => step_raw.trans.etdl,
      done   => fp_valids(6)
      );
  end generate;
  gen_es3_mul_eta : if POSIT_ES = 3 generate
    mul_eta : positmult_4_raw_es3 port map (
      clk    => cr.clk,
      in1    => step_raw.init.tmis.eta,
      in2    => step_raw.init.mids.dl,
      start  => step_raw.init.valid,
      result => step_raw.trans.etdl,
      done   => fp_valids(6)
      );
  end generate;

  ---------------------------------------------------------------------------------------------------
  --     _____ _               ___                  _     _ _ _   _
  --    / ____| |             |__ \ _      /\      | |   | (_) | (_)
  --   | (___ | |_ ___ _ __      ) (_)    /  \   __| | __| |_| |_ _  ___  _ __  ___
  --    \___ \| __/ _ \ '_ \    / /      / /\ \ / _` |/ _` | | __| |/ _ \| '_ \/ __|
  --    ____) | ||  __/ |_) |  / /_ _   / ____ \ (_| | (_| | | |_| | (_) | | | \__ \
  --   |_____/ \__\___| .__/  |____(_) /_/    \_\__,_|\__,_|_|\__|_|\___/|_| |_|___/
  --                  | |
  --                  |_|
  ---------------------------------------------------------------------------------------------------
  -- Addition of the multiplied probabilities
  --
  -- 8 CYCLES
  ---------------------------------------------------------------------------------------------------

  -- BEGIN alpha + beta + delayed gamma
  -- Substep adding alpha + beta
  gen_es2_add_alpha_beta : if POSIT_ES = 2 generate
    add_alpha_beta : positadd_prod_4_raw port map (
      clk       => cr.clk,
      in1       => step_raw.trans.almtl,
      in2       => step_raw.trans.beitl,
      start     => step_raw.init.valid,
      result    => step_raw.add.albetl,
      done      => fp_valids(7),
      truncated => posit_truncated(0)
      );
  end generate;
  gen_es3_add_alpha_beta : if POSIT_ES = 3 generate
    add_alpha_beta : positadd_prod_4_raw port map (
      clk       => cr.clk,
      in1       => step_raw.trans.almtl,
      in2       => step_raw.trans.beitl,
      start     => step_raw.init.valid,
      result    => step_raw.add.albetl,
      done      => fp_valids(7),
      truncated => posit_truncated(0)
      );
  end generate;

  -- Substep adding alpha + beta + delayed gamma
  gen_es2_add_alpha_beta_gamma : if POSIT_ES = 2 generate
    add_alpha_beta_gamma : positadd_4_truncated_prodsum_raw port map (
      clk           => cr.clk,
      in1           => step_raw.add.albetl,
      in1_truncated => posit_truncated(0),
      in2           => prod2prodsum(add_gamma_sr(PE_ADD_CYCLES-1)),
      in2_truncated => '0',
      start         => step_raw.init.valid,
      result        => step_raw.add.albegatl,
      done          => fp_valids(8),
      truncated     => posit_truncated(1)
      );
  -- : positadd_4_raw port map (
  --  clk       => cr.clk,
  --  in1       => add_albetl,
  --  in2       => add_gamma,
  --  start     => step_raw.init.valid,
  --  result    => step_raw.add.albegatl,
  --  done      => fp_valids(8),
  --  truncated => posit_truncated(1)
  --  );
  end generate;
  gen_es3_add_alpha_beta_gamma : if POSIT_ES = 3 generate
    add_alpha_beta_gamma : positadd_4_truncated_prodsum_raw_es3 port map (
      clk           => cr.clk,
      in1           => step_raw.add.albetl,
      in1_truncated => posit_truncated(0),
      in2           => prod2prodsum(add_gamma_sr(PE_ADD_CYCLES-1)),
      in2_truncated => '0',
      start         => step_raw.init.valid,
      result        => step_raw.add.albegatl,
      done          => fp_valids(8),
      truncated     => posit_truncated(1)
      );
  end generate;
  -- END alpha + beta + delayed gamma


  gen_es2_add_delta_epsilon : if POSIT_ES = 2 generate
    add_delta_epsilon : positadd_prod_8_raw port map (
      clk       => cr.clk,
      in1       => step_raw.trans.demt,
      in2       => step_raw.trans.epit,
      start     => step_raw.init.valid,
      result    => step_raw.add.deept,
      done      => fp_valids(9),
      truncated => posit_truncated(2)
      );
  end generate;
  gen_es3_add_delta_epsilon : if POSIT_ES = 3 generate
    add_delta_epsilon : positadd_prod_8_raw_es3 port map (
      clk       => cr.clk,
      in1       => step_raw.trans.demt,
      in2       => step_raw.trans.epit,
      start     => step_raw.init.valid,
      result    => step_raw.add.deept,
      done      => fp_valids(9),
      truncated => posit_truncated(2)
      );
  end generate;

  gen_es2_add_zeta_eta : if POSIT_ES = 2 generate
    add_zeta_eta : positadd_prod_8_raw port map (
      clk       => cr.clk,
      in1       => step_raw.trans.zeml,
      in2       => step_raw.trans.etdl,
      start     => step_raw.init.valid,
      result    => step_raw.add.zeett,
      done      => fp_valids(10),
      truncated => posit_truncated(3)
      );
  end generate;
  gen_es3_add_zeta_eta : if POSIT_ES = 3 generate
    add_zeta_eta : positadd_prod_8_raw_es3 port map (
      clk       => cr.clk,
      in1       => step_raw.trans.zeml,
      in2       => step_raw.trans.etdl,
      start     => step_raw.init.valid,
      result    => step_raw.add.zeett,
      done      => fp_valids(10),
      truncated => posit_truncated(3)
      );
  end generate;


  ---------------------------------------------------------------------------------------------------
  --     _____ _               ____      __  __       _ _   _       _ _           _   _
  --    / ____| |             |___ \ _  |  \/  |     | | | (_)     | (_)         | | (_)
  --   | (___ | |_ ___ _ __     __) (_) | \  / |_   _| | |_ _ _ __ | |_  ___ __ _| |_ _  ___  _ __  ___
  --    \___ \| __/ _ \ '_ \   |__ <    | |\/| | | | | | __| | '_ \| | |/ __/ _` | __| |/ _ \| '_ \/ __|
  --    ____) | ||  __/ |_) |  ___) |_  | |  | | |_| | | |_| | |_) | | | (_| (_| | |_| | (_) | | | \__ \
  --   |_____/ \__\___| .__/  |____/(_) |_|  |_|\__,_|_|\__|_| .__/|_|_|\___\__,_|\__|_|\___/|_| |_|___/
  --                  | |                                    | |
  --                  |_|                                    |_|
  ---------------------------------------------------------------------------------------------------
  -- Step 3: Multiplication of the emission probabilities
  --
  -- 4 CYCLES
  ---------------------------------------------------------------------------------------------------

  -- Mux for the final multiplication
  -- Select correct emission probability (distm) depending on read
  process(step_raw, y_sr, x_sr)
  begin
    if y_sr(PE_BCC-1) = x_sr(PE_BCC-1) or y_sr(PE_BCC-1) = BP_N or x_sr(PE_BCC-1) = BP_N
    then
      distm <= step_raw.add.emis.distm_simi;
    else
      distm <= step_raw.add.emis.distm_diff;
    end if;
  end process;

  gen_es2_mul_lambda : if POSIT_ES = 2 generate
    mul_lambda : positmult_4_truncated_raw_prodsumsum port map (
      clk           => cr.clk,
      in1           => step_raw.add.albegatl,
      in1_truncated => posit_truncated(1),
      in2           => val2prodsumsum(distm),
      in2_truncated => '0',
      start         => step_raw.init.valid,
      result        => step_raw.emult.m,
      done          => fp_valids(11),
      truncated     => posit_truncated(4)
      );
  end generate;
  gen_es3_mul_lambda : if POSIT_ES = 3 generate
    mul_lambda : positmult_4_truncated_raw_prodsumsum_es3 port map (
      clk           => cr.clk,
      in1           => step_raw.add.albegatl,
      in1_truncated => posit_truncated(1),
      in2           => val2prodsumsum(distm),
      in2_truncated => '0',
      start         => step_raw.init.valid,
      result        => step_raw.emult.m,
      done          => fp_valids(11),
      truncated     => posit_truncated(4)
      );
  end generate;

  fp_valids(12) <= '1';
  fp_valids(13) <= '1';

  ---------------------------------------------------------------------------------------------------
  --    ____         __  __
  --   |  _ \       / _|/ _|
  --   | |_) |_   _| |_| |_ ___ _ __ ___
  --   |  _ <| | | |  _|  _/ _ \ '__/ __|
  --   | |_) | |_| | | | ||  __/ |  \__ \
  --   |____/ \__,_|_| |_| \___|_|  |___/
  ---------------------------------------------------------------------------------------------------
  -- Shift register for gamma to match the latency of alpha+beta adder
  ---------------------------------------------------------------------------------------------------
  add_gamma_shift_reg : process(cr.clk)
  begin
    if rising_edge(cr.clk) then
      if cr.rst = '1' then
        -- Reset shift register:
        add_gamma_sr <= (others => value_product_empty);
      else
        add_gamma_sr(0) <= step_raw.trans.gadtl;
        -- Shifts:
        for I in 1 to PE_ADD_CYCLES-1 loop
          add_gamma_sr(I) <= add_gamma_sr(I-1);
        end loop;
      end if;
    end if;
  end process;

  ---------------------------------------------------------------------------------------------------
  -- Shift register to match the latency of the lambda multiplier in case theta and upsilon
  -- are always 1.0
  ---------------------------------------------------------------------------------------------------

  skip_mul_theta_sr : process(cr.clk)
  begin
    if rising_edge(cr.clk) then
      if cr.rst = '1' then
        -- Reset shift register:
        mul_theta_sr           <= (others => value_prod_sum_empty);
        mul_theta_truncated_sr <= (others => '0');
      else
        mul_theta_sr(0)           <= step_raw.add.deept;
        mul_theta_truncated_sr(0) <= posit_truncated(2);
        -- Shifts:
        for I in 1 to PE_MUL_CYCLES-1 loop
          mul_theta_sr(I)           <= mul_theta_sr(I-1);
          mul_theta_truncated_sr(I) <= mul_theta_truncated_sr(I-1);
        end loop;
      end if;
    end if;
  end process;

  skip_mul_upsilon_sr : process(cr.clk)
  begin
    if rising_edge(cr.clk) then
      if cr.rst = '1' then
        -- Reset shift register:
        mul_upsilon_sr           <= (others => value_prod_sum_empty);
        mul_upsilon_truncated_sr <= (others => '0');
      else
        mul_upsilon_sr(0)           <= step_raw.add.zeett;
        mul_upsilon_truncated_sr(0) <= posit_truncated(3);
        -- Shifts:
        for I in 1 to PE_MUL_CYCLES-1 loop
          mul_upsilon_sr(I)           <= mul_upsilon_sr(I-1);
          mul_upsilon_truncated_sr(I) <= mul_upsilon_truncated_sr(I-1);
        end loop;
      end if;
    end if;
  end process;

  ---------------------------------------------------------------------------------------------------
  -- Shift register to do the following:
  -- *  Delay the transmission and emission probabilities to insert them in the proper cycle.
  -- *  Delay the M, I and D from the top left cell with one full iteration.
  ---------------------------------------------------------------------------------------------------
  constants_shift : process(cr.clk)
  begin
    if rising_edge(cr.clk) then
      if cr.rst = '1' then
        -- Reset shift register:
        initial_sr <= (others => value_empty);
        mids_sr    <= (others => mids_raw_empty);
        tmis_sr    <= (others => tmis_raw_empty);
        emis_sr    <= (others => emis_raw_empty);
        valid_sr   <= (others => '0');
        cell_sr    <= (others => PE_NORMAL);
        x_sr       <= bps_empty;
        y_sr       <= bps_empty;
      else
        initial_sr(0) <= step_raw.init.initial;
        mids_sr(0)    <= step_raw.init.mids;
        tmis_sr(0)    <= step_raw.init.tmis;
        emis_sr(0)    <= step_raw.init.emis;

        valid_sr(0) <= step_raw.init.valid;
        cell_sr(0)  <= step_raw.init.cell;
        x_sr(0)     <= step_raw.init.x;
        y_sr(0)     <= step_raw.init.y;

        -- Shifts:
        for I in 1 to PE_CYCLES-1 loop
          initial_sr(I) <= initial_sr(I-1);
          mids_sr(I)    <= mids_sr(I-1);
          tmis_sr(I)    <= tmis_sr(I-1);
          emis_sr(I)    <= emis_sr(I-1);

          valid_sr(I) <= valid_sr(I-1);
          cell_sr(I)  <= cell_sr(I-1);
          x_sr(I)     <= x_sr(I-1);
          y_sr(I)     <= y_sr(I-1);
        end loop;
      end if;
    end if;
  end process;

  ---------------------------------------------------------------------------------------------------
  --     _____ _                   _
  --    / ____(_)                 | |
  --   | (___  _  __ _ _ __   __ _| |___
  --    \___ \| |/ _` | '_ \ / _` | / __|
  --    ____) | | (_| | | | | (_| | \__ \
  --   |_____/|_|\__, |_| |_|\__,_|_|___/
  --              __/ |
  --             |___/
  ---------------------------------------------------------------------------------------------------

  step_raw.add.tmis <= tmis_sr(PE_MUL_CYCLES + 2 * PE_ADD_CYCLES - 1);
  step_raw.add.emis <= emis_sr(PE_MUL_CYCLES + 2 * PE_ADD_CYCLES - 1);

  step_raw.emult.tmis <= tmis_sr(PE_CYCLES-1);
  step_raw.emult.emis <= emis_sr(PE_CYCLES-1);

  ---------------------------------------------------------------------------------------------------
  --    _   _                            _    ____        _               _
  --   | \ | |                          | |  / __ \      | |             | |
  --   |  \| | ___  _ __ _ __ ___   __ _| | | |  | |_   _| |_ _ __  _   _| |_ ___
  --   | . ` |/ _ \| '__| '_ ` _ \ / _` | | | |  | | | | | __| '_ \| | | | __/ __|
  --   | |\  | (_) | |  | | | | | | (_| | | | |__| | |_| | |_| |_) | |_| | |_\__ \
  --   |_| \_|\___/|_|  |_| |_| |_|\__,_|_|  \____/ \__,_|\__| .__/ \__,_|\__|___/
  --                                                         | |
  --                                                         |_|
  ---------------------------------------------------------------------------------------------------
  -- Outputs when this PE is not in bypass mode
  ---------------------------------------------------------------------------------------------------

  o_normal.valid <= valid_sr(PE_CYCLES-1);
  o_normal.cell  <= cell_sr(PE_CYCLES-1);

  -- Probabilities
  o_normal.emis <= step_raw.emult.emis;
  o_normal.tmis <= step_raw.emult.tmis;


  gen_es2_extract_emult_m_val : if POSIT_ES = 2 generate
    extract_mt_es2 : posit_extract_raw port map (
      in1      => emult_m_val,
      absolute => open,
      result   => mids_ml
      );
  end generate;
  gen_es3_extract_emult_m_val : if POSIT_ES = 3 generate
    extract_mt_es3 : posit_extract_raw_es3 port map (
      in1      => emult_m_val,
      absolute => open,
      result   => mids_ml
      );
  end generate;

  gen_es2_extract_mul_theta_val : if POSIT_ES = 2 generate
    extract_mt_es2 : posit_extract_raw port map (
      in1      => mul_theta_val,
      absolute => open,
      result   => mids_il
      );
  end generate;
  gen_es3_extract_mul_theta_val : if POSIT_ES = 3 generate
    extract_mt_es3 : posit_extract_raw_es3 port map (
      in1      => mul_theta_val,
      absolute => open,
      result   => mids_il
      );
  end generate;

  gen_es2_extract_mul_upsilon_val : if POSIT_ES = 2 generate
    extract_upsilon_es2 : posit_extract_raw port map (
      in1      => mul_upsilon_val,
      absolute => open,
      result   => mids_dl
      );
  end generate;
  gen_es3_extract_mul_upsilon_val : if POSIT_ES = 3 generate
    extract_upsilon_es3 : posit_extract_raw_es3 port map (
      in1      => mul_upsilon_val,
      absolute => open,
      result   => mids_dl
      );
  end generate;

  -- gen_es2_extract_add_gamma_val : if POSIT_ES = 2 generate
  --   extract_gamma_es2 : posit_extract_raw port map (
  --     in1      => add_gamma_val,
  --     absolute => open,
  --     result   => add_gamma
  --     );
  -- end generate;
  -- gen_es3_extract_add_gamma_val : if POSIT_ES = 3 generate
  --   extract_gamma_es3 : posit_extract_raw_es3 port map (
  --     in1      => add_gamma_val,
  --     absolute => open,
  --     result   => add_gamma
  --     );
  -- end generate;

  gen_es2_extract_add_albetl_val : if POSIT_ES = 2 generate
    extract_add_albetl : posit_extract_raw port map (
      in1      => step.add.albetl,
      absolute => open,
      result   => add_albetl
      );
  end generate;
  gen_es3_extract_add_albetl_val : if POSIT_ES = 3 generate
    extract_add_albetl : posit_extract_raw_es3 port map (
      in1      => step.add.albetl,
      absolute => open,
      result   => add_albetl
      );
  end generate;

  -- o_normal.mids.ml  <= prod2val(step_raw.emult.m);
  o_normal.mids.ml  <= mids_ml;
  o_normal.mids.mtl <= value_empty;
  -- o_normal.mids.mt  <= prod2val(step_raw.emult.m);
  o_normal.mids.mt  <= mids_ml;

  -- o_normal.mids.il <= prodsum2val(mul_theta_sr(PE_MUL_CYCLES-1));
  o_normal.mids.il <= mids_il;

  o_normal.mids.itl <= value_empty;
  o_normal.mids.it  <= value_empty;

  -- o_normal.mids.dl <= prodsum2val(mul_upsilon_sr(PE_MUL_CYCLES-1));
  o_normal.mids.dl <= mids_dl;

  o_normal.mids.dtl <= value_empty;
  o_normal.mids.dt  <= value_empty;

  -- Output X & Y
  o_normal.x <= x_sr(PE_CYCLES-1);
  o_normal.y <= y_sr(PE_CYCLES-1);

  o_normal.initial <= initial_sr(PE_CYCLES-1);

  o_normal.ready <= '1';

  ---------------------------------------------------------------------------------------------------
  --    ____                               ____        _               _
  --   |  _ \                             / __ \      | |             | |
  --   | |_) |_   _ _ __   __ _ ___ ___  | |  | |_   _| |_ _ __  _   _| |_ ___
  --   |  _ <| | | | '_ \ / _` / __/ __| | |  | | | | | __| '_ \| | | | __/ __|
  --   | |_) | |_| | |_) | (_| \__ \__ \ | |__| | |_| | |_| |_) | |_| | |_\__ \
  --   |____/ \__, | .__/ \__,_|___/___/  \____/ \__,_|\__| .__/ \__,_|\__|___/
  --           __/ | |                                    | |
  --          |___/|_|                                    |_|
  ---------------------------------------------------------------------------------------------------

  o_bypass.valid <= valid_sr(PE_CYCLES-1);
  o_bypass.cell  <= cell_sr(PE_CYCLES-1);

  -- Probabilities
  o_bypass.emis <= emis_sr(PE_CYCLES-1);
  o_bypass.tmis <= tmis_sr(PE_CYCLES-1);

  -- Output MIDs
  o_bypass.mids <= mids_sr(PE_CYCLES-1);

  -- Output X & Y
  o_bypass.x <= x_sr(PE_CYCLES-1);
  o_bypass.y <= y_sr(PE_CYCLES-1);

  -- Initial D row value
  o_bypass.initial <= initial_sr(PE_CYCLES-1);

  o_bypass.ready <= '1';

  --------------------------------------------------------------------------------------------------- Determine output:

  determine_out : process(o_bypass, o_normal, x_sr, y_sr)
  begin
    if x_sr(PE_CYCLES-1) = BP_STOP or y_sr(PE_CYCLES-1) = BP_STOP
    then
      o_buf <= o_bypass;
    else
      o_buf <= o_normal;
    end if;
  end process;

  o <= o_buf;

  -- POSIT DEBUGGING
  posit_normalize_ml_initial : posit_normalize port map (
    in1       => step_raw.init.initial,
    result    => posit_norm.init.initial,
    truncated => '0',
    inf       => open,
    zero      => open
    );
  posit_normalize_ml_es31 : posit_normalize_prod port map (
    in1       => step_raw.trans.almtl,
    result    => posit_norm.trans.almtl,
    truncated => '0',
    inf       => open,
    zero      => open
    );
  posit_normalize_ml_es32 : posit_normalize_prod port map (
    in1       => step_raw.trans.beitl,
    result    => posit_norm.trans.beitl,
    truncated => '0',
    inf       => open,
    zero      => open
    );
  posit_normalize_ml_es33 : posit_normalize_prod port map (
    in1       => step_raw.trans.gadtl,
    result    => posit_norm.trans.gadtl,
    truncated => '0',
    inf       => open,
    zero      => open
    );
  posit_normalize_ml_es34 : posit_normalize_prod port map (
    in1       => (step_raw.trans.demt),
    result    => posit_norm.trans.demt,
    truncated => '0',
    inf       => open,
    zero      => open
    );
  posit_normalize_ml_es35 : posit_normalize_prod port map (
    in1       => (step_raw.trans.epit),
    result    => posit_norm.trans.epit,
    truncated => '0',
    inf       => open,
    zero      => open
    );
  posit_normalize_ml_es36 : posit_normalize_prod port map (
    in1       => (step_raw.trans.zeml),
    result    => posit_norm.trans.zeml,
    truncated => '0',
    inf       => open,
    zero      => open
    );
  posit_normalize_ml_es37 : posit_normalize_prod port map (
    in1       => (step_raw.trans.etdl),
    result    => posit_norm.trans.etdl,
    truncated => '0',
    inf       => open,
    zero      => open
    );
  posit_normalize_ml_es38 : posit_normalize_prod_sum port map (
    in1       => (step_raw.add.albetl),
    result    => posit_norm.add.albetl,
    truncated => posit_truncated(0),
    inf       => open,
    zero      => open
    );
  -- posit_normalize_ml_es39 : posit_normalize_sum port map (
  --   in1       => (step_raw.add.albegatl),
  --   result    => posit_norm.add.albegatl,
  --   truncated => '0',
  --   inf       => open,
  --   zero      => open
  --   );
  posit_normalize_ml_es310 : posit_normalize_prod_sum port map (
    in1       => (step_raw.add.deept),
    result    => posit_norm.add.deept,
    truncated => '0',
    inf       => open,
    zero      => open
    );
  posit_normalize_ml_es311 : posit_normalize_prod_sum port map (
    in1       => (step_raw.add.zeett),
    result    => posit_norm.add.zeett,
    truncated => '0',
    inf       => open,
    zero      => open
    );
  posit_normalize_ml_es312 : posit_normalize_product_prod_sum_sum port map (
    in1       => (step_raw.emult.m),
    result    => posit_norm.emult.m,
    truncated => posit_truncated(4),
    inf       => open,
    zero      => open
    );
  posit_normalize_ml_es313 : posit_normalize_prod port map (
    in1       => (step_raw.emult.i),
    result    => posit_norm.emult.i,
    truncated => '0',
    inf       => open,
    zero      => open
    );
  posit_normalize_ml_es314 : posit_normalize_prod port map (
    in1       => (step_raw.emult.d),
    result    => posit_norm.emult.d,
    truncated => '0',
    inf       => open,
    zero      => open
    );
  posit_normalize_ml_es410 : posit_normalize port map (
    in1       => step_raw.init.tmis.alpha,
    result    => posit_norm.init.tmis.alpha,
    truncated => '0',
    inf       => open,
    zero      => open
    );
  posit_normalize_ml_es411 : posit_normalize port map (
    in1       => step_raw.init.tmis.beta,
    result    => posit_norm.init.tmis.beta,
    truncated => '0',
    inf       => open,
    zero      => open
    );
  posit_normalize_ml_es412 : posit_normalize port map (
    in1       => step_raw.init.tmis.delta,
    result    => posit_norm.init.tmis.delta,
    truncated => '0',
    inf       => open,
    zero      => open
    );
  posit_normalize_ml_es413 : posit_normalize port map (
    in1       => step_raw.init.tmis.epsilon,
    result    => posit_norm.init.tmis.epsilon,
    truncated => '0',
    inf       => open,
    zero      => open
    );
  posit_normalize_ml_es414 : posit_normalize port map (
    in1       => step_raw.init.tmis.zeta,
    result    => posit_norm.init.tmis.zeta,
    truncated => '0',
    inf       => open,
    zero      => open
    );
  posit_normalize_ml_es415 : posit_normalize port map (
    in1       => step_raw.init.tmis.eta,
    result    => posit_norm.init.tmis.eta,
    truncated => '0',
    inf       => open,
    zero      => open
    );
  posit_normalize_ml_es000 : posit_normalize port map (
    in1       => step_raw.init.tmis.eta,
    result    => posit_norm.init.tmis.eta,
    truncated => '0',
    inf       => open,
    zero      => open
    );
  posit_normalize_ml_es514_it : posit_normalize port map (
    in1       => step_raw.init.mids.it,
    result    => posit_norm.init.mids.it,
    truncated => '0',
    inf       => open,
    zero      => open
    );
  posit_normalize_ml_es514_il : posit_normalize port map (
    in1       => step_raw.init.mids.il,
    result    => posit_norm.init.mids.il,
    truncated => '0',
    inf       => open,
    zero      => open
    );
  posit_normalize_ml_es514_ml : posit_normalize port map (
    in1       => step_raw.init.mids.ml,
    result    => posit_norm.init.mids.ml,
    truncated => '0',
    inf       => open,
    zero      => open
    );
  posit_normalize_ml_es514_mtl : posit_normalize port map (
    in1       => step_raw.init.mids.mtl,
    result    => posit_norm.init.mids.mtl,
    truncated => '0',
    inf       => open,
    zero      => open
    );
  posit_normalize_ml_es514_dtl : posit_normalize port map (
    in1       => step_raw.init.mids.dtl,
    result    => posit_norm.init.mids.dtl,
    truncated => '0',
    inf       => open,
    zero      => open
    );
  posit_normalize_ml_es514_dl : posit_normalize port map (
    in1       => step_raw.init.mids.dl,
    result    => posit_norm.init.mids.dl,
    truncated => '0',
    inf       => open,
    zero      => open
    );
  posit_normalize_ml_es514_mt123 : posit_normalize port map (
    in1       => step_raw.init.mids.mt,
    result    => posit_norm.init.mids.mt,
    truncated => '0',
    inf       => open,
    zero      => open
    );
  posit_normalize_ml_es514 : posit_normalize port map (
    in1       => step_raw.init.mids.itl,
    result    => posit_norm.init.mids.itl,
    truncated => '0',
    inf       => open,
    zero      => open
    );
  posit_normalize_ml_es516 : posit_normalize port map (
    in1       => step_raw.init.mids.dt,
    result    => posit_norm.init.mids.dt,
    truncated => '0',
    inf       => open,
    zero      => open
    );
  posit_normalize_ml_distm : posit_normalize port map (
    in1       => distm,
    result    => distm_norm,
    truncated => '0',
    inf       => open,
    zero      => open
    );


---------------------------------------------------------------------------------------------------
end rtl;
