library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
------------------------------------------------------------------------
-- Top-level hardware module for the basic, general fifo-based UART-USB
-- transmission, specifically designed for validation via loopback
-- testing, but transferable across recieving and transmitting domains
------------------------------------------------------------------------
entity top_uart_loopback_generic_fifo is
    port (
        CLK100MHZ : in  std_logic;
        RESETN    : in  std_logic;
        uart_rx   : in  std_logic;
        uart_tx   : out std_logic
    );
end entity;

architecture rtl of top_uart_loopback_generic_fifo is

    -- UART parallel interface signals
    signal rx_data        : std_logic_vector(7 downto 0);  -- 8-bit parallel byte recieved from UART
    signal rx_stb         : std_logic;                     -- Indicator that rx_data is valid and to recieve
    signal tx_data        : std_logic_vector(7 downto 0);  -- 8-bit parallel byte to be transmitted by UART
    signal tx_stb         : std_logic;                     -- Request for UART to transmit tx_data
    signal tx_ack         : std_logic;                     -- Indicator that tx_data was accepted

    signal rst            : std_logic;                     -- Active-high reset


    -- FIFO signals (8-bit FIFO)
    signal fifo_din       : std_logic_vector(7 downto 0);  -- FIFO input data
    signal fifo_dout      : std_logic_vector(7 downto 0);  -- FIFO output data
    signal fifo_wr_en     : std_logic;                     -- FIFO write enable
    signal fifo_rd_en     : std_logic;                     -- FIFO read enable
    signal fifo_full      : std_logic;                     -- Indicates if FIFO is unable to be written into
    signal fifo_empty     : std_logic;                     -- Indicates if FIFO is unable to be read from
    
    signal fifo_level     : std_logic_vector(9 downto 0);  -- How many entries are currently stored in FIFO (2^10=1024)

begin

    rst <= not RESETN; -- Convert board RESETN to active-high reset

    --------------------------------------------------------------------
    -- UART instance
    --------------------------------------------------------------------
    U_UART : entity work.uart
        generic map (
            baud            => 960000,    -- Experimentally determined max
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
    -- FIFO instance
    --------------------------------------------------------------------
    U_FIFO : entity work.GENERIC_FIFO
        generic map (
            FIFO_WIDTH => 8,
            FIFO_DEPTH => 1024
        )
        port map (
            clock      => CLK100MHZ,
            reset      => rst,
            write_data => fifo_din,
            read_data  => fifo_dout,
            write_en   => fifo_wr_en,
            read_en    => fifo_rd_en,
            full       => fifo_full,
            empty      => fifo_empty,
            level      => fifo_level
        );

    --------------------------------------------------------------------
    -- FIFO-level loopback glue
    --------------------------------------------------------------------
    process (CLK100MHZ)
    begin
        if rising_edge(CLK100MHZ) then
            if rst = '1' then
                tx_stb      <= '0';
                tx_data     <= (others => '0');

                fifo_din    <= (others => '0');
                fifo_wr_en  <= '0';
                fifo_rd_en  <= '0';
            else
                -- defaults: pulses are 0 unless we assert them this cycle
                fifo_wr_en <= '0';
                fifo_rd_en <= '0';

                -- If UART accepted a byte, drop the strobe (same as your original)
                if tx_ack = '1' then
                    tx_stb <= '0';
                end if;

                ----------------------------------------------------------------
                -- RX -> FIFO write
                ----------------------------------------------------------------
                if (rx_stb = '1') and (fifo_full = '0') then
                    fifo_din   <= rx_data;
                    fifo_wr_en <= '1';
                end if;

                ----------------------------------------------------------------
                -- FIFO read -> UART TX
                -- Only start a TX when we're not already holding tx_stb high
                ----------------------------------------------------------------
                if (tx_stb = '0') and (fifo_empty = '0') then
                    -- fifo_dout is already the next byte at current read_pointer
                    tx_data    <= fifo_dout;
                    tx_stb     <= '1';     -- request transmit
                    fifo_rd_en <= '1';     -- advance FIFO pointer (consume)
                end if;
            end if;
        end if;
    end process;
end architecture;
