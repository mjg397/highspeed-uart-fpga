-------------------------------------------------------------------------------
-- High-Speed UART (up to ~12 Mbaud) [Debug Version]
--
-- Author: Michael Grillo
-- Based on original UART design by Peter Bennett:
-- https://github.com/pabennett/uart
--
-- Description:
--   Implements a fully synchronous UART transmitter and receiver for serial
--   communication between an FPGA and external devices (e.g., FTDI USB-UART).
--   Converts between parallel byte streams and serialized UART data using a
--   streaming interface (TX handshake, RX valid strobe).
--
-- Operation:
--   • TX: Accepts input bytes via strobe/ack handshake and transmits
--         start bit, 8 data bits (LSB first), and stop bit at 1x baud
--   • RX: Uses 8x oversampling to detect incoming data and reconstruct bytes
--   • Start-bit confirmation (half-bit delay) aligns sampling to mid-bit
--   • Bit-spacing counter generates a 1x sampling tick from oversample ticks
--   • RX FSM shifts in data and asserts a one-cycle valid strobe on completion
--
-- Timing Architecture:
--   • Clock dividers generate TX (1x) and RX (8x) baud ticks from system clock
--   • RX sampling is aligned to bit centers for improved timing margin
--   • All logic is synchronous to the FPGA clock (no asynchronous domains)
--
-- Enhancements:
--   • Improved RX timing alignment for consistent mid-bit sampling
--   • Added start-bit confirmation (half-bit delay)
--   • Refined oversample spacing to ensure accurate bit-period timing
--   • Corrected baud/oversample counter behavior for precise timing
--   • Updated RX synchronizer to run every clock cycle (improved CDC)
--   • Simplified RX datapath by removing input filtering
--   • Verified reliable operation up to ~12 Mbaud on FPGA + FTDI interface
--
-- Debug:
--   Includes internal debug signals for ILA-based verification.
--   These can be removed for non-debug / production builds.
--
-- Notes:
--   • RX uses fixed 8x oversampling
--   • TX operates at 1x baud rate
--   • Designed to maintain reliable sampling at high baud rates
-------------------------------------------------------------------------------

library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;
    use ieee.math_real.all;

entity uart is
    generic (
        baud                : positive;
        clock_frequency     : positive
    );
    port (
        clock               : in  std_logic;
        reset               : in  std_logic;
        data_stream_in      : in  std_logic_vector(7 downto 0);
        data_stream_in_stb  : in  std_logic;
        data_stream_in_ack  : out std_logic;
        data_stream_out     : out std_logic_vector(7 downto 0);
        data_stream_out_stb : out std_logic;
        tx                  : out std_logic;
        rx                  : in  std_logic;
        
        -- Debug signals
        dbg_rx_baud_tick     : out std_logic;
        dbg_uart_rx_bit      : out std_logic;
        dbg_uart_rx_state    : out std_logic_vector(1 downto 0);
        dbg_uart_rx_spacing  : out std_logic_vector(3 downto 0);
        dbg_uart_rx_bit_tick : out std_logic;
        dbg_uart_rx_count    : out std_logic_vector(2 downto 0);
        dbg_uart_rx_data_vec : out std_logic_vector(7 downto 0);
        dbg_uart_rx_data_sr  : out std_logic_vector(1 downto 0)
    );
end uart;

