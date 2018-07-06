---------------------------------------------------------------------------------------------------
--    _____      _      _    _ __  __ __  __
--   |  __ \    (_)    | |  | |  \/  |  \/  |
--   | |__) |_ _ _ _ __| |__| | \  / | \  / |
--   |  ___/ _` | | '__|  __  | |\/| | |\/| |
--   | |  | (_| | | |  | |  | | |  | | |  | |
--   |_|   \__,_|_|_|  |_|  |_|_|  |_|_|  |_|
---------------------------------------------------------------------------------------------------
-- Processing Element package
---------------------------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.functions.all;

package pe_package is

  constant POSIT_NBITS            : natural := 32;
  constant POSIT_ES               : natural := 3;
  constant POSIT_WIDE_ACCUMULATOR : natural := 1;  -- 0: dont use wide accumulator in pairhmm.vhd

  constant PE_DW         : natural := 32;               -- data width
  constant PE_MUL_CYCLES : natural := 4;
  constant PE_ADD_CYCLES : natural := 4;
  constant PE_CYCLES     : natural := 2 * PE_MUL_CYCLES + 2 * PE_ADD_CYCLES;
  constant PE_DEPTH      : natural := PE_CYCLES;
  constant PE_DEPTH_BITS : natural := log2e(PE_DEPTH);  -- should be round_up(log_2(PE_DEPTH)).
  constant PE_BCC        : natural := PE_MUL_CYCLES + 2 * PE_ADD_CYCLES;  -- base compare cycle

  -- Internal type for values
  subtype prob is std_logic_vector(PE_DW-1 downto 0);

  constant prob_zero : prob := X"00000000";
  constant prob_one  : prob := X"3F800000";

  type pe_cell_type is (PE_NORMAL, PE_TOP, PE_LAST, PE_BOTTOM);

  constant POSIT_SERIALIZED_WIDTH_ES3         : natural := 1+9+26+1+1;
  constant POSIT_SERIALIZED_WIDTH_SUM_ES3     : natural := 1+9+30+1+1;
  constant POSIT_SERIALIZED_WIDTH_PRODUCT_ES3 : natural := 1+10+54+1+1;

  subtype value_es3 is std_logic_vector(POSIT_SERIALIZED_WIDTH_ES3-1 downto 0);

  constant value_es3_empty : value_es3 := (POSIT_SERIALIZED_WIDTH_ES3-1 downto 1 => '0', others => '1');
  --(
  -- sgn     => '0',
  -- scale    => (others => '0'),
  -- fraction => (others => '0'),
  -- inf      => '0',
  -- zero     => '1'
  -- );

  constant value_es3_one : value_es3 := (others => '0');
  -- (
  --   sgn     => '0',
  --   scale    => (others => '0'),
  --   fraction => (others => '0'),
  --   inf      => '0',
  --   zero     => '0'
  --   );

  subtype value_sum_es3 is std_logic_vector(POSIT_SERIALIZED_WIDTH_SUM_ES3-1 downto 0);
  constant value_sum_es3_empty : value_sum_es3 := (POSIT_SERIALIZED_WIDTH_SUM_ES3-1 downto 1 => '0', others => '1');
  --      record
  --   sgn     : std_logic;
  --   scale    : std_logic_vector(8 downto 0);
  --   fraction : std_logic_vector(29 downto 0);
  --   inf      : std_logic;
  --   zero     : std_logic;
  -- end record;

  -- constant value_sum_es3_empty : value_sum_es3 := (
  --   sgn     => '0',
  --   scale    => (others => '0'),
  --   fraction => (others => '0'),
  --   inf      => '0',
  --   zero     => '1'
  --   );


  subtype value_product_es3 is std_logic_vector(POSIT_SERIALIZED_WIDTH_PRODUCT_ES3-1 downto 0);
  constant value_product_es3_empty : value_product_es3 := (POSIT_SERIALIZED_WIDTH_PRODUCT_ES3-1 downto 1 => '0', others => '1');

  -- type value_product_es3 is record
  --   sgn     : std_logic;
  --   scale    : std_logic_vector(9 downto 0);
  --   fraction : std_logic_vector(53 downto 0);
  --   inf      : std_logic;
  --   zero     : std_logic;
  -- end record;
  --
  -- constant value_product_es3_empty : value_product_es3 := (
  --   sgn     => '0',
  --   scale    => (others => '0'),
  --   fraction => (others => '0'),
  --   inf      => '0',
  --   zero     => '1'
  --   );

  type matchindels is record
    mtl : prob;
    itl : prob;
    dtl : prob;

    mt : prob;
    it : prob;
    dt : prob;

    ml : prob;
    il : prob;
    dl : prob;
  end record;

  type matchindels_es3 is record
    mtl : value_es3;
    itl : value_es3;
    dtl : value_es3;

    mt : value_es3;
    it : value_es3;
    dt : value_es3;

    ml : value_es3;
    il : value_es3;
    dl : value_es3;
  end record;

  constant mids_mlone : matchindels := (
    mtl => (others => '0'),
    itl => (others => '0'),
    dtl => (others => '0'),
    mt  => (others => '0'),
    it  => (others => '0'),
    dt  => (others => '0'),
    ml  => X"40000000",                 -- posit<32,2>/posit<32,3>: 40000000
    il  => (others => '0'),
    dl  => (others => '0')
    );

  constant mids_empty : matchindels := (
    mtl => (others => '0'),
    itl => (others => '0'),
    dtl => (others => '0'),
    mt  => (others => '0'),
    it  => (others => '0'),
    dt  => (others => '0'),
    ml  => (others => '0'),
    il  => (others => '0'),
    dl  => (others => '0')
    );

  constant mids_es3_empty : matchindels_es3 := (
    mtl => value_es3_empty,
    itl => value_es3_empty,
    dtl => value_es3_empty,
    mt  => value_es3_empty,
    it  => value_es3_empty,
    dt  => value_es3_empty,
    ml  => value_es3_empty,
    il  => value_es3_empty,
    dl  => value_es3_empty
    );

  type transmissions is record
    alpha : prob;
    beta  : prob;

    delta   : prob;
    epsilon : prob;

    zeta : prob;
    eta  : prob;
  end record;

  constant tmis_empty : transmissions := (
    alpha   => (others => '0'),
    beta    => (others => '0'),
    delta   => (others => '0'),
    epsilon => (others => '0'),
    zeta    => (others => '0'),
    eta     => (others => '0')
    );

  type transmissions_es3 is record
    alpha : value_es3;
    beta  : value_es3;

    delta   : value_es3;
    epsilon : value_es3;

    zeta : value_es3;
    eta  : value_es3;
  end record;

  constant tmis_es3_empty : transmissions_es3 := (
    alpha   => value_es3_empty,
    beta    => value_es3_empty,
    delta   => value_es3_empty,
    epsilon => value_es3_empty,
    zeta    => value_es3_empty,
    eta     => value_es3_empty
    );

  type emissions is record
    distm_simi : prob;
    distm_diff : prob;
    theta      : prob;
    upsilon    : prob;
  end record;

  type probabilities is record
    distm_simi : std_logic_vector(31 downto 0);
    distm_diff : std_logic_vector(31 downto 0);
    theta      : std_logic_vector(31 downto 0);
    upsilon    : std_logic_vector(31 downto 0);
      alpha : std_logic_vector(31 downto 0);
      beta  : std_logic_vector(31 downto 0);
      delta   : std_logic_vector(31 downto 0);
      epsilon : std_logic_vector(31 downto 0);
      zeta : std_logic_vector(31 downto 0);
      eta  : std_logic_vector(31 downto 0);
  end record;

  constant emis_empty : emissions := (
    distm_simi => (others => '0'),
    distm_diff => (others => '0'),
    theta      => (others => '0'),
    upsilon    => (others => '0')
    );

  type emissions_es3 is record
    distm_simi : value_es3;
    distm_diff : value_es3;
    theta      : value_es3;
    upsilon    : value_es3;
  end record;

  constant emis_es3_empty : emissions_es3 := (
    distm_simi => value_es3_empty,
    distm_diff => value_es3_empty,
    theta      => value_es3_empty,
    upsilon    => value_es3_empty
    );

  type step_init_type is record
    initial : prob;
    tmis    : transmissions;
    emis    : emissions;
    mids    : matchindels;
    valid   : std_logic;
    cell    : pe_cell_type;
    x       : bp_type;
    y       : bp_type;
  end record;

  constant step_init_empty : step_init_type := (
    initial => (others => '0'),
    tmis    => tmis_empty,
    emis    => emis_empty,
    mids    => mids_empty,
    valid   => '0',
    cell    => PE_NORMAL,
    x       => BP_IGNORE,
    y       => BP_IGNORE
    );

  type step_init_es3_type is record
    initial : value_es3;
    tmis    : transmissions_es3;
    emis    : emissions_es3;
    mids    : matchindels_es3;
    valid   : std_logic;
    cell    : pe_cell_type;
    x       : bp_type;
    y       : bp_type;
  end record;

  constant step_init_es3_empty : step_init_es3_type := (
    initial => value_es3_empty,
    tmis    => tmis_es3_empty,
    emis    => emis_es3_empty,
    mids    => mids_es3_empty,
    valid   => '0',
    cell    => PE_NORMAL,
    x       => BP_IGNORE,
    y       => BP_IGNORE
    );

  type step_trans_type is record
    almtl : prob;
    beitl : prob;
    gadtl : prob;
    demt  : prob;
    epit  : prob;
    zeml  : prob;
    etdl  : prob;

    tmis : transmissions;
    emis : emissions;
    mids : matchindels;
  end record;


  constant step_trans_empty : step_trans_type := (
    almtl => (others => '0'),
    beitl => (others => '0'),
    gadtl => (others => '0'),
    demt  => (others => '0'),
    epit  => (others => '0'),
    zeml  => (others => '0'),
    etdl  => (others => '0'),
    tmis  => tmis_empty,
    emis  => emis_empty,
    mids  => mids_empty
    );

  type step_trans_es3_type is record    -- TODO for es2
    almtl : value_product_es3;
    beitl : value_product_es3;
    gadtl : value_product_es3;
    demt  : value_product_es3;
    epit  : value_product_es3;
    zeml  : value_product_es3;
    etdl  : value_product_es3;

    tmis : transmissions_es3;
    emis : emissions_es3;
    mids : matchindels_es3;
  end record;

  constant step_trans_es3_empty : step_trans_es3_type := (
    almtl => value_product_es3_empty,
    beitl => value_product_es3_empty,
    gadtl => value_product_es3_empty,
    demt  => value_product_es3_empty,
    epit  => value_product_es3_empty,
    zeml  => value_product_es3_empty,
    etdl  => value_product_es3_empty,
    tmis  => tmis_es3_empty,
    emis  => emis_es3_empty,
    mids  => mids_es3_empty
    );

  type step_add_type is record
    albetl   : prob;
    albegatl : prob;
    deept    : prob;
    zeett    : prob;

    tmis : transmissions;
    emis : emissions;
    mids : matchindels;
  end record;

  constant step_add_empty : step_add_type := (
    albetl   => (others => '0'),
    albegatl => (others => '0'),
    deept    => (others => '0'),
    zeett    => (others => '0'),
    tmis     => tmis_empty,
    emis     => emis_empty,
    mids     => mids_empty
    );

  type step_add_es3_type is record
    albetl   : value_sum_es3;
    albegatl : value_sum_es3;
    deept    : value_sum_es3;
    zeett    : value_sum_es3;

    tmis : transmissions_es3;
    emis : emissions_es3;
    mids : matchindels_es3;
  end record;

  constant step_add_es3_empty : step_add_es3_type := (
    albetl   => value_sum_es3_empty,
    albegatl => value_sum_es3_empty,
    deept    => value_sum_es3_empty,
    zeett    => value_sum_es3_empty,
    tmis     => tmis_es3_empty,
    emis     => emis_es3_empty,
    mids     => mids_es3_empty
    );

  type step_emult_type is record
    m : prob;
    i : prob;
    d : prob;

    tmis : transmissions;
    emis : emissions;
    mids : matchindels;
  end record;

  constant step_emult_empty : step_emult_type := (
    m    => (others => '0'),
    i    => (others => '0'),
    d    => (others => '0'),
    tmis => tmis_empty,
    emis => emis_empty,
    mids => mids_empty
    );

  type step_emult_es3_type is record
    m : value_product_es3;
    i : value_product_es3;
    d : value_product_es3;

    tmis : transmissions_es3;
    emis : emissions_es3;
    mids : matchindels_es3;
  end record;

  constant step_emult_es3_empty : step_emult_es3_type := (
    m    => value_product_es3_empty,
    i    => value_product_es3_empty,
    d    => value_product_es3_empty,
    tmis => tmis_es3_empty,
    emis => emis_es3_empty,
    mids => mids_es3_empty
    );

  type step_type is record
    init  : step_init_type;
    trans : step_trans_type;
    add   : step_add_type;
    emult : step_emult_type;
  end record;

  constant step_type_init : step_type := (
    init  => step_init_empty,
    trans => step_trans_empty,
    add   => step_add_empty,
    emult => step_emult_empty
    );

  type step_es3_type is record
    init  : step_init_es3_type;
    trans : step_trans_es3_type;
    add   : step_add_es3_type;
    emult : step_emult_es3_type;
  end record;

  constant step_es3_init : step_es3_type := (
    init  => step_init_es3_empty,
    trans => step_trans_es3_empty,
    add   => step_add_es3_empty,
    emult => step_emult_es3_empty
    );

  type bps is array (0 to PE_DEPTH-1) of bp_type;

  constant bps_empty : bps := (others => BP_IGNORE);

  type pe_in is record
    en      : std_logic;
    valid   : std_logic;
    cell    : pe_cell_type;
    initial : value_es3;
    tmis    : transmissions_es3;
    emis    : emissions_es3;
    mids    : matchindels_es3;
    x       : bp_type;
    y       : bp_type;
  end record;

  constant pe_in_empty : pe_in := (
    en      => '0',
    valid   => '0',
    cell    => PE_NORMAL,
    initial => value_es3_empty,
    mids    => mids_es3_empty,
    tmis    => tmis_es3_empty,
    emis    => emis_es3_empty,
    x       => BP_IGNORE,
    y       => BP_IGNORE
    );

  type pe_out is record
    ready   : std_logic;
    valid   : std_logic;
    cell    : pe_cell_type;
    initial : value_es3;
    tmis    : transmissions_es3;
    emis    : emissions_es3;
    mids    : matchindels_es3;
    x       : bp_type;
    y       : bp_type;
  end record;

  type initial_array_pe is array (0 to PE_CYCLES-1) of prob;
  type initial_array_pe_raw is array (0 to PE_CYCLES-1) of value_es3;
  type emissions_array is array (0 to PE_CYCLES-1) of emissions;
  type transmissions_array is array (0 to PE_CYCLES-1) of transmissions;
  type mids_array is array (0 to PE_CYCLES-1) of matchindels;
  type valid_array is array (0 to PE_CYCLES-1) of std_logic;
  type cell_array is array (0 to PE_CYCLES-1) of pe_cell_type;

  type emissions_raw_array is array (0 to PE_CYCLES-1) of emissions_es3;
  type transmissions_raw_array is array (0 to PE_CYCLES-1) of transmissions_es3;
  type mids_raw_array is array (0 to PE_CYCLES-1) of matchindels_es3;

  subtype value is value_es3;
  alias value_empty         : value_es3 is value_es3_empty;
  subtype value_product is value_product_es3;
  alias value_product_empty : value_product_es3 is value_product_es3_empty;
  subtype value_sum is value_sum_es3;
  alias value_sum_empty     : value_sum_es3 is value_sum_es3_empty;
  alias value_one           : value_es3 is value_es3_one;

  function pst2slv (a : in pe_cell_type) return std_logic_vector;

  component posit_normalize_sum_es3
    port (
      in1    : in  std_logic_vector(POSIT_SERIALIZED_WIDTH_SUM_ES3-1 downto 0);
      result : out std_logic_vector(POSIT_NBITS-1 downto 0);
      inf    : out std_logic;
      zero   : out std_logic
      );
  end component;

  component posit_extract_raw_es3
    port (
      in1    : in  std_logic_vector(POSIT_NBITS-1 downto 0);
      absolute : out std_logic_vector(31-1 downto 0);
      result   : out std_logic_vector(POSIT_SERIALIZED_WIDTH_ES3-1 downto 0)
      );
  end component;

  component positadd_4_raw_es3
    port (
      clk    : in  std_logic;
      in1    : in  std_logic_vector(POSIT_SERIALIZED_WIDTH_ES3-1 downto 0);
      in2    : in  std_logic_vector(POSIT_SERIALIZED_WIDTH_ES3-1 downto 0);
      start  : in  std_logic;
      result : out std_logic_vector(POSIT_SERIALIZED_WIDTH_SUM_ES3-1 downto 0);
      done   : out std_logic
      );
  end component;

  component posit_normalize_es3
    port (
      in1    : in  std_logic_vector(POSIT_SERIALIZED_WIDTH_ES3-1 downto 0);
      result : out std_logic_vector(POSIT_NBITS-1 downto 0);
      inf    : out std_logic;
      zero   : out std_logic
      );
  end component;

  component positadd_8_raw_es3
    port (
      clk    : in  std_logic;
      in1    : in  std_logic_vector(POSIT_SERIALIZED_WIDTH_ES3-1 downto 0);
      in2    : in  std_logic_vector(POSIT_SERIALIZED_WIDTH_ES3-1 downto 0);
      start  : in  std_logic;
      result : out std_logic_vector(POSIT_SERIALIZED_WIDTH_SUM_ES3-1 downto 0);
      done   : out std_logic
      );
  end component;

  component positmult_4_raw_es3
    port (
      clk    : in  std_logic;
      in1    : in  std_logic_vector(POSIT_SERIALIZED_WIDTH_ES3-1 downto 0);
      in2    : in  std_logic_vector(POSIT_SERIALIZED_WIDTH_ES3-1 downto 0);
      start  : in  std_logic;
      result : out std_logic_vector(POSIT_SERIALIZED_WIDTH_PRODUCT_ES3-1 downto 0);
      done   : out std_logic
      );
  end component;

  component positmult_4_raw_sumval_es3
    port (
      clk    : in  std_logic;
      in1    : in  std_logic_vector(POSIT_SERIALIZED_WIDTH_SUM_ES3-1 downto 0);
      in2    : in  std_logic_vector(POSIT_SERIALIZED_WIDTH_ES3-1 downto 0);
      start  : in  std_logic;
      result : out std_logic_vector(POSIT_SERIALIZED_WIDTH_PRODUCT_ES3-1 downto 0);
      done   : out std_logic
      );
  end component;

  -- component posit_prod_to_value_es3
  --   port (
  --     in1    : in  value_product_es3;
  --     result : out value_es3
  --     );
  -- end component;
  --
  -- component posit_sum_to_value_es3
  --   port (
  --     in1    : in  value_sum_es3;
  --     result : out value_es3
  --     );
  -- end component;

  component positadd_4
    port (
      clk    : in  std_logic;
      in1    : in  std_logic_vector(31 downto 0);
      in2    : in  std_logic_vector(31 downto 0);
      start  : in  std_logic;
      result : out std_logic_vector(31 downto 0);
      inf    : out std_logic;
      zero   : out std_logic;
      done   : out std_logic
      );
  end component;

  component positadd_8
    port (
      clk    : in  std_logic;
      in1    : in  std_logic_vector(31 downto 0);
      in2    : in  std_logic_vector(31 downto 0);
      start  : in  std_logic;
      result : out std_logic_vector(31 downto 0);
      inf    : out std_logic;
      zero   : out std_logic;
      done   : out std_logic
      );
  end component;

  component positmult_4
    port (
      clk    : in  std_logic;
      in1    : in  std_logic_vector(31 downto 0);
      in2    : in  std_logic_vector(31 downto 0);
      start  : in  std_logic;
      result : out std_logic_vector(31 downto 0);
      inf    : out std_logic;
      zero   : out std_logic;
      done   : out std_logic
      );
  end component;

  component positadd_4_es3
    port (
      clk    : in  std_logic;
      in1    : in  std_logic_vector(31 downto 0);
      in2    : in  std_logic_vector(31 downto 0);
      start  : in  std_logic;
      result : out std_logic_vector(31 downto 0);
      inf    : out std_logic;
      zero   : out std_logic;
      done   : out std_logic
      );
  end component;

  component positadd_8_es3
    port (
      clk    : in  std_logic;
      in1    : in  std_logic_vector(31 downto 0);
      in2    : in  std_logic_vector(31 downto 0);
      start  : in  std_logic;
      result : out std_logic_vector(31 downto 0);
      inf    : out std_logic;
      zero   : out std_logic;
      done   : out std_logic
      );
  end component;

  component positmult_4_es3
    port (
      clk    : in  std_logic;
      in1    : in  std_logic_vector(31 downto 0);
      in2    : in  std_logic_vector(31 downto 0);
      start  : in  std_logic;
      result : out std_logic_vector(31 downto 0);
      inf    : out std_logic;
      zero   : out std_logic;
      done   : out std_logic
      );
  end component;

  -- function val2slv (a : in value_es3) return std_logic_vector;
  -- function val2slv (a : in value_sum_es3) return std_logic_vector;
  -- function val2slv (a : in value_product_es3) return std_logic_vector;
  --
  -- function slv2val (a  : in std_logic_vector) return value_es3;
  --   function slv2val (a  : in std_logic_vector) return value_sum_es3;
  --     function slv2val (a  : in std_logic_vector) return value_product_es3;

  function prod2val (a : in value_product_es3) return value_es3;
  function sum2val (a  : in value_sum_es3) return value_es3;

end package;

package body pe_package is

  -- function val2slv (a : in value_es3) return std_logic_vector is
  -- begin
  --   return a.sgn & std_logic_vector(a.scale) & a.fraction & a.inf & a.zero;
  -- end function val2slv;
  --
  -- function val2slv (a : in value_sum_es3) return std_logic_vector is
  -- begin
  --   return a.sgn & std_logic_vector(a.scale) & a.fraction & a.inf & a.zero;
  -- end function val2slv;
  --
  -- function val2slv (a : in value_product_es3) return std_logic_vector is
  -- begin
  --   return a.sgn & std_logic_vector(a.scale) & a.fraction & a.inf & a.zero;
  -- end function val2slv;

  -- function slv2val (a : in std_logic_vector) return value_es3 is
  --   variable result : value_es3;
  -- begin
  --   result.sgn     := a(37);
  --   result.scale    := a(36 downto 28);
  --   result.fraction := a(27 downto 2);
  --   result.inf      := a(1);
  --   result.zero     := a(0);
  --   return result;
  -- end function slv2val;
  --
  -- function slv2val (a : in std_logic_vector) return value_sum_es3 is
  --   variable result : value_sum_es3;
  -- begin
  --   result.sgn     := a(41);
  --   result.scale    := a(40 downto 32);
  --   result.fraction := a(31 downto 2);
  --   result.inf      := a(1);
  --   result.zero     := a(0);
  --   return result;
  -- end function slv2val;
  --
  -- function slv2val (a : in std_logic_vector) return value_product_es3 is
  --   variable result : value_product_es3;
  -- begin
  --   result.sgn     := a(66);
  --   result.scale    := a(65 downto 56);
  --   result.fraction := a(55 downto 2);
  --   result.inf      := a(1);
  --   result.zero     := a(0);
  --   return result;
  -- end function slv2val;


  -- Product layout:
  -- 67 1       sign
  -- 66 10      scale
  -- 56 54      fraction
  -- 2  1       inf
  -- 1  1       zero
  -- 0
  function prod2val (a : in value_product_es3) return value_es3 is
    variable tmp : std_logic_vector(POSIT_SERIALIZED_WIDTH_ES3-1 downto 0);
  begin
      tmp(0) := a(0);
      tmp(1) := a(1);
      tmp(27 downto 2) := a(55 downto 30);
      tmp(36 downto 28) := a(64 downto 56);
      tmp(37) := a(66);
      return tmp;
  end function prod2val;

  -- Sum layout:
  -- 42 1       sign
  -- 41 9       scale
  -- 32 30      fraction
  -- 2  1       inf
  -- 1  1       zero
  -- 0
  function sum2val (a : in value_sum_es3) return value_es3 is
    variable tmp : std_logic_vector(POSIT_SERIALIZED_WIDTH_ES3-1 downto 0);
  begin
    tmp(0) := a(0);
    tmp(1) := a(1);
    tmp(27 downto 2) := a(31 downto 6);
    tmp(36 downto 28) := a(40 downto 32);
    tmp(37) := a(41);
    return tmp;
  end function sum2val;

  function pst2slv (a : in pe_cell_type) return std_logic_vector is
  begin
    case a is
      when PE_NORMAL => return "00";
      when PE_TOP    => return "01";
      when PE_BOTTOM => return "10";
      when PE_LAST   => return "11";
    end case;
  end function pst2slv;

end package body;
