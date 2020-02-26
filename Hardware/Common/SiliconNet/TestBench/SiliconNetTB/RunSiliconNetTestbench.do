set hw_path "../../../../"
set common_path "../../../"
set sn_path "../../"
set net_path "../../../NetworkTypes"

set AlteraSim_path "C:/intelFPGA/17.0/quartus/eda/sim_lib"
if { [info exists ::env(QUARTUS_ROOTDIR)] } { set AlteraSim_path $::env(QUARTUS_ROOTDIR)/eda/sim_lib }

# Create work library
vlib work

# Compile system verilog sources
vlog -incr -sv -work work $net_path/NetworkTypes.sv
vlog -incr -sv -work work $common_path/RegisterFIFOskid.sv

# compile SiliconNet verilog sources
vlog -incr -sv -work work $sn_path/SiliconNetTypes.sv
vlog -incr -sv -work work $sn_path/SiliconSwitch/SiliconSwitch.sv
vlog -incr -sv -work work $sn_path/SiliconSwitch/InputUnit.sv
vlog -incr -sv -work work $sn_path/SiliconSwitch/OutputUnit.sv
vlog -incr -sv -work work $sn_path/SiliconSwitch/Freelist.sv
vlog -incr -sv -work work $sn_path/SiliconSwitch/OutputMux.sv
vlog -incr -sv -work work $sn_path/ShimInterface/ShimInterface.sv
vlog -incr -sv -work work $sn_path/SiliconNet.sv
vlog -incr -sv -work work $sn_path/SiliconNetController/SiliconNetController.sv
vlog -incr -sv -work work $sn_path/TestBench/SiliconNetTB/SiliconNetTestbench.sv
vlog -incr -sv -work work $sn_path/Connector/Connector.sv
vlog -incr -sv -work work $common_path/ForwardingTable/ForwardingTableDual.sv
vlog -incr -sv -work work $common_path/ForwardingTable/ForwardingTable_arbitrary.sv
vlog -incr -sv -work work $common_path/FIFOCounter/FIFOCounter.sv
vlog -incr -sv -work work $common_path/TreeMux/pipemux_prim2.sv
vlog -incr -sv -work work $common_path/TreeMux/treemux_prim.sv 
vlog -incr -sv -work work $common_path/TreeMux/treemux16.sv 

# Compile verilog sources
vlog -incr -sv -work work $common_path/FastArbiterRandUpdate4/Arbiter_v2.sv

vlog -incr -vlog01compat -work work $sn_path/SiliconSwitch/portfifo.v
vlog -incr -vlog01compat -work work $common_path/shift_reg_clr.v
vlog -incr -vlog01compat -work work $common_path/shift_reg.v
vlog -incr -vlog01compat -work work $common_path/AsyncFIFO.v
vlog -incr -vlog01compat -work work $common_path/lutram_dual.v
vlog -incr -vlog01compat -work work $common_path/mram.v
vlog -incr -vlog01compat -work work $common_path/FIFOFast.v
vlog -incr -vlog01compat -work work $common_path/RegisterFIFOFast.v
vlog -incr -vlog01compat -work work $common_path/sync_regs.v
vlog -incr -vlog01compat -work work $common_path/RegisterFIFOFast.v
vlog -incr -vlog01compat -work work $common_path/Counter.v
vlog -incr -vlog01compat -work work $common_path/FIFO.v

# Compile altera libs
vlog -incr -vlog01compat -work work $AlteraSim_path/altera_mf.v
vlog -incr -vlog01compat -work work $AlteraSim_path/220model.v

# Call vsim to invoke simulator
#
vsim -novopt -voptargs="+acc" -t 1ps -wlf test.wlf -L work work.SiliconNetTestbench
view wave
view structure
view signals

add wave -noupdate -divider -height 20 {clk}
add wave    -label clk              {sim:/SiliconNetTestbench/clk}
add wave    -label rst              {sim:/SiliconNetTestbench/rst}
add wave    -label sa_clk           {sim:/SiliconNetTestbench/sa_clk}
add wave    -label sa_rst           {sim:/SiliconNetTestbench/sa_rst}