architecture rtl of uart is

    ---------------------------------------------------------------------------
    -- BAUD GENERATION TIMING CONSTANTS
    ---------------------------------------------------------------------------
    constant oversample     : integer := 8;
    constant c_tx_div       : integer := clock_frequency / baud;
    constant c_rx_div       : integer := clock_frequency / (baud * oversample);

    constant c_tx_div_width : integer := integer(log2(real(c_tx_div))) + 1;
    constant c_rx_div_width : integer := integer(log2(real(c_rx_div))) + 1;
    constant c_rx_spc_width : integer := integer(log2(real(oversample))) + 1;

    constant half_bit_count : integer := oversample/2 - 1;
    
    constant c_tx_rem : integer := clock_frequency mod baud;
    constant c_rx_rem : integer := clock_frequency mod baud;
    constant c_tx_den : integer := baud;
    constant c_rx_den : integer := baud;

    
    ---------------------------------------------------------------------------
    -- BAUD GENERATION SIGNALS
    ---------------------------------------------------------------------------
    signal tx_baud_counter : unsigned(c_tx_div_width - 1 downto 0) := (others => '0');
    signal tx_baud_tick    : std_logic := '0';

    signal rx_baud_counter : unsigned(c_rx_div_width - 1 downto 0) := (others => '0');
    signal rx_baud_tick    : std_logic := '0';
    
     -- Fractional baud divider signals
    signal tx_rem_accum : integer range 0 to clock_frequency := 0;
    signal tx_div_adj   : integer range 0 to 1 := 0;
    signal rx_rem_accum : integer range 0 to clock_frequency := 0;
    signal rx_div_adj   : integer range 0 to 1 := 0;

    ---------------------------------------------------------------------------
    -- TRANSMITTER SIGNALS
    ---------------------------------------------------------------------------
    type uart_tx_states is (
        tx_send_start_bit,
        tx_send_data,
        tx_send_stop_bit
    );

    signal uart_tx_state        : uart_tx_states := tx_send_start_bit;
    signal uart_tx_data_vec     : std_logic_vector(7 downto 0) := (others => '0');
    signal uart_tx_data         : std_logic := '1';
    signal uart_tx_count        : unsigned(2 downto 0) := (others => '0');
    signal uart_rx_data_in_ack  : std_logic := '0';

    ---------------------------------------------------------------------------
    -- RECEIVER SIGNALS
    ---------------------------------------------------------------------------
    type uart_rx_states is (
        rx_get_start_bit,
        rx_confirm_start,
        rx_get_data,
        rx_get_stop_bit
    );

    signal uart_rx_state        : uart_rx_states := rx_get_start_bit;
    signal uart_rx_bit          : std_logic := '1';

    -- Synchronizer
    signal uart_rx_data_sr      : std_logic_vector(1 downto 0) := (others => '1');

    -- Data path
    signal uart_rx_data_vec     : std_logic_vector(7 downto 0) := (others => '0');
    signal uart_rx_count        : unsigned(2 downto 0) := (others => '0');
    signal uart_rx_data_out_stb : std_logic := '0';

    -- Timing / alignment
    signal uart_rx_bit_spacing  : unsigned(c_rx_spc_width-1 downto 0) := (others => '0');
    signal uart_rx_bit_tick     : std_logic := '0';
    signal start_confirm_count  : integer range 0 to oversample := 0;

