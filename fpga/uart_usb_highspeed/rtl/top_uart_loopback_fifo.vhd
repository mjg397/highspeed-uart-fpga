library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity top_uart_loopback_fifo is
    port (
        CLK100MHZ : in  std_logic;
        RESETN    : in  std_logic;
        uart_rx   : in  std_logic;
        uart_tx   : out std_logic;
        led       : out std_logic_vector(7 downto 0)
    );
end entity;

architecture rtl of top_uart_loopback_fifo is

    -- UART parallel interface signals
    signal rx_data        : std_logic_vector(7 downto 0);
    signal rx_stb         : std_logic;
    signal tx_data        : std_logic_vector(7 downto 0);
    signal tx_stb         : std_logic;
    signal tx_ack         : std_logic;

    -- Store last received byte for LEDs
    signal last_byte      : std_logic_vector(7 downto 0) := (others => '0');

    -- Active-high reset for UART core
    signal rst            : std_logic;

begin

    -- Convert board RESETN (active low) to active-high reset
    rst <= not RESETN;

    --------------------------------------------------------------------
    -- UART instance (from GitHub)
    --------------------------------------------------------------------
    U_UART : entity work.uart
        generic map (
            baud            => 115200,
            clock_frequency => 100000000  -- 100 MHz board clock
        )
        port map (
            clock               => CLK100MHZ,
            reset               => rst,
            data_stream_in      => tx_data,
            data_stream_in_stb  => tx_stb,
            data_stream_in_ack  => tx_ack,
            data_stream_out     => rx_data,
            data_stream_out_stb => rx_stb,
            tx                  => uart_tx,
            rx                  => uart_rx
        );

    --------------------------------------------------------------------
    -- Simple loopback logic:
    -- whenever a byte is received, echo it back and show it on LEDs
    --------------------------------------------------------------------
    process (CLK100MHZ)
    begin
        if rising_edge(CLK100MHZ) then
            if rst = '1' then
                tx_stb    <= '0';
                tx_data   <= (others => '0');
                last_byte <= (others => '0');
            else
                -- default: don't request a transmit
                if tx_ack = '1' then
                    -- UART accepted the byte, drop the strobe
                    tx_stb <= '0';
                end if;

                -- New byte received?
                if rx_stb = '1' then
                    last_byte <= rx_data;   -- show on LEDs
                    tx_data   <= rx_data;   -- echo back
                    tx_stb    <= '1';       -- request transmit
                end if;
            end if;
        end if;
    end process;

    led <= last_byte;

end architecture;
