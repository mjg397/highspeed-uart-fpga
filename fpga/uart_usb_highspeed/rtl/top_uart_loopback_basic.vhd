------------------------------------------------------------------------
-- Top-level hardware module for the basic, fifo-less UART-USB
-- transmission, specifically designed for validation via loopback
-- testing, but transferable across recieving and transmitting domains
------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity top_uart_loopback_basic is
    port (
        CLK100MHZ : in  std_logic;
        RESETN    : in  std_logic;
        uart_rx   : in  std_logic;
        uart_tx   : out std_logic
    );
end entity;

architecture rtl of top_uart_loopback_basic is

    -- UART parallel interface signals
    signal rx_data   : std_logic_vector(7 downto 0);  -- 8-bit parallel byte recieved from UART
    signal rx_stb    : std_logic;                     -- Indicator that rx_data is valid and to recieve
    signal tx_data   : std_logic_vector(7 downto 0);  -- 8-bit parallel byte to be transmitted by UART
    signal tx_stb    : std_logic;                     -- Request for UART to transmit tx_data
    signal tx_ack    : std_logic;                     -- Indicator that tx_data was accepted
    
    signal rst       : std_logic;                     -- Active-high reset

begin

    rst <= not RESETN; -- Convert board RESETN to active-high reset

    --------------------------------------------------------------------
    -- UART instance
    --------------------------------------------------------------------
    U_UART : entity work.uart
        generic map (
            baud            => 115200,    -- Experimentally determined max
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
    -- Simple loopback logic: when a byte is received, echo it back
    --------------------------------------------------------------------
    process (CLK100MHZ)
    begin
        if rising_edge(CLK100MHZ) then
            -- if reset signal is set, set tx_data to 0 and don't transmit data
            if rst = '1' then
                tx_stb    <= '0';
                tx_data   <= (others => '0');
            else
                -- If tx_data was accepted, no longer request transmision via strobe
                if tx_ack = '1' then
                    tx_stb <= '0';
                end if;

                -- If a new byte was recieved and not waiting to transmit, send byte back
                if (rx_stb = '1') and (tx_stb = '0') then
                    tx_data   <= rx_data;   -- echo back to source
                    tx_stb    <= '1';       -- request transmission
                end if;
            end if;
        end if;
    end process;
end architecture;
