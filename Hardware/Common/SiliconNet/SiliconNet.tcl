#Network
set_global_assignment -name SYSTEMVERILOG_FILE $common_path/NetworkTypes/NetworkTypes.sv

#SiliconNet
set_global_assignment -name SYSTEMVERILOG_FILE $common_path/SiliconNet/SiliconNetTypes.sv
set_global_assignment -name SYSTEMVERILOG_FILE $common_path/SiliconNet/SiliconNet.sv

#Connector
source $common_path/SiliconNet/Connector/Connector.tcl

#SiliconNetController
source $common_path/SiliconNet/SiliconNetController/SiliconNetController.tcl

#SiliconSwitch
source $common_path/SiliconNet/SiliconSwitch/SiliconSwitch.tcl

#ShimInterface
source $common_path/SiliconNet/ShimInterface/ShimInterface.tcl
