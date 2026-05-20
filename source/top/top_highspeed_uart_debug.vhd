------------------------------------------------------------------------
-- Top-Level UART FIFO Loopback
--
-- Receives bytes from the UART RX path, stores them in an 8-bit FIFO,
-- then transmits them back through the UART TX path.
--
-- This design provides a simple hardware loopback that is intended for
-- testing and validating UART receive, FIFO buffering, and UART
-- transmit behavior on FPGA. 
--
-- Default configuration of this top level uses the fractional-baud UART
-- implementation (uart_frac_debug). To use the original integer-divider UART
-- implementation, replace:
--     entity work.uart_frac_debug
-- with:
--     entity work.uart_int_debug
-- in the UART instantiation below.
--
-- This debug variant of the top level allows internal UART timing, baud
-- tick, spacing, synchronization, and state-machine signals to be
-- exposed to Vivado ILA for hardware debugging and timing analysis.
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
    
    signal rst            : std_logic;

    -- debug signals
    signal dbg_rx_baud_tick     : std_logic;
    signal dbg_uart_rx_bit      : std_logic;
    signal dbg_uart_rx_state    : std_logic_vector(1 downto 0);
    signal dbg_uart_rx_spacing  : std_logic_vector(3 downto 0); -- or exact width
    signal dbg_uart_rx_bit_tick : std_logic;
    signal dbg_uart_rx_count    : std_logic_vector(2 downto 0);
    signal dbg_uart_rx_data_vec : std_logic_vector(7 downto 0);
    signal dbg_uart_rx_data_sr  : std_logic_vector(1 downto 0);

    -- UART parallel interface signals
    signal rx_data        : std_logic_vector(7 downto 0);
    signal rx_stb         : std_logic;
    signal tx_data        : std_logic_vector(7 downto 0);
    signal tx_stb         : std_logic;
    signal tx_ack         : std_logic;

    -- FIFO signals
    signal fifo_din       : std_logic_vector(7 downto 0);
    signal fifo_dout      : std_logic_vector(7 downto 0);
    signal fifo_wr_en     : std_logic;
    signal fifo_rd_en     : std_logic;
    signal fifo_full      : std_logic;
    signal fifo_empty     : std_logic;

begin
    -- Convert active-low board reset to active-high internal reset.
    rst <= not RESETN; 

    --------------------------------------------------------------------
    -- UART instance
    --------------------------------------------------------------------
    U_UART : entity work.uart_frac_debug
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
            
            -- Debug signals
            dbg_rx_baud_tick     => dbg_rx_baud_tick,
            dbg_uart_rx_bit      => dbg_uart_rx_bit,
            dbg_uart_rx_state    => dbg_uart_rx_state,
            dbg_uart_rx_spacing  => dbg_uart_rx_spacing,
            dbg_uart_rx_bit_tick => dbg_uart_rx_bit_tick,
            dbg_uart_rx_count    => dbg_uart_rx_count,
            dbg_uart_rx_data_vec => dbg_uart_rx_data_vec,
            dbg_uart_rx_data_sr  => dbg_uart_rx_data_sr 
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
    -- ILA instance
    --------------------------------------------------------------------
    U_ILA : entity work.ila_1
    port map (
        clk     => CLK100MHZ,
        probe0  => (0 => uart_rx),
        probe1  => (0 => dbg_rx_baud_tick),
        probe2  => (0 => dbg_uart_rx_bit),
        probe3  => dbg_uart_rx_state,
        probe4  => dbg_uart_rx_spacing,
        probe5  => (0 => dbg_uart_rx_bit_tick),
        probe6  => dbg_uart_rx_count,
        probe7  => dbg_uart_rx_data_vec,
        probe8  => (0 => rx_stb),
        probe9  => rx_data,
        probe10 => (0 => fifo_wr_en),
        probe11 => fifo_din,
        probe12 => (0 => uart_rx),
        probe13 => dbg_uart_rx_data_sr
    );
        
    --------------------------------------------------------------------
    -- FIFO loopback logic
    --------------------------------------------------------------------
    loopback_proc : process (CLK100MHZ)
    begin
        if rising_edge(CLK100MHZ) then
            if rst = '1' then
                tx_stb      <= '0';
                tx_data     <= (others => '0');

                fifo_din    <= (others => '0');
                fifo_wr_en  <= '0';
                fifo_rd_en  <= '0';
            else
                -- Default pulse signals low unless asserted in this cycle.
                fifo_wr_en <= '0';
                fifo_rd_en <= '0';

                -- Clear transmit request once UART accepts the byte.
                if tx_ack = '1' then
                    tx_stb <= '0';
                end if;

                ----------------------------------------------------------------
                -- RX -> FIFO write
                ----------------------------------------------------------------
                -- Store each valid received UART byte unless the FIFO is full.
                if (rx_stb = '1') and (fifo_full = '0') then
                    fifo_din   <= rx_data;
                    fifo_wr_en <= '1';
                end if;

                ----------------------------------------------------------------
                -- FIFO read -> UART TX
                ----------------------------------------------------------------
                -- Start a new UART transmit when we're not already requesting one,
                -- and there's a byte available in the FIFO.
                if (tx_stb = '0') and (fifo_empty = '0') then
                    tx_data    <= fifo_dout;
                    tx_stb     <= '1';
                    fifo_rd_en <= '1';
                end if;
            end if;
        end if;
    end process;
end architecture;
