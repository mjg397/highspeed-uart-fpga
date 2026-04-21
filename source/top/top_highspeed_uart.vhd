------------------------------------------------------------------------
-- Top-level hardware module for FIFO-based UART loopback (fixed FIFO read timing)
-- Key fix: do NOT use fifo_dout in the same cycle you assert fifo_rd_en.
-- Instead: pop FIFO, then on the next cycle send the (now-valid) fifo_dout.
------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity top_uart_loopback_fifo is
    port (
        CLK100MHZ : in  std_logic;
        RESETN    : in  std_logic;
        uart_rx   : in  std_logic;
        uart_tx   : out std_logic
    );
end entity;

architecture rtl of top_uart_loopback_fifo is
    -- UART parallel interface signals
    signal rx_data        : std_logic_vector(7 downto 0);
    signal rx_stb         : std_logic;
    signal tx_data        : std_logic_vector(7 downto 0);
    signal tx_stb         : std_logic;
    signal tx_ack         : std_logic;

    signal rst            : std_logic;

    -- FIFO signals (8-bit FIFO)
    signal fifo_din       : std_logic_vector(7 downto 0);
    signal fifo_dout      : std_logic_vector(7 downto 0);
    signal fifo_wr_en     : std_logic;
    signal fifo_rd_en     : std_logic;
    signal fifo_full      : std_logic;
    signal fifo_empty     : std_logic;
    signal fifo_level     : std_logic_vector(9 downto 0);

begin

    rst <= not RESETN; -- Convert board RESETN to active-high reset

    --------------------------------------------------------------------
    -- UART instance
    --------------------------------------------------------------------
    U_UART : entity work.uart
        generic map (
            baud            => 12000000,
            clock_frequency => 100000000
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
            rx                  => uart_rx,
        );

    --------------------------------------------------------------------
    -- FIFO instance
    --------------------------------------------------------------------
U_FIFO : entity work.generic_fifo_IP
        port map (
            rst         => rst,
            wr_clk      => CLK100MHZ,
            rd_clk      => CLK100MHZ,
            din         => fifo_din,
            wr_en       => fifo_wr_en,
            rd_en       => fifo_rd_en,
            dout        => fifo_dout,
            full        => fifo_full,
            empty       => fifo_empty,
            wr_rst_busy => open,
            rd_rst_busy => open
        );
        
    --------------------------------------------------------------------
    -- FIFO loopback logic
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
