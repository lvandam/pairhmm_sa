library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package functions is

  -- clock/reset
  type cr_in is record
    clk : std_logic;
    rst : std_logic;
  end record;

  constant BP_SIZE : natural := 3;
  type bp_type is (BP_A, BP_C, BP_G, BP_T, BP_N, BP_STOP, BP_IGNORE);

  function endian_swap (a : in std_logic_vector) return std_logic_vector;
  function is_full (a     : in std_logic_vector; b : in std_logic_vector) return std_logic;
  function is_full (a     : in unsigned; b : in unsigned) return std_logic;
  function is_empty (a    : in std_logic_vector; b : in std_logic_vector) return std_logic;
  function is_empty (a    : in unsigned; b : in unsigned) return std_logic;
  function idx (a         : in std_logic_vector) return integer;
  function idx (a         : in unsigned) return integer;
  function slv (a         : in integer; b : in natural) return std_logic_vector;
  function slv (a         : in unsigned) return std_logic_vector;
  function sext (a        : in unsigned; b : in natural) return unsigned;
  function usign (a           : in integer; b : in natural) return unsigned;
  function usign (a           : in std_logic_vector) return unsigned;
  function usign (a           : in std_logic) return unsigned;
  function l (a           : in boolean) return std_logic;
  function log2 (a        : in natural) return natural;
  function log2e (a       : in natural) return natural;
  function ones (a        : in std_logic_vector) return natural;
  function slv8bp (a      : in std_logic_vector(7 downto 0)) return bp_type;
  function slv4bp (a      : in std_logic_vector(3 downto 0)) return bp_type;
  function slv3bp (a      : in std_logic_vector(2 downto 0)) return bp_type;
  function slv8bpslv3 (a  : in std_logic_vector(7 downto 0)) return std_logic_vector;
  function slv8char (a    : in std_logic_vector(7 downto 0)) return character;
  function slv8string (a  : in std_logic_vector(7 downto 0)) return string;
  function bpslv3 (a      : in bp_type) return std_logic_vector;

end package functions;

package body functions is

  function endian_swap (a : in std_logic_vector) return std_logic_vector is
    variable result : std_logic_vector(a'range);
    constant bytes  : natural := a'length / 8;
  begin
    for i in 0 to bytes - 1 loop
      result(8 * i + 7 downto 8 * i) := a((bytes - 1 - i) * 8 + 7 downto (bytes - 1 - i) * 8);
    end loop;
    return result;
  end function endian_swap;

  function is_full (a : in std_logic_vector; b : in std_logic_vector) return std_logic is
    variable result : std_logic;
  begin
    if a(a'high) /= b(b'high) and a(a'high - 1 downto a'low) = b(b'high - 1 downto b'low) then
      result := '1';
    else
      result := '0';
    end if;
    return result;
  end function is_full;

  function is_full (a : in unsigned; b : in unsigned) return std_logic is
    variable result : std_logic;
  begin
    if a(a'high) /= b(b'high) and a(a'high - 1 downto a'low) = b(b'high - 1 downto b'low) then
      result := '1';
    else
      result := '0';
    end if;
    return result;
  end function is_full;

  function is_empty (a : in std_logic_vector; b : in std_logic_vector) return std_logic is
    variable result : std_logic;
  begin
    if a = b then
      result := '1';
    else
      result := '0';
    end if;
    return result;
  end function is_empty;

  function is_empty (a : in unsigned; b : in unsigned) return std_logic is
    variable result : std_logic;
  begin
    if a = b then
      result := '1';
    else
      result := '0';
    end if;
    return result;
  end function is_empty;

  function idx (a : in std_logic_vector) return integer is
  begin
    return to_integer(unsigned(a));
  end function idx;

  function idx (a : in unsigned) return integer is
  begin
    return to_integer(a);
  end function idx;

  function slv (a : in integer; b : in natural) return std_logic_vector is
  begin
    return std_logic_vector(to_unsigned(a, b));
  end function slv;

  function slv (a : in unsigned) return std_logic_vector is
  begin
    return std_logic_vector(a);
  end function slv;

  function sext (a : in unsigned; b : in natural) return unsigned is
    variable result : unsigned(b-1 downto 0);
  begin
    result(a'high downto 0)     := a;
    result(b-1 downto a'high+1) := (others => a(a'high));
    return result;
  end function sext;

  function usign (a : in integer; b : in natural) return unsigned is
  begin
    return to_unsigned(a, b);
  end function usign;

  function usign (a : in std_logic_vector) return unsigned is
  begin
    return unsigned(a);
  end function usign;

  function usign (a : in std_logic) return unsigned is
    variable result : unsigned(0 downto 0);
  begin
    if a = '1' then
      result := usign("1");
    else
      result := usign("0");
    end if;
    return result;
  end function usign;

  function l (a : boolean) return std_logic is
    variable result : std_logic;
  begin
    if a then
      result := '1';
    else
      result := '0';
    end if;
    return result;
  end function l;

  function log2 (a : in natural) return natural is
    variable b      : natural := a;
    variable result : natural := 0;
  begin
    while b > 1 loop
      result := result + 1;
      b      := b / 2;
    end loop;
    return result;
  end function log2;

  function log2e (a : in natural) return natural is
    variable b      : natural := a;
    variable result : natural := 1;
  begin
    while b > 1 loop
      result := result + 1;
      b      := b / 2;
    end loop;
    return result;
  end function log2e;

  function ones (a : in std_logic_vector) return natural is
    variable result : natural := 0;
  begin
    for i in a'range loop
      if a(i) = '1' then
        result := result + 1;
      end if;
    end loop;
    return result;
  end function ones;

  function slv8bp (a : in std_logic_vector(7 downto 0)) return bp_type is
  begin
    case a is
      when "01000001" => return BP_A;       -- 'A'
      when "01000011" => return BP_C;       -- 'C'
      when "01000111" => return BP_G;       -- 'G'
      when "01010100" => return BP_T;       -- 'T'
      when "01001110" => return BP_N;       -- 'N'
      when "01010011" => return BP_STOP;    -- 'S'
      when others     => return BP_IGNORE;  --
    end case;
  end function slv8bp;

  function slv4bp (a : in std_logic_vector(3 downto 0)) return bp_type is
  begin
    case a is
      when "0001" => return BP_A;       -- 0
      when "0010" => return BP_C;       -- 1
      when "0011" => return BP_G;       -- 2
      when "0100" => return BP_T;       -- 3
      when "0101" => return BP_N;       -- 4
      when "0000" => return BP_STOP;    --
      when others => return BP_IGNORE;  --
    end case;
  end function slv4bp;

  function slv3bp (a : in std_logic_vector(2 downto 0)) return bp_type is
  begin
    case a is
      when "001"  => return BP_A;
      when "010"  => return BP_C;
      when "011"  => return BP_G;
      when "100"  => return BP_T;
      when "101"  => return BP_N;
      when "000"  => return BP_STOP;
      when others => return BP_IGNORE;
    end case;
  end function slv3bp;

  function slv8bpslv3 (a : in std_logic_vector(7 downto 0)) return std_logic_vector is
  begin
    case a is
      when "01000001" => return "001";  -- 'A'
      when "01000011" => return "010";  -- 'C'
      when "01000111" => return "011";  -- 'G'
      when "01010100" => return "100";  -- 'T'
      when "01001110" => return "101";  -- 'N'
      when "01010011" => return "000";  -- 'S'
      when others     => return "111";  --
    end case;
  end function slv8bpslv3;

  function bpslv3 (a : in bp_type) return std_logic_vector is
  begin
    case a is
      when BP_A      => return "001";
      when BP_C      => return "010";
      when BP_G      => return "011";
      when BP_T      => return "100";
      when BP_N      => return "101";
      when BP_STOP   => return "000";
      when BP_IGNORE => return "111";
    end case;
  end function bpslv3;

  function slv8char (a : in std_logic_vector(7 downto 0)) return character is
  begin
    case a is
      when "01000001" => return 'A';
      when "01000011" => return 'C';
      when "01000111" => return 'G';
      when "01010100" => return 'T';
      when "01001110" => return 'N';
      when "01010011" => return 'S';
      when others     => return 'I';
    end case;
  end function slv8char;

  function slv8string (a : in std_logic_vector(7 downto 0)) return string is
  begin
    case a is
      when "01000001" => return "A";
      when "01000011" => return "C";
      when "01000111" => return "G";
      when "01010100" => return "T";
      when "01001110" => return "N";
      when "01010011" => return "S";
      when others     => return "I";
    end case;
  end function slv8string;

end package body functions;
