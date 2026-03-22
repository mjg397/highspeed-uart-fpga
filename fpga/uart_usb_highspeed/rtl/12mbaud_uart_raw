-------------------------------------------------------------------------------
-- UART (pabennett-derived) - FIXED + PARAMETERIZED OVERSAMPLING
-- Key fix: RX is now truly oversampled (default 8x) and bit tick occurs every
-- OVERSAMPLE samples (not once every 16 bits / mismatched settings).
-------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;
    use ieee.math_real.all;

entity uart is
    generic (
        baud                : positive;
        clock_frequency     : positive;
        oversample          : positive := 8      -- <<< set to 4, 8, or 16
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
        
        -- debug lines
        dbg_rx_baud_tick     : out std_logic;
        dbg_uart_rx_bit      : out std_logic;
        dbg_uart_rx_state    : out std_logic_vector(1 downto 0);
        dbg_uart_rx_spacing  : out std_logic_vector(3 downto 0);
        dbg_uart_rx_bit_tick : out std_logic;
        dbg_uart_rx_count    : out std_logic_vector(2 downto 0);
        dbg_uart_rx_data_vec : out std_logic_vector(7 downto 0);
        dbg_uart_rx_data_sr  : out std_logic_vector(1 downto 0);
        dbg_uart_rx_filter   : out std_logic_vector(1 downto 0)
    );
end uart;

architecture rtl of uart is

    ---------------------------------------------------------------------------
    -- Baud generation constants
    ---------------------------------------------------------------------------
    constant c_tx_div       : integer := clock_frequency / baud;
    constant c_rx_div       : integer := clock_frequency / (baud * oversample);

    constant c_tx_div_width : integer := integer(log2(real(c_tx_div))) + 1;
    constant c_rx_div_width : integer := integer(log2(real(c_rx_div))) + 1;

    -- spacing counter needs to count 0..(oversample-1)
    constant c_rx_spc_width : integer := integer(log2(real(oversample))) + 1;
    -- half bit count will fix up later
    constant HALF_BIT_COUNT : integer := oversample/2 - 1;
    ---------------------------------------------------------------------------
    -- Baud generation signals
    ---------------------------------------------------------------------------
    signal tx_baud_counter : unsigned(c_tx_div_width - 1 downto 0)
        := (others => '0');
    signal tx_baud_tick : std_logic := '0';

    signal rx_baud_counter : unsigned(c_rx_div_width - 1 downto 0)
        := (others => '0');
    signal rx_baud_tick : std_logic := '0';

    ---------------------------------------------------------------------------
    -- Transmitter signals
    ---------------------------------------------------------------------------
    type uart_tx_states is (
        tx_send_start_bit,
        tx_send_data,
        tx_send_stop_bit
    );
    signal uart_tx_state    : uart_tx_states := tx_send_start_bit;
    signal uart_tx_data_vec : std_logic_vector(7 downto 0) := (others => '0');
    signal uart_tx_data     : std_logic := '1';
    signal uart_tx_count    : unsigned(2 downto 0) := (others => '0');
    signal uart_rx_data_in_ack : std_logic := '0';

    ---------------------------------------------------------------------------
    -- Receiver signals
    ---------------------------------------------------------------------------
    type uart_rx_states is (
        rx_get_start_bit,
        rx_confirm_start,
        rx_get_data,
        rx_get_stop_bit
    );
    signal uart_rx_state        : uart_rx_states := rx_get_start_bit;
    signal uart_rx_bit          : std_logic := '1';
    signal uart_rx_data_vec     : std_logic_vector(7 downto 0) := (others => '0');
    signal uart_rx_data_sr      : std_logic_vector(1 downto 0) := (others => '1');
    signal uart_rx_filter       : unsigned(1 downto 0) := (others => '1');
    signal uart_rx_count        : unsigned(2 downto 0) := (others => '0');
    signal uart_rx_data_out_stb : std_logic := '0';

    signal uart_rx_bit_spacing  : unsigned(c_rx_spc_width-1 downto 0) := (others => '0');
    signal uart_rx_bit_tick     : std_logic := '0';
    -- fix up later if necessary
    signal confirm_count : integer range 0 to oversample := 0;

