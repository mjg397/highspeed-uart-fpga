-- ================================================================
-- GENERIC FIFO
-- ================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

entity GENERIC_FIFO is
    generic (
        FIFO_WIDTH  positive = 32;
        FIFO_DEPTH  positive = 1024
    );
    port (
        clock        in std_logic;
        reset        in std_logic;
        write_data   in std_logic_vector(FIFO_WIDTH-1 downto 0);
        read_data    out std_logic_vector(FIFO_WIDTH-1 downto 0);
        write_en     in std_logic;
        read_en      in std_logic;
        full         out std_logic;
        empty        out std_logic;
        level        out std_logic_vector(
            integer(ceil(log2(real(FIFO_DEPTH))))-1 downto 0
        )
    );
end entity;

architecture RTL of GENERIC_FIFO is
    function get_fifo_level(
        write_pointer    unsigned;
        read_pointer     unsigned;
        depth            positive) return integer is
    begin
        if write_pointer  read_pointer then
            return to_integer(write_pointer - read_pointer);
        elsif write_pointer = read_pointer then
            return 0;
        else
            return (depth - to_integer(read_pointer)) +
                   to_integer(write_pointer);
        end if;
    end function;

    type memory is array (0 to FIFO_DEPTH-1) of
        std_logic_vector(FIFO_WIDTH-1 downto 0);

    signal fifo_memory  memory = (others = (others = '0'));
    signal read_pointer, write_pointer 
        unsigned(integer(ceil(log2(real(FIFO_DEPTH))))-1 downto 0)
        = (others = '0');

    signal fifo_empty  std_logic = '1';
    signal fifo_full   std_logic = '0';
