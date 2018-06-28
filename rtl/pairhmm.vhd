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

  signal addm_out       : prob;  -- Laurens: 1 extra delay (11 -> 12 cycles latency)
  signal addm_out_valid : std_logic;

  signal addi_out       : prob;
  signal addi_out_valid : std_logic;

  signal res_acc : prob;

  type res_array is array (0 to PAIRHMM_NUM_PES-1) of prob;

  signal res_rst : std_logic;
  signal resm    : res_array;
  signal resi    : res_array;

  signal resbusm, resbusi : prob;

  signal lastlast  : std_logic;
  signal lastlast1 : std_logic;

  component positaccum_16
    port (
      clk    : in  std_logic;
      rst    : in  std_logic;
      in1    : in  std_logic_vector(31 downto 0);
      start  : in  std_logic;
      result : out std_logic_vector(31 downto 0);
      inf    : out std_logic;
      zero   : out std_logic;
      done   : out std_logic
      );
  end component;

  component positaccum_16_es3
    port (
      clk    : in  std_logic;
      rst    : in  std_logic;
      in1    : in  std_logic_vector(31 downto 0);
      start  : in  std_logic;
      result : out std_logic_vector(31 downto 0);
      inf    : out std_logic;
      zero   : out std_logic;
      done   : out std_logic
      );
  end component;

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

  -- Connect last PE outputs to pairhmm outputs

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

  -- Result bus
  process(cr.clk)
    variable vbusm : prob;
    variable vbusi : prob;
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
          resm(K) <= (others => '0');
          resi(K) <= (others => '0');
        end if;
      end loop;

      -- OR everything, latency is 1
      vbusm := (others => '0');
      vbusi := (others => '0');
      for K in 0 to PAIRHMM_NUM_PES-1 loop
        vbusm := vbusm or resm(K);
        vbusi := vbusi or resi(K);
      end loop;

      -- Place on bus, latency is 2
      resbusm <= vbusm;
      resbusi <= vbusi;

      -- Check if last PE is at last cell update
      if pe_outs(PAIRHMM_NUM_PES-1).cell = PE_LAST then lastlast <= '1';
      else lastlast                                              <= '0';
      end if;

      lastlast1 <= lastlast;            -- match latency of 2
    end if;
  end process;


  gen_accumulator_wide : if POSIT_WIDE_ACCUMULATOR = 1 generate
    signal resaccum_out       : prob;
    signal resaccum_out_valid : std_logic;

    signal res_acc_zero : std_logic;

    type i_delay_type is array (0 to 4 * PE_ADD_CYCLES - 1) of prob;
    signal i_delay       : i_delay_type;
    signal i_valid_delay : std_logic_vector(5 * PE_ADD_CYCLES - 1 downto 0);

    signal acc : acc_state_wide := resetting;
  begin
    gen_es2_add : if POSIT_ES = 2 generate
      resaccum_m : positaccum_16 port map (
        clk    => cr.clk,
        rst    => res_rst,
        in1    => resbusm,
        start  => '1',
        result => addm_out,
        inf    => posit_infs(0),
        done   => addm_out_valid
        );

      resaccum_i : positaccum_16 port map (
        clk    => cr.clk,
        rst    => res_rst,
        in1    => resbusi,
        start  => '1',
        result => addi_out,
        inf    => posit_infs(1),
        done   => addi_out_valid
        );

      resaccum : positadd_4 port map (
        clk    => cr.clk,
        in1    => i_delay(4 * PE_ADD_CYCLES - 1),
        in2    => addm_out,
        start  => addm_out_valid and addi_out_valid,
        result => resaccum_out,
        inf    => posit_infs(2),
        done   => resaccum_out_valid
        );
    end generate;

    gen_es3_add : if POSIT_ES = 3 generate
      resaccum_m : positaccum_16_es3 port map (
        clk    => cr.clk,
        rst    => res_rst,
        in1    => resbusm,
        start  => '1',
        result => addm_out,
        inf    => posit_infs(0),
        done   => addm_out_valid
        );

      resaccum_i : positaccum_16_es3 port map (
        clk    => cr.clk,
        rst    => res_rst,
        in1    => resbusi,
        start  => '1',
        result => addi_out,
        inf    => posit_infs(1),
        done   => addi_out_valid
        );

      resaccum : positadd_4_es3 port map (
        clk    => cr.clk,
        in1    => i_delay(4 * PE_ADD_CYCLES - 1),
        in2    => addm_out,
        start  => addm_out_valid and addi_out_valid,
        result => resaccum_out,
        inf    => posit_infs(2),
        done   => resaccum_out_valid
        );
    end generate;

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
          i_delay(0) <= addi_out;
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

    res_acc <= resaccum_out when res_acc_zero = '0' else
               (others => '0');
  end generate;

  gen_accumulator : if POSIT_WIDE_ACCUMULATOR = 0 generate
    signal addm_ina, addm_inb, addi_ina, addi_inb                         : prob;
    signal addm_ina_valid, addm_inb_valid, addi_ina_valid, addi_inb_valid : std_logic;

    type i_delay_type is array (0 to 2 * PE_ADD_CYCLES-1) of prob;
    signal i_delay       : i_delay_type;
    signal i_valid_delay : std_logic_vector(2 * PE_ADD_CYCLES - 1 downto 0);

    signal acc : acc_state := resetting;
  begin

    gen_es2_add : if POSIT_ES = 2 generate
      add_m : positadd_8 port map (
        clk    => cr.clk,
        in1    => addm_ina,
        in2    => addm_inb,
        start  => addm_ina_valid and addm_inb_valid,
        result => addm_out,
        inf    => posit_infs(0),
        done   => addm_out_valid
        );
      add_i : positadd_8 port map (
        clk    => cr.clk,
        in1    => addi_ina,
        in2    => addi_inb,
        start  => addi_ina_valid and addi_inb_valid,
        result => addi_out,
        inf    => posit_infs(1),
        done   => addi_out_valid
        );
    end generate;

    gen_es3_add : if POSIT_ES = 3 generate
      add_m : positadd_8_es3 port map (
        clk    => cr.clk,
        in1    => addm_ina,
        in2    => addm_inb,
        start  => addm_ina_valid and addm_inb_valid,
        result => addm_out,
        inf    => posit_infs(0),
        done   => addm_out_valid
        );
      add_i : positadd_8_es3 port map (
        clk    => cr.clk,
        in1    => addi_ina,
        in2    => addi_inb,
        start  => addi_ina_valid and addi_inb_valid,
        result => addi_out,
        inf    => posit_infs(1),
        done   => addi_out_valid
        );
    end generate;

    process(cr.clk)
      variable rescounter : integer range 0 to PE_DEPTH := 0;
      variable prevlast   : std_logic;
    begin
      if rising_edge(cr.clk) then
        if cr.rst = '1' then
          acc           <= resetting;
          o.score_valid <= '0';
        else
          -- Delayed signals:
          i_valid_delay(0) <= lastlast1;
          i_delay(0)       <= resbusi;

          for K in 1 to 2*PE_ADD_CYCLES - 1 loop
            i_delay(K)       <= i_delay(K-1);
            i_valid_delay(K) <= i_valid_delay(K-1);
          end loop;

          -- Small state machine:
          case acc is
            when adding =>
              if lastlast = '0' and prevlast = '1' then
                acc     <= resetting;
                res_rst <= '1';
              end if;

            when resetting =>
              rescounter := rescounter + 1;
              if rescounter = PE_DEPTH then
                rescounter := 0;
                acc        <= adding;
                res_rst    <= '0';
              end if;

          end case;

          prevlast := lastlast1;

          o.score       <= addi_out;
          o.score_valid <= addi_out_valid;
        end if;
      end if;
    end process;

    res_acc <= addi_out when res_rst = '0' else
               (others => '0');

    addm_ina       <= res_acc;
    addm_ina_valid <= '1';

    addm_inb       <= resbusm;
    addm_inb_valid <= '1';

    addi_ina       <= addm_out;
    addi_ina_valid <= addm_out_valid;

    addi_inb       <= i_delay(2*PE_ADD_CYCLES-1);
    addi_inb_valid <= i_valid_delay(2*PE_ADD_CYCLES-1);
  end generate;

end architecture logic;