add wave -noupdate -divider -height 20 {S/A side tx}
add wave    -label sa_data_in           -radix unsigned         {sim:/SiliconNetTestbench/sa_data_in}
add wave    -label sa_valid_in                                  {sim:/SiliconNetTestbench/sa_valid_in}
add wave    -label sa_first_in                                  {sim:/SiliconNetTestbench/sa_first_in}
add wave    -label sa_last_in                                   {sim:/SiliconNetTestbench/sa_last_in}
add wave    -label sa_ready_out                                 {sim:/SiliconNetTestbench/sa_ready_out}
add wave    -label dbg_head_send        -radix unsigned         {sim:/SiliconNetTestbench/SiliconNet/dbg_head_send}
add wave    -label dbg_data_send        -radix unsigned         {sim:/SiliconNetTestbench/SiliconNet/dbg_data_send}

add wave -noupdate -divider -height 20 {S/A side rx}
add wave    -label sa_data_out          -radix unsigned         {sim:/SiliconNetTestbench/sa_data_out}
add wave    -label sa_valid_out                                 {sim:/SiliconNetTestbench/sa_valid_out}
add wave    -label sa_first_out                                 {sim:/SiliconNetTestbench/sa_first_out}
add wave    -label sa_last_out                                  {sim:/SiliconNetTestbench/sa_last_out}
add wave    -label sa_ready_in                                  {sim:/SiliconNetTestbench/sa_ready_in}
add wave    -label dbg_head_receive     -radix unsigned         {sim:/SiliconNetTestbench/SiliconNet/dbg_head_receive}
add wave    -label dbg_data_receive     -radix unsigned         {sim:/SiliconNetTestbench/SiliconNet/dbg_data_receive}

add wave -noupdate -divider -height 20 {arbiter}
add wave    -label raises_in           -radix unsigned         {sim:/SiliconNetTestbench/SiliconNet/SiliconSwitch/gen_output_units[4]/OutputUnitInst/InputArbiter/raises}
add wave    -label grant_out           -radix unsigned         {sim:/SiliconNetTestbench/SiliconNet/SiliconSwitch/gen_output_units[4]/OutputUnitInst/InputArbiter/grant}
add wave    -label valid_out           -radix unsigned         {sim:/SiliconNetTestbench/SiliconNet/SiliconSwitch/gen_output_units[4]/OutputUnitInst/InputArbiter/valid}
add wave    -label arbiter             -radix unsigned         {sim:/SiliconNetTestbench/SiliconNet/SiliconSwitch/gen_output_units[4]/OutputUnitInst/arbiter}

add wave -noupdate -divider -height 20 {debug_SS_Port_0-3_in}
add wave    -label input_ifc_in            -radix unsigned      {sim:/SiliconNetTestbench/SiliconNet/SiliconSwitch/input_ifc_in}
add wave    -label input_valid_in          -radix unsigned      {sim:/SiliconNetTestbench/SiliconNet/SiliconSwitch/input_valid_in}

add wave -noupdate -divider -height 20 {debug_SS_Port_0-3_out}
add wave    -label output_ifc_out          -radix unsigned      {sim:/SiliconNetTestbench/SiliconNet/SiliconSwitch/output_ifc_out}
add wave    -label output_valid_out        -radix unsigned      {sim:/SiliconNetTestbench/SiliconNet/SiliconSwitch/output_valid_out}

add wave -noupdate -divider -height 20 {debug_tx_internal}
add wave    -label 7tx_msg_counter         -radix unsigned       {sim:/SiliconNetTestbench/SiliconNet/gen_Connector[7]/Connector/tx_msg_counter}
add wave    -label 6tx_msg_counter         -radix unsigned       {sim:/SiliconNetTestbench/SiliconNet/gen_Connector[6]/Connector/tx_msg_counter}
add wave    -label 5tx_msg_counter         -radix unsigned       {sim:/SiliconNetTestbench/SiliconNet/gen_Connector[5]/Connector/tx_msg_counter}
add wave    -label 4tx_msg_counter         -radix unsigned       {sim:/SiliconNetTestbench/SiliconNet/gen_Connector[4]/Connector/tx_msg_counter}
add wave    -label 3tx_msg_counter         -radix unsigned       {sim:/SiliconNetTestbench/SiliconNet/gen_Connector[3]/Connector/tx_msg_counter}
add wave    -label 2tx_msg_counter         -radix unsigned       {sim:/SiliconNetTestbench/SiliconNet/gen_Connector[2]/Connector/tx_msg_counter}
add wave    -label 1tx_msg_counter         -radix unsigned       {sim:/SiliconNetTestbench/SiliconNet/gen_Connector[1]/Connector/tx_msg_counter}
add wave    -label 0tx_msg_counter         -radix unsigned       {sim:/SiliconNetTestbench/SiliconNet/gen_Connector[0]/Connector/tx_msg_counter}

add wave -noupdate -divider -height 20 {debug_tx_drop_internal}
add wave    -label 7tx_msg_drop_counter    -radix unsigned       {sim:/SiliconNetTestbench/SiliconNet/gen_Connector[7]/Connector/tx_msg_drop_counter}
add wave    -label 6tx_msg_drop_counter    -radix unsigned       {sim:/SiliconNetTestbench/SiliconNet/gen_Connector[6]/Connector/tx_msg_drop_counter}
add wave    -label 5tx_msg_drop_counter    -radix unsigned       {sim:/SiliconNetTestbench/SiliconNet/gen_Connector[5]/Connector/tx_msg_drop_counter}
add wave    -label 4tx_msg_drop_counter    -radix unsigned       {sim:/SiliconNetTestbench/SiliconNet/gen_Connector[4]/Connector/tx_msg_drop_counter}
add wave    -label 3tx_msg_drop_counter    -radix unsigned       {sim:/SiliconNetTestbench/SiliconNet/gen_Connector[3]/Connector/tx_msg_drop_counter}
add wave    -label 2tx_msg_drop_counter    -radix unsigned       {sim:/SiliconNetTestbench/SiliconNet/gen_Connector[2]/Connector/tx_msg_drop_counter}
add wave    -label 1tx_msg_drop_counter    -radix unsigned       {sim:/SiliconNetTestbench/SiliconNet/gen_Connector[1]/Connector/tx_msg_drop_counter}
add wave    -label 0tx_msg_drop_counter    -radix unsigned       {sim:/SiliconNetTestbench/SiliconNet/gen_Connector[0]/Connector/tx_msg_drop_counter}

add wave -noupdate -divider -height 20 {debug_rx_internal}
add wave    -label 7rx_msg_counter         -radix unsigned       {sim:/SiliconNetTestbench/SiliconNet/gen_Connector[7]/Connector/rx_msg_counter}
add wave    -label 6rx_msg_counter         -radix unsigned       {sim:/SiliconNetTestbench/SiliconNet/gen_Connector[6]/Connector/rx_msg_counter}
add wave    -label 5rx_msg_counter         -radix unsigned       {sim:/SiliconNetTestbench/SiliconNet/gen_Connector[5]/Connector/rx_msg_counter}
add wave    -label 4rx_msg_counter         -radix unsigned       {sim:/SiliconNetTestbench/SiliconNet/gen_Connector[4]/Connector/rx_msg_counter}
add wave    -label 3rx_msg_counter         -radix unsigned       {sim:/SiliconNetTestbench/SiliconNet/gen_Connector[3]/Connector/rx_msg_counter}
add wave    -label 2rx_msg_counter         -radix unsigned       {sim:/SiliconNetTestbench/SiliconNet/gen_Connector[2]/Connector/rx_msg_counter}
add wave    -label 1rx_msg_counter         -radix unsigned       {sim:/SiliconNetTestbench/SiliconNet/gen_Connector[1]/Connector/rx_msg_counter}
add wave    -label 0rx_msg_counter         -radix unsigned       {sim:/SiliconNetTestbench/SiliconNet/gen_Connector[0]/Connector/rx_msg_counter}

add wave -noupdate -divider -height 20 {debug_counter}
add wave    -label counter_sa              -radix unsigned    -color white    {sim:/SiliconNetTestbench/counter_sa}
add wave    -label counter                 -radix unsigned    -color white    {sim:/SiliconNetTestbench/counter}
add wave    -label sub_test                -radix unsigned    -color white    {sim:/SiliconNetTestbench/sub_test}
add wave    -label int_rand                -radix unsigned    -color white    {sim:/SiliconNetTestbench/int_rand}

add wave -noupdate -divider -height 20 {counter_ingress}
add wave    -label i_counter_pkt_sum      -radix unsigned    -color cyan            {sim:/SiliconNetTestbench/counter_valid_sum}
add wave    -label i_counter_pkt_port     -radix unsigned    -expand                {sim:/SiliconNetTestbench/counter_valid}
add wave    -label i_counter_msg_sum      -radix unsigned    -color {Slate Blue}    {sim:/SiliconNetTestbench/counter_last_sum}
add wave    -label i_counter_msg_port     -radix unsigned    -expand                {sim:/SiliconNetTestbench/counter_last}

add wave -noupdate -divider -height 20 {counter_egress}
add wave    -label o_counter_pkt_sum      -radix unsigned    -color cyan            {sim:/SiliconNetTestbench/counter_valid_e_sum}
add wave    -label o_counter_pkt_port     -radix unsigned    -expand                {sim:/SiliconNetTestbench/counter_valid_e}
add wave    -label o_counter_msg_sum      -radix unsigned    -color {Slate Blue}    {sim:/SiliconNetTestbench/counter_last_e_sum}
add wave    -label o_counter_msg_port     -radix unsigned    -expand                {sim:/SiliconNetTestbench/counter_last_e}

add wave -noupdate -divider -height 20 {register_interface}
add wave    -label i                       -radix unsigned      {sim:/SiliconNetTestbench/i}
add wave    -label ctl_read_in             -radix unsigned      {sim:/SiliconNetTestbench/ctl_read_in}
add wave    -label ctl_write_in            -radix unsigned      {sim:/SiliconNetTestbench/ctl_write_in}
add wave    -label ctl_addr_in             -radix hexadecimal   {sim:/SiliconNetTestbench/ctl_addr_in}
add wave    -label ctl_wrdata_in           -radix unsigned      {sim:/SiliconNetTestbench/ctl_wrdata_in}
add wave    -label ctl_rddata_out          -radix unsigned      {sim:/SiliconNetTestbench/ctl_rddata_out}
add wave    -label ctl_rdvalid_out         -radix unsigned      {sim:/SiliconNetTestbench/ctl_rdvalid_out}

add wave -noupdate -divider -height 20 {register_content}
add wave    -label sn_ctl_reg              -radix unsigned      {sim:/SiliconNetTestbench/SiliconNet/SiliconNetController/sn_ctl_reg}
add wave    -label sn_ctl_write_key_reg    -radix unsigned      {sim:/SiliconNetTestbench/SiliconNet/SiliconNetController/sn_ctl_write_key_reg}
add wave    -label sn_ctl_write_msk_reg    -radix unsigned      {sim:/SiliconNetTestbench/SiliconNet/SiliconNetController/sn_ctl_write_msk_reg}
add wave    -label sn_ctl_read_key_reg     -radix unsigned      {sim:/SiliconNetTestbench/SiliconNet/SiliconNetController/sn_ctl_read_key_reg}
add wave    -label sn_ctl_read_msk_reg     -radix unsigned      {sim:/SiliconNetTestbench/SiliconNet/SiliconNetController/sn_ctl_read_msk_reg}
add wave    -label sn_ctl_read_ep_reg      -radix unsigned      {sim:/SiliconNetTestbench/SiliconNet/SiliconNetController/sn_ctl_read_ep_reg}
add wave    -label write_cmpl_user         -radix unsigned      {sim:/SiliconNetTestbench/SiliconNet/SiliconNetController/write_cmpl_user}
add wave    -label write_cmpl_sn           -radix unsigned      {sim:/SiliconNetTestbench/SiliconNet/SiliconNetController/write_cmpl_sn}
add wave    -label read_cmpl_user          -radix unsigned      {sim:/SiliconNetTestbench/SiliconNet/SiliconNetController/read_cmpl_user}
add wave    -label read_cmpl_sn            -radix unsigned      {sim:/SiliconNetTestbench/SiliconNet/SiliconNetController/read_cmpl_sn}
add wave    -label sn_ctl_read_counter_reg -radix unsigned      {sim:/SiliconNetTestbench/SiliconNet/SiliconNetController/sn_ctl_read_counter_reg[63:32]}
add wave    -label sn_ctl_read_counter_reg -radix unsigned      {sim:/SiliconNetTestbench/SiliconNet/SiliconNetController/sn_ctl_read_counter_reg[31:0]}
add wave    -label counter_cmpl_user       -radix unsigned      {sim:/SiliconNetTestbench/SiliconNet/SiliconNetController/counter_cmpl_user}
add wave    -label counter_cmpl_sn         -radix unsigned      {sim:/SiliconNetTestbench/SiliconNet/SiliconNetController/counter_cmpl_sn}

add wave -noupdate -divider -height 20 {debug_forwardingtable_3-0}
add wave    -label high_key_store_3          -radix unsigned      {sim:/SiliconNetTestbench/SiliconNet/gen_Connector[3]/Connector/ForwardingTableDual_ins/ForwardingTable_high_ins/key_store}
add wave    -label high_msk_store_3          -radix unsigned      {sim:/SiliconNetTestbench/SiliconNet/gen_Connector[3]/Connector/ForwardingTableDual_ins/ForwardingTable_high_ins/msk_store}
add wave    -label low_key_store_3           -radix unsigned      {sim:/SiliconNetTestbench/SiliconNet/gen_Connector[3]/Connector/ForwardingTableDual_ins/ForwardingTable_low_ins/key_store}
add wave    -label low_msk_store_3           -radix unsigned      {sim:/SiliconNetTestbench/SiliconNet/gen_Connector[3]/Connector/ForwardingTableDual_ins/ForwardingTable_low_ins/msk_store}
add wave    -label high_key_store_2          -radix unsigned      {sim:/SiliconNetTestbench/SiliconNet/gen_Connector[2]/Connector/ForwardingTableDual_ins/ForwardingTable_high_ins/key_store}
add wave    -label high_msk_store_2          -radix unsigned      {sim:/SiliconNetTestbench/SiliconNet/gen_Connector[2]/Connector/ForwardingTableDual_ins/ForwardingTable_high_ins/msk_store}
add wave    -label low_key_store_2           -radix unsigned      {sim:/SiliconNetTestbench/SiliconNet/gen_Connector[2]/Connector/ForwardingTableDual_ins/ForwardingTable_low_ins/key_store}
add wave    -label low_msk_store_2           -radix unsigned      {sim:/SiliconNetTestbench/SiliconNet/gen_Connector[2]/Connector/ForwardingTableDual_ins/ForwardingTable_low_ins/msk_store}
add wave    -label high_key_store_1          -radix unsigned      {sim:/SiliconNetTestbench/SiliconNet/gen_Connector[1]/Connector/ForwardingTableDual_ins/ForwardingTable_high_ins/key_store}
add wave    -label high_msk_store_1          -radix unsigned      {sim:/SiliconNetTestbench/SiliconNet/gen_Connector[1]/Connector/ForwardingTableDual_ins/ForwardingTable_high_ins/msk_store}
add wave    -label low_key_store_1           -radix unsigned      {sim:/SiliconNetTestbench/SiliconNet/gen_Connector[1]/Connector/ForwardingTableDual_ins/ForwardingTable_low_ins/key_store}
add wave    -label low_msk_store_1           -radix unsigned      {sim:/SiliconNetTestbench/SiliconNet/gen_Connector[1]/Connector/ForwardingTableDual_ins/ForwardingTable_low_ins/msk_store}
add wave    -label high_key_store_0          -radix unsigned      {sim:/SiliconNetTestbench/SiliconNet/gen_Connector[0]/Connector/ForwardingTableDual_ins/ForwardingTable_high_ins/key_store}
add wave    -label high_msk_store_0          -radix unsigned      {sim:/SiliconNetTestbench/SiliconNet/gen_Connector[0]/Connector/ForwardingTableDual_ins/ForwardingTable_high_ins/msk_store}
add wave    -label low_key_store_0           -radix unsigned      {sim:/SiliconNetTestbench/SiliconNet/gen_Connector[0]/Connector/ForwardingTableDual_ins/ForwardingTable_low_ins/key_store}
add wave    -label low_msk_store_0           -radix unsigned      {sim:/SiliconNetTestbench/SiliconNet/gen_Connector[0]/Connector/ForwardingTableDual_ins/ForwardingTable_low_ins/msk_store}

add wave -noupdate -divider -height 20 {debug_counter}
add wave    -label counter_read_in           -radix unsigned      {sim:/SiliconNetTestbench/SiliconNet/counter_read_in}
add wave    -label counter_index_in          -radix unsigned      {sim:/SiliconNetTestbench/SiliconNet/counter_index_in}
add wave    -label counter_value_valid_out   -radix unsigned      {sim:/SiliconNetTestbench/SiliconNet/counter_value_valid_out}
add wave    -label counter_value_out         -radix unsigned      {sim:/SiliconNetTestbench/SiliconNet/counter_value_out}

add wave -noupdate -divider -height 20 {debug_lv1_arb}
add wave    -label mid_raise            -radix unsigned         {sim:/SiliconNetTestbench/SiliconNet/SiliconSwitch/mid_raise}
add wave    -label mid_grant            -radix unsigned         {sim:/SiliconNetTestbench/SiliconNet/SiliconSwitch/mid_grant}
add wave    -label grant_in             -radix unsigned         {sim:/SiliconNetTestbench/SiliconNet/SiliconSwitch/gen_input_units[7]/InputUnitInst/grant_in}

add wave -noupdate -divider -height 20 {fsm}
add wave    -label in_fsm               -radix unsigned         {sim:/SiliconNetTestbench/SiliconNet/SiliconSwitch/gen_input_units[7]/InputUnitInst/raise_state_ff.fsm}
add wave    -label raise_out_nxt.dst_port               -radix unsigned         {sim:/SiliconNetTestbench/SiliconNet/SiliconSwitch/gen_input_units[7]/InputUnitInst/raise_out_nxt.dst_port}
add wave    -label hram_ctrl            -radix unsigned         {sim:/SiliconNetTestbench/SiliconNet/SiliconSwitch/gen_input_units[7]/InputUnitInst/hram_ctrl}
add wave    -label hram_net             -radix unsigned         {sim:/SiliconNetTestbench/SiliconNet/SiliconSwitch/gen_input_units[7]/InputUnitInst/hram_net}
add wave    -label marshal_ff           -radix unsigned         {sim:/SiliconNetTestbench/SiliconNet/SiliconSwitch/gen_input_units[7]/InputUnitInst/marshal_ff}
add wave    -label output_addr_net      -radix unsigned         {sim:/SiliconNetTestbench/SiliconNet/SiliconSwitch/gen_input_units[7]/InputUnitInst/output_addr_net}
add wave    -label out_fsm              -radix unsigned         {sim:/SiliconNetTestbench/SiliconNet/SiliconSwitch/gen_output_units[7]/OutputUnitInst/grant_state_ff.fsm}



# SA slower
run 2300000000
#run 1000000000

# SA faster
#run 300000000

# run controller
#run 800000000