begin
    
    ---------------------------------------------------------------------------
    -- DEBUG SIGNAL EXPORTS (for ILA / hardware debugging)
    --
    -- dbg_rx_baud_tick     : Oversample tick (baud * oversample)
    -- dbg_uart_rx_bit      : Synchronized RX input bit
    -- dbg_uart_rx_bit_tick : 1x bit sampling tick
    -- dbg_uart_rx_count    : Counts received data bits (0-7)
    -- dbg_uart_rx_data_vec : Current received byte (shift register)
    -- dbg_uart_rx_data_sr  : RX synchronizer shift register
    -- dbg_uart_rx_spacing  : Oversample spacing counter
    -- dbg_uart_rx_state    : Encoded RX FSM state
    ---------------------------------------------------------------------------
    dbg_rx_baud_tick     <= rx_baud_tick;
    dbg_uart_rx_bit      <= uart_rx_bit;
    dbg_uart_rx_bit_tick <= uart_rx_bit_tick;
    dbg_uart_rx_count    <= std_logic_vector(uart_rx_count);
    dbg_uart_rx_data_vec <= uart_rx_data_vec;
    dbg_uart_rx_data_sr  <= uart_rx_data_sr;
    dbg_uart_rx_spacing  <= std_logic_vector(uart_rx_bit_spacing);

    with uart_rx_state select
        dbg_uart_rx_state <=
            "00" when rx_get_start_bit,
            "01" when rx_confirm_start,
            "10" when rx_get_data,
            "11" when rx_get_stop_bit;

    ---------------------------------------------------------------------------
    -- CONNECT IO
    --   data_stream_in_ack  : TX handshake (input accepted)
    --   data_stream_out     : Received byte
    --   data_stream_out_stb : RX data valid strobe
    --   tx                  : UART transmit line
    ---------------------------------------------------------------------------
    data_stream_in_ack  <= uart_rx_data_in_ack;
    data_stream_out     <= uart_rx_data_vec;
    data_stream_out_stb <= uart_rx_data_out_stb;
    tx                  <= uart_tx_data;

    ---------------------------------------------------------------------------
    -- RX_CLOCK_DIVIDER
    --
    -- Non-fractional clock divider for the receiver oversample clock.
    -- Generates rx_baud_tick at approximately baud * oversample.
    ---------------------------------------------------------------------------
    ---------------------------------------------------------------------------
    -- RX_CLOCK_DIVIDER
    --
    -- Fractional clock divider for the receiver timing tick.
    -- Uses integer division plus remainder accumulation so the
    -- average tick rate matches the desired rate even when the
    -- divider is non-integer.
    ---------------------------------------------------------------------------



    rx_clock_divider : process (clock)
        variable v_next_rem  : integer;
        variable v_div_limit : integer;
    begin
        if rising_edge(clock) then
            if reset = '1' then
                rx_baud_counter <= (others => '0');
                rx_baud_tick    <= '0';
                rx_rem_accum    <= 0;
                rx_div_adj      <= 0;
            else
                v_div_limit := c_rx_div - 1 + rx_div_adj;

                if rx_baud_counter = to_unsigned(v_div_limit, rx_baud_counter'length) then
                    rx_baud_counter <= (others => '0');
                    rx_baud_tick    <= '1';

                    v_next_rem := rx_rem_accum + c_rx_rem;

                    if v_next_rem >= c_rx_den then
                        rx_rem_accum <= v_next_rem - c_rx_den;
                        rx_div_adj   <= 1;
                    else
                        rx_rem_accum <= v_next_rem;
                        rx_div_adj   <= 0;
                    end if;
                else
                    rx_baud_counter <= rx_baud_counter + 1;
                    rx_baud_tick    <= '0';
                end if;
            end if;
        end if;
    end process;

    ---------------------------------------------------------------------------
    -- RXD_SYNCHRONIZE
    --
    -- Two-stage flip-flop synchronizer to safely bring the asynchronous RX
    -- signal into the FPGA clock domain and reduce metastability.
    -- Runs every clock cycle to provide a stable sampled input for the receiver.
    ---------------------------------------------------------------------------
    rxd_synchronize : process(clock)
    begin
        if rising_edge(clock) then
            if reset = '1' then
                uart_rx_data_sr <= (others => '1');
            else
                uart_rx_data_sr(0) <= rx;
                uart_rx_data_sr(1) <= uart_rx_data_sr(0);
            end if;
        end if;
    end process;
    uart_rx_bit <= uart_rx_data_sr(1);

    ---------------------------------------------------------------------------
    -- RX_BIT_SPACING
    --
    -- Counts oversample ticks and generates a 1x bit tick for the receiver.
    -- The counter is held at zero during start detection and start confirmation,
    -- then begins counting so that data and stop bits are sampled once per bit.
    ---------------------------------------------------------------------------
    rx_bit_spacing : process(clock)
    begin
        if rising_edge(clock) then
            uart_rx_bit_tick <= '0';

            if reset = '1' then
                uart_rx_bit_spacing <= (others => '0');

            else
                if rx_baud_tick = '1' then
                    if (uart_rx_state = rx_get_start_bit) or (uart_rx_state = rx_confirm_start) then
                        uart_rx_bit_spacing <= (others => '0');
                    else
                        if uart_rx_bit_spacing = to_unsigned(oversample - 1, uart_rx_bit_spacing'length) then
                            uart_rx_bit_tick    <= '1';
                            uart_rx_bit_spacing <= (others => '0');
                        else
                            uart_rx_bit_spacing <= uart_rx_bit_spacing + 1;
                        end if;
                    end if;
                end if;
            end if;
        end if;
    end process;

    ---------------------------------------------------------------------------
    -- UART_RECEIVE_DATA
    --
    -- State 1: rx_get_start_bit
    --   Wait for start bit (line goes low). Transition on oversample tick.
    --
    -- State 2: rx_confirm_start
    --   Wait half a bit period, then re-check the line to confirm a valid
    --   start bit (rejects noise/glitches).
    --   This aligns the sampling point to the center of the bit, so all
    --   following data bits are sampled mid-bit.
    --
    -- State 3: rx_get_data
    --   Sample 8 data bits at each bit tick (center of bit) and shift them
    --   into the receive register.
    --
    -- State 4: rx_get_stop_bit
    --   Sample stop bit. If high ('1'), assert data_stream_out_stb to indicate
    --   valid received byte, then return to idle.
    ---------------------------------------------------------------------------
    uart_receive_data : process(clock)
    begin
        if rising_edge(clock) then
            if reset = '1' then
                uart_rx_state        <= rx_get_start_bit;
                uart_rx_data_vec     <= (others => '0');
                uart_rx_count        <= (others => '0');
                uart_rx_data_out_stb <= '0';
                start_confirm_count <= 0;
            else
                uart_rx_data_out_stb <= '0';

                case uart_rx_state is
                    when rx_get_start_bit =>
                        if rx_baud_tick = '1' and uart_rx_bit = '0' then
                            start_confirm_count <= 0;
                            uart_rx_state <= rx_confirm_start;
                        end if;
                    
                    when rx_confirm_start =>
                        if rx_baud_tick = '1' then
                            if start_confirm_count = half_bit_count then
                                if uart_rx_bit = '0' then
                                    uart_rx_count <= (others => '0');
                                    uart_rx_state <= rx_get_data;
                                else
                                    uart_rx_state <= rx_get_start_bit;
                                end if;
                            else
                                start_confirm_count <= start_confirm_count + 1;
                            end if;
                        end if;
                    
                    when rx_get_data =>
                        if uart_rx_bit_tick = '1' then
                            uart_rx_data_vec(uart_rx_data_vec'high) <= uart_rx_bit;
                            uart_rx_data_vec(uart_rx_data_vec'high-1 downto 0)
                                <= uart_rx_data_vec(uart_rx_data_vec'high downto 1);

                            if uart_rx_count < 7 then
                                uart_rx_count <= uart_rx_count + 1;
                            else
                                uart_rx_count <= (others => '0');
                                uart_rx_state <= rx_get_stop_bit;
                            end if;
                        end if;

                    when rx_get_stop_bit =>
                        if uart_rx_bit_tick = '1' then
                            if uart_rx_bit = '1' then
                                uart_rx_data_out_stb <= '1';
                            end if;
                            uart_rx_state <= rx_get_start_bit;
                        end if;

                    when others =>
                        uart_rx_state <= rx_get_start_bit;
                end case;
            end if;
        end if;
    end process;

    ---------------------------------------------------------------------------
    -- TX_CLOCK_DIVIDER
    --
    -- Generates a tick at the baud rate (1x).
    -- Each tick advances the transmitter by one bit.
    ---------------------------------------------------------------------------
    ---------------------------------------------------------------------------
    -- RX_CLOCK_DIVIDER
    --
    -- Fractional clock divider for the receiver baud tick.
    -- Uses integer division plus remainder accumulation so the
    -- average tick rate matches BAUD even when CLOCK_FREQ / BAUD
    -- is not an integer.
    ---------------------------------------------------------------------------

    tx_clock_divider : process (clock)
        variable v_next_rem  : integer;
        variable v_div_limit : integer;
    begin
        if rising_edge(clock) then
            if reset = '1' then
                tx_baud_counter <= (others => '0');
                rx_baud_tick    <= '0';
                tx_rem_accum    <= 0;
                tx_div_adj      <= 0;
            else
                -- normal interval   = c_rx_div clocks
                -- extended interval = c_rx_div + 1 clocks
                --
                -- counter starts at 0, so compare against:
                -- normal   -> c_rx_div - 1
                -- extended -> c_rx_div
                v_div_limit := c_tx_div - 1 + tx_div_adj;

                if tx_baud_counter = to_unsigned(v_div_limit, tx_baud_counter'length) then
                    tx_baud_counter <= (others => '0');
                    tx_baud_tick    <= '1';

                    -- decide whether NEXT interval gets one extra clock
                    v_next_rem := tx_rem_accum + c_tx_rem;

                    if v_next_rem >= c_tx_den then
                        tx_rem_accum <= v_next_rem - c_tx_den;
                        tx_div_adj   <= 1;
                    else
                        tx_rem_accum <= v_next_rem;
                        tx_div_adj   <= 0;
                    end if;
                else
                    tx_baud_counter <= tx_baud_counter + 1;
                    tx_baud_tick    <= '0';
                end if;
            end if;
        end if;
    end process;

    ---------------------------------------------------------------------------
    -- UART_SEND_DATA
    --
    -- State 1: tx_send_start_bit
    --   Wait for valid input (data_stream_in_stb = '1'), then transmit the
    --   start bit ('0') and latch the input data.
    --
    -- State 2: tx_send_data
    --   Shift out 8 data bits, one per baud tick (LSB first).
    --
    -- State 3: tx_send_stop_bit
    --   Transmit the stop bit ('1'), then return to idle state.
    ---------------------------------------------------------------------------
    uart_send_data : process(clock)
    begin
        if rising_edge(clock) then
            if reset = '1' then
                uart_tx_data      <= '1';
                uart_tx_data_vec  <= (others => '0');
                uart_tx_count     <= (others => '0');
                uart_tx_state     <= tx_send_start_bit;
                uart_rx_data_in_ack <= '0';
            else
                uart_rx_data_in_ack <= '0';

                case uart_tx_state is
                    when tx_send_start_bit =>
                        if tx_baud_tick = '1' and data_stream_in_stb = '1' then
                            uart_tx_data        <= '0';
                            uart_tx_state       <= tx_send_data;
                            uart_tx_count       <= (others => '0');
                            uart_rx_data_in_ack <= '1';
                            uart_tx_data_vec    <= data_stream_in;
                        end if;

                    when tx_send_data =>
                        if tx_baud_tick = '1' then
                            uart_tx_data <= uart_tx_data_vec(0);
                            uart_tx_data_vec(uart_tx_data_vec'high-1 downto 0)
                                <= uart_tx_data_vec(uart_tx_data_vec'high downto 1);

                            if uart_tx_count < 7 then
                                uart_tx_count <= uart_tx_count + 1;
                            else
                                uart_tx_count <= (others => '0');
                                uart_tx_state <= tx_send_stop_bit;
                            end if;
                        end if;

                    when tx_send_stop_bit =>
                        if tx_baud_tick = '1' then
                            uart_tx_data  <= '1';
                            uart_tx_state <= tx_send_start_bit;
                        end if;

                    when others =>
                        uart_tx_data  <= '1';
                        uart_tx_state <= tx_send_start_bit;
                end case;
            end if;
        end if;
    end process;

end rtl;
