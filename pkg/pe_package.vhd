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

  constant POSIT_NBITS   : natural := 32;
  constant POSIT_ES      : natural := 2;
  constant POSIT_WIDE_ACCUMULATOR : natural := 1; -- 0: dont use wide accumulator in pairhmm.vhd

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

  constant mids_mlone : matchindels := (
    mtl => (others => '0'),
    itl => (others => '0'),
    dtl => (others => '0'),
    mt  => (others => '0'),
    it  => (others => '0'),
    dt  => (others => '0'),
    ml  => X"40000000", -- posit<32,2>/posit<32,3>: 40000000
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

  type emissions is record
    distm_simi : prob;
    distm_diff : prob;
    theta      : prob;
    upsilon    : prob;
  end record;

  constant emis_empty : emissions := (
    distm_simi => (others => '0'),
    distm_diff => (others => '0'),
    theta      => (others => '0'),
    upsilon    => (others => '0')
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

  type bps is array (0 to PE_DEPTH-1) of bp_type;

  constant bps_empty : bps := (others => BP_IGNORE);

  type pe_in is record
    en      : std_logic;
    valid   : std_logic;
    cell    : pe_cell_type;
    initial : prob;
    tmis    : transmissions;
    emis    : emissions;
    mids    : matchindels;
    x       : bp_type;
    y       : bp_type;
  end record;

  constant pe_in_empty : pe_in := (
    en      => '0',
    valid   => '0',
    cell    => PE_NORMAL,
    initial => (others => '0'),
    mids    => mids_empty,
    tmis    => tmis_empty,
    emis    => emis_empty,
    x       => BP_IGNORE,
    y       => BP_IGNORE
    );

  type pe_out is record
    ready   : std_logic;
    valid   : std_logic;
    cell    : pe_cell_type;
    initial : prob;
    tmis    : transmissions;
    emis    : emissions;
    mids    : matchindels;
    x       : bp_type;
    y       : bp_type;
  end record;

  type initial_array_pe is array (0 to PE_CYCLES-1) of prob;
  type emissions_array is array (0 to PE_CYCLES-1) of emissions;
  type transmissions_array is array (0 to PE_CYCLES-1) of transmissions;
  type mids_array is array (0 to PE_CYCLES-1) of matchindels;
  type valid_array is array (0 to PE_CYCLES-1) of std_logic;
  type cell_array is array (0 to PE_CYCLES-1) of pe_cell_type;

  function pst2slv (a : in pe_cell_type) return std_logic_vector;

end package;

package body pe_package is

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