begin
    -- debug
    dbg_rx_baud_tick     <= rx_baud_tick;
    dbg_uart_rx_bit      <= uart_rx_bit;
    dbg_uart_rx_bit_tick <= uart_rx_bit_tick;
    dbg_uart_rx_count    <= std_logic_vector(uart_rx_count);
    dbg_uart_rx_data_vec <= uart_rx_data_vec;
    dbg_uart_rx_data_sr  <= uart_rx_data_sr;
    dbg_uart_rx_filter   <= std_logic_vector(uart_rx_filter);
    dbg_uart_rx_spacing  <= std_logic_vector(uart_rx_bit_spacing);

    with uart_rx_state select
        dbg_uart_rx_state <=
            "00" when rx_get_start_bit,
            "01" when rx_confirm_start,
            "10" when rx_get_data,
            "11" when rx_get_stop_bit;
            
    -- Connect IO
    data_stream_in_ack  <= uart_rx_data_in_ack;
    data_stream_out     <= uart_rx_data_vec;
    data_stream_out_stb <= uart_rx_data_out_stb;
    tx                  <= uart_tx_data;

    ---------------------------------------------------------------------------
    -- RX_CLOCK_DIVIDER (oversample tick at baud*oversample)
    ---------------------------------------------------------------------------
    rx_clock_divider : process (clock)
    begin
        if rising_edge(clock) then
            if reset = '1' then
                rx_baud_counter <= (others => '0');
                rx_baud_tick    <= '0';
            else
                if rx_baud_counter = to_unsigned(c_rx_div - 1, rx_baud_counter'length) then
                    rx_baud_counter <= (others => '0');
                    rx_baud_tick    <= '1';
                else
                    rx_baud_counter <= rx_baud_counter + 1;
                    rx_baud_tick    <= '0';
                end if;
            end if;
        end if;
    end process;

    ---------------------------------------------------------------------------
    -- RXD_SYNCHRONISE (to oversample tick)
    ---------------------------------------------------------------------------
    rxd_synchronise : process(clock)
    begin
        if rising_edge(clock) then
            if reset = '1' then
                uart_rx_data_sr <= (others => '1');
            else
                if rx_baud_tick = '1' then
                    uart_rx_data_sr(0) <= rx;
                    --uart_rx_data_sr(1) <= uart_rx_data_sr(0);
                    uart_rx_bit <= uart_rx_data_sr(0);
                end if;
            end if;
        end if;
    end process;

--    ---------------------------------------------------------------------------
--    -- RXD_FILTER (2-bit up/down filter)
--    ---------------------------------------------------------------------------
--    rxd_filter : process(clock)
--    begin
--        if rising_edge(clock) then
--            if reset = '1' then
--                uart_rx_filter <= (others => '1');
--                uart_rx_bit    <= '1';
--            else
--                if rx_baud_tick = '1' then
--                    if uart_rx_data_sr(1) = '1' and uart_rx_filter < 3 then
--                        uart_rx_filter <= uart_rx_filter + 1;
--                    elsif uart_rx_data_sr(1) = '0' and uart_rx_filter > 0 then
--                        uart_rx_filter <= uart_rx_filter - 1;
--                    end if;

--                    if uart_rx_filter = 3 then
--                        uart_rx_bit <= '1';
--                    elsif uart_rx_filter = 0 then
--                        uart_rx_bit <= '0';
--                    end if;
--                end if;
--            end if;
--        end if;
--    end process;

    ---------------------------------------------------------------------------
    -- RX_BIT_SPACING (generate 1x bit tick from oversample ticks)
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
    ---------------------------------------------------------------------------
    uart_receive_data : process(clock)
    begin
        if rising_edge(clock) then
            if reset = '1' then
                uart_rx_state        <= rx_get_start_bit;
                uart_rx_data_vec     <= (others => '0');
                uart_rx_count        <= (others => '0');
                uart_rx_data_out_stb <= '0';
                confirm_count <= 0;
            else
                uart_rx_data_out_stb <= '0';

                case uart_rx_state is
                    when rx_get_start_bit =>
                        if rx_baud_tick = '1' and uart_rx_bit = '0' then
                            confirm_count <= 0;
                            uart_rx_state <= rx_confirm_start;
                        end if;
                    
                    when rx_confirm_start =>
                        if rx_baud_tick = '1' then
                            if confirm_count = HALF_BIT_COUNT then
                                if uart_rx_bit = '0' then
                                    uart_rx_count <= (others => '0');
                                    uart_rx_state <= rx_get_data;
                                else
                                    uart_rx_state <= rx_get_start_bit;
                                end if;
                            else
                                confirm_count <= confirm_count + 1;
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
    -- TX_CLOCK_DIVIDER (1x baud)
    ---------------------------------------------------------------------------
    tx_clock_divider : process(clock)
    begin
        if rising_edge(clock) then
            if reset = '1' then
                tx_baud_counter <= (others => '0');
                tx_baud_tick    <= '0';
            else
                if tx_baud_counter = to_unsigned(c_tx_div - 1, tx_baud_counter'length) then
                    tx_baud_counter <= (others => '0');
                    tx_baud_tick    <= '1';
                else
                    tx_baud_counter <= tx_baud_counter + 1;
                    tx_baud_tick    <= '0';
                end if;
            end if;
        end if;
    end process;

    ---------------------------------------------------------------------------
    -- UART_SEND_DATA
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