begin
    full  = fifo_full;
    empty = fifo_empty;

    FIFO_FLAGS  process(write_pointer, read_pointer)
        variable lev  integer range 0 to FIFO_DEPTH-1;
    begin
        lev = get_fifo_level(write_pointer, read_pointer, FIFO_DEPTH);
        level = std_logic_vector(to_unsigned(lev, level'length));

        fifo_full  = '1' when lev = FIFO_DEPTH-1 else '0';
        fifo_empty = '1' when lev = 0 else '0';
    end process;

    FIFO_LOGIC  process(clock)
    begin
        if rising_edge(clock) then
            if reset = '1' then
                write_pointer = (others = '0');
                read_pointer  = (others = '0');
            else
                if write_en = '1' and fifo_full = '0' then
                    fifo_memory(to_integer(write_pointer)) = write_data;
                    if write_pointer = FIFO_DEPTH-1 then
                        write_pointer = (others = '0');
                    else
                        write_pointer = write_pointer + 1;
                    end if;
                end if;

                if read_en = '1' and fifo_empty = '0' then
                    if read_pointer = FIFO_DEPTH-1 then
                        read_pointer = (others = '0');
                    else
                        read_pointer = read_pointer + 1;
                    end if;
                end if;
            end if;
        end if;
    end process;

    read_data = fifo_memory(to_integer(read_pointer));
end architecture;

-- ================================================================
-- UART
-- ================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

entity uart is
    generic (
        baud             positive;
        clock_frequency  positive
    );
    port (
        clock                in  std_logic;
        reset                in  std_logic;
        data_stream_in       in  std_logic_vector(7 downto 0);
        data_stream_in_stb   in  std_logic;
        data_stream_in_ack   out std_logic;
        data_stream_out      out std_logic_vector(7 downto 0);
        data_stream_out_stb  out std_logic;
        tx                   out std_logic;
        rx                   in  std_logic
    );
end uart;

architecture rtl of uart is
    constant c_tx_div  integer = clock_frequency  baud;
    constant c_rx_div  integer = clock_frequency  (baud  16);

    signal tx_cnt  integer = 0;
    signal rx_cnt  integer = 0;

    signal tx_shift  std_logic_vector(9 downto 0) = (others = '1');
    signal tx_busy   std_logic = '0';

    signal rx_shift  std_logic_vector(7 downto 0) = (others = '0');
    signal rx_bit    integer range 0 to 9 = 0;
    signal rx_busy   std_logic = '0';

    signal tx_tick, rx_tick  std_logic = '0';
begin
    tx = tx_shift(0);

    data_stream_out     = rx_shift;
    data_stream_out_stb = '1' when (rx_busy = '0' and rx_bit = 9) else '0';

    -- TX baud
    process(clock)
    begin
        if rising_edge(clock) then
            if reset = '1' then
                tx_cnt = 0;
                tx_tick = '0';
            elsif tx_cnt = c_tx_div then
                tx_cnt = 0;
                tx_tick = '1';
            else
                tx_cnt = tx_cnt + 1;
                tx_tick = '0';
            end if;
        end if;
    end process;

    -- RX baud
    process(clock)
    begin
        if rising_edge(clock) then
            if reset = '1' then
                rx_cnt = 0;
                rx_tick = '0';
            elsif rx_cnt = c_rx_div then
                rx_cnt = 0;
                rx_tick = '1';
            else
                rx_cnt = rx_cnt + 1;
                rx_tick = '0';
            end if;
        end if;
    end process;

    -- TX logic
    process(clock)
    begin
        if rising_edge(clock) then
            data_stream_in_ack = '0';
            if reset = '1' then
                tx_busy = '0';
                tx_shift = (others = '1');
            elsif tx_busy = '0' and data_stream_in_stb = '1' then
                tx_shift = '1' & data_stream_in & '0';
                tx_busy = '1';
                data_stream_in_ack = '1';
            elsif tx_busy = '1' and tx_tick = '1' then
                tx_shift = '1' & tx_shift(9 downto 1);
                if tx_shift = (others = '1') then
                    tx_busy = '0';
                end if;
            end if;
        end if;
    end process;
end architecture;

-- ================================================================
-- TOP LEVEL
-- ================================================================
library ieee;
use ieee.std_logic_1164.all;

entity top_uart_loopback_fifo is
    port (
        CLK100MHZ  in  std_logic;
        RESETN     in  std_logic;
        uart_rx    in  std_logic;
        uart_tx    out std_logic;
        led        out std_logic_vector(7 downto 0)
    );
end entity;

architecture rtl of top_uart_loopback_fifo is
    signal rx_data   std_logic_vector(7 downto 0);
    signal rx_stb    std_logic;
    signal tx_data   std_logic_vector(7 downto 0);
    signal tx_stb    std_logic;
    signal tx_ack    std_logic;
    signal rst       std_logic;
begin
    rst = not RESETN;

    U_UART  entity work.uart
        generic map (
            baud = 115200,
            clock_frequency = 100000000
        )
        port map (
            clock               = CLK100MHZ,
            reset               = rst,
            data_stream_in      = tx_data,
            data_stream_in_stb  = tx_stb,
            data_stream_in_ack  = tx_ack,
            data_stream_out     = rx_data,
            data_stream_out_stb = rx_stb,
            tx                  = uart_tx,
            rx                  = uart_rx
        );

    process(CLK100MHZ)
    begin
        if rising_edge(CLK100MHZ) then
            if rst = '1' then
                tx_stb = '0';
                led    = (others = '0');
            else
                if tx_ack = '1' then
                    tx_stb = '0';
                end if;
                if rx_stb = '1' then
                    tx_data = rx_data;
                    tx_stb  = '1';
                    led     = rx_data;
                end if;
            end if;
        end if;
    end process;
end architecture;

-- ================================================================
-- TESTBENCH
-- ================================================================
library ieee;
use ieee.std_logic_1164.all;

entity tb_top_uart_loopback_fifo is
end entity;

architecture sim of tb_top_uart_loopback_fifo is
    constant CLK_PERIOD  time = 10 ns;
    constant BIT_TIME    time = 1 sec  115200;

    signal clk     std_logic = '0';
    signal resetn  std_logic = '0';
    signal rx      std_logic = '1';
    signal tx      std_logic;
    signal led     std_logic_vector(7 downto 0);

    procedure uart_send(signal r  out std_logic;
                        constant b  std_logic_vector(7 downto 0)) is
    begin
        r = '0'; wait for BIT_TIME;
        for i in 0 to 7 loop
            r = b(i); wait for BIT_TIME;
        end loop;
        r = '1'; wait for BIT_TIME;
    end procedure;
begin
    clk = not clk after CLK_PERIOD2;

    dut  entity work.top_uart_loopback_fifo
        port map (
            CLK100MHZ = clk,
            RESETN    = resetn,
            uart_rx   = rx,
            uart_tx   = tx,
            led       = led
        );

    process
    begin
        resetn = '0';
        wait for 200 ns;
        resetn = '1';
        wait for 1 ms;

        uart_send(rx, x55);
        wait for 2 ms;

        uart_send(rx, xA3);
        wait for 2 ms;

        uart_send(rx, xF0);
        wait for 2 ms;

        report SIM DONE;
        wait;
    end process;
end architecture;
