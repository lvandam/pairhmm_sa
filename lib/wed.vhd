library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.functions.all;

package wed is

  type wed_type is record
    status  : std_logic_vector(7 downto 0);
    wed00_a : std_logic_vector(7 downto 0);
    wed00_b : std_logic_vector(15 downto 0);
    wed00_c : std_logic_vector(31 downto 0);

    source : unsigned(63 downto 0);

    destination : unsigned(63 downto 0);

    batch_size : unsigned(31 downto 0);
    pair_size  : unsigned(31 downto 0);

    padded_size : unsigned(31 downto 0);
    batches     : unsigned(31 downto 0);
    batches_total : unsigned(31 downto 0);

    wed05 : std_logic_vector(63 downto 0);
    wed06 : std_logic_vector(63 downto 0);
    wed07 : std_logic_vector(63 downto 0);
    wed08 : std_logic_vector(63 downto 0);
    wed09 : std_logic_vector(63 downto 0);
    wed10 : std_logic_vector(63 downto 0);
    wed11 : std_logic_vector(63 downto 0);
    wed12 : std_logic_vector(63 downto 0);
    wed13 : std_logic_vector(63 downto 0);
    wed14 : std_logic_vector(63 downto 0);
    wed15 : std_logic_vector(63 downto 0);
  end record;

  procedure wed_parse (signal data : in std_logic_vector(1023 downto 0); variable wed : out wed_type);

end package wed;

package body wed is

  procedure wed_parse (signal data : in std_logic_vector(1023 downto 0); variable wed : out wed_type) is
  begin
    wed.status  := data(7 downto 0);
    wed.wed00_a := data(15 downto 8);
    wed.wed00_b := data(31 downto 16);
    wed.wed00_c := data(63 downto 32);

    wed.source      := usign(data(127 downto 64));
    wed.destination := usign(data(191 downto 128));

    wed.batch_size := usign(data(223 downto 192));
    wed.pair_size  := usign(data(255 downto 224));

    wed.padded_size := usign(data(287 downto 256));
    wed.batches     := usign(data(319 downto 288));
    wed.batches     := (others => '0');

    wed.wed05 := data(383 downto 320);
    wed.wed06 := data(447 downto 384);
    wed.wed07 := data(511 downto 448);
    wed.wed08 := data(575 downto 512);
    wed.wed09 := data(639 downto 576);
    wed.wed10 := data(703 downto 640);
    wed.wed11 := data(767 downto 704);
    wed.wed12 := data(831 downto 768);
    wed.wed13 := data(895 downto 832);
    wed.wed14 := data(959 downto 896);
    wed.wed15 := data(1023 downto 960);
  end procedure wed_parse;

end package body wed;
