# Base Clock: 27.0 MHz oscillator
# Period = 1000 / 27.0 = 37.037 ns
create_clock -name clk -period 37.037 [get_ports {clk}]

# System Clock
create_clock -name core_clk -period 3.036 [get_nets {core_clk}]

# SDRAM CLock
create_clock -name bus_clk -period 6.072 [get_nets {bus_clk}]


# HDMI Serializer Clock (s_clk): 126.0 MHz 
# Period = 1000 / 126.0 = 7.936 ns
create_clock -name s_clk -period 7.936 [get_nets {s_clk}]

# HDMI Pixel Clock (p_clk): 25.2 MHz
# Period = 1000 / 25.2 = 39.682 ns
create_clock -name p_clk -period 39.682 [get_nets {p_clk}]