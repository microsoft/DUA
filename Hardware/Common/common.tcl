
set common_path [ file dirname [ dict get [ info frame [ info frame ] ] file ] ]

set_global_assignment -name VERILOG_FILE       $common_path/AsyncFIFO.v

set_global_assignment -name VERILOG_FILE       $common_path/Counter.v

set_global_assignment -name VERILOG_FILE       $common_path/FIFO.v
set_global_assignment -name VERILOG_FILE       $common_path/FIFOFast.v

set_global_assignment -name SYSTEMVERILOG_FILE $common_path/ForwardingTable/ForwardingTable_arbitrary.sv
set_global_assignment -name SYSTEMVERILOG_FILE $common_path/ForwardingTable/ForwardingTableDual.sv

set_global_assignment -name SYSTEMVERILOG_FILE $common_path/FIFOCounter/FIFOCounter.sv

set_global_assignment -name SYSTEMVERILOG_FILE $common_path/TreeMux/pipemux_prim2.sv
set_global_assignment -name SYSTEMVERILOG_FILE $common_path/TreeMux/treemux_prim.sv
set_global_assignment -name SYSTEMVERILOG_FILE $common_path/TreeMux/treemux16.sv

set_global_assignment -name SYSTEMVERILOG_FILE $common_path/FastArbiterRandUpdate4/Arbiter_v2.sv

set_global_assignment -name VERILOG_FILE       $common_path/lutram_dual.v

set_global_assignment -name VERILOG_FILE       $common_path/mram.v

set_global_assignment -name VERILOG_FILE       $common_path/RegisterFIFOFast.v
set_global_assignment -name SYSTEMVERILOG_FILE $common_path/RegisterFIFOSkid.sv

set_global_assignment -name VERILOG_FILE       $common_path/shift_reg_clr.v

set_global_assignment -name VERILOG_FILE       $common_path/shift_reg.v

set_global_assignment -name VERILOG_FILE       $common_path/sync_regs.v
