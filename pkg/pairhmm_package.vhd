---------------------------------------------------------------------------------------------------
--    _____      _      _    _ __  __ __  __
--   |  __ \    (_)    | |  | |  \/  |  \/  |
--   | |__) |_ _ _ _ __| |__| | \  / | \  / |
--   |  ___/ _` | | '__|  __  | |\/| | |\/| |
--   | |  | (_| | | |  | |  | | |  | | |  | |
--   |_|   \__,_|_|_|  |_|  |_|_|  |_|_|  |_|
---------------------------------------------------------------------------------------------------
-- PairHMM core package
---------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.functions.all;
use work.pe_package.all;

package pairhmm_package is

  constant PAIRHMM_MAX_SIZE                : natural := 512;
  constant PAIRHMM_NUM_PES                 : natural := 16;
  constant PAIRHMM_BITS_PER_PROB           : natural := 8 * PE_DW;

  type bp_array_type is array (0 to PAIRHMM_MAX_SIZE-1) of bp_type;
  constant bp_array_empty : bp_array_type := (others => BP_IGNORE);

  type bp_all_type is array (0 to PE_DEPTH-1) of bp_array_type;
  constant bp_all_empty : bp_all_type := (others => bp_array_empty);

  type x_array_type is array (0 to PAIRHMM_NUM_PES - 1) of bp_type;
  constant x_array_empty : x_array_type := (others => BP_IGNORE);
  constant x_array_actg  : x_array_type := (0      => BP_A, 1 => BP_C, 2 => BP_T, 3 => BP_G, others => BP_IGNORE);

  type x_to_pes_type is array (0 to PE_DEPTH - 1) of x_array_type;
  constant x_to_pes_empty : x_to_pes_type := (others => x_array_empty);

  type pe_y_data_type is array (0 to PE_DEPTH - 1) of bp_type;

  constant pe_y_data_empty : pe_y_data_type := (others => BP_STOP);

  type pe_y_data_regs_type is array (0 to PAIRHMM_NUM_PES - 1) of pe_y_data_type;

  constant pe_y_data_regs_empty : pe_y_data_regs_type := (others => pe_y_data_empty);

  type ybus_type is record
    addr : unsigned(log2e(PAIRHMM_NUM_PES) downto 0);
    data : pe_y_data_type;
    wren : std_logic;
  end record;

  constant ybus_empty : ybus_type := (
    addr => (others => '0'),
    data => pe_y_data_empty,
    wren => '0'
    );

  type pairhmm_in is record
    first    : pe_in;
    ybus     : ybus_type;
    x        : bp_type;
    schedule : unsigned(PE_DEPTH_BITS-1 downto 0);
    fb       : std_logic;
  end record;

  constant pairhmm_in_empty : pairhmm_in := (
    first    => pe_in_empty,
    ybus     => ybus_empty,
    x        => BP_IGNORE,
    schedule => (others => '0'),
    fb       => '0'
    );

  type pairhmm_out is record
    score       : prob;
    score_valid : std_logic;
    last        : pe_out;
    ready       : std_logic;
  end record;

  type pairhmm_item is record
    i : pairhmm_in;
    o : pairhmm_out;
  end record;

  type acc_state is (adding, resetting);
  type acc_state_wide is (adding, accumulating, reset_accumulator, resetting);

end package;
