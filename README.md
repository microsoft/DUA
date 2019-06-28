Direct Universal Access<br/>
Making Data Center Resources Available to FPGA
=
("Code - DUA | SiliconNet")
-
<br/>

## Introduction ##

DUA is a reference design of non-blocking hardware switch that connects all kinds of computing resources deployed in datacenters at PCIe Gen3 x8 line rate. All source files are written in Verilog/SystemVerilog.

## Feature List ##

This release includes the following features:
* Non-blocking hardware switch, supports up to 16 ports.
* A replacable shim layer, supports up to 4 virtual channels to share 1 port with full bandwidth.
* Variable switching packet size, from (256 bits x 4 cycles) to (512 bits x 8 cycles).
* Variable message size, from 32 Bytes to 4 Kilo-Bytes.
* A message is signed with a "first" signal and a "last" signal. A message is not neccessarily transmitted continuesly by using a "valid" signal.
* RoundRobin mechanism is used for packet control.
* Intel (formerly Altera) device is natually supported, we have not tried on Xilinx devices, though it should work on Xilinx devices with some interface wrapper modules.

## Goal ##

DUA is a unified interconnection framework that provides communication among all physical interfaces between FPGAs without CPU involvement by leveraging existing networking and FPGA appliance infrastructure. With DUA, FPGA applications can use a unified address format and a single programming interface to access different types of resources, regardless of the location (remote or local), or the type of the target device (CPU, GPU, FPGA DRAM, server DRAM, SSD, etc.). DUA only incurs negligible latency and logic area overhead on existing communication stacks that's the key to build the hyper-efficient FPGA cluster.

## Build ##

To simulate and synthesis the design, you need to install ModelSim (10.5b) and Quartus Prime (Std 17.0.2).
The following link provides you the resources before building DUA
https://www.intel.com/content/www/us/en/software/programmable/quartus-prime/download.html

## External Dependency ##

There is no external dependencies for this release.

## Publication ##

This release source code is PoC of our NSDI'19 paper:
https://www.usenix.org/system/files/nsdi19-shu.pdf
and under active development to support more features and devices in the future.

## Feedback ##

* Refer to Wiki page for roadmap. Refer to Issues page to raise an issue.<br/>
* To contact with us, please send an email to DUA@microsoft.com.<br/>
* You could report a potential security vulnerability to us through Microsoft Security Response Center (https://www.microsoft.com/en-us/msrc) privately.

## Contributing ##

DUA provides a switching platform for networking and hardware systems, so we encourage developers to build stacks for all kinds of resources on top of DUA.

This project welcomes contributions and suggestions.  Most contributions require you to agree to a
Contributor License Agreement (CLA) declaring that you have the right to, and actually do, grant us
the rights to use your contribution. For details, visit https://cla.microsoft.com.

When you submit a pull request, a CLA-bot will automatically determine whether you need to provide
a CLA and decorate the PR appropriately (e.g., label, comment). Simply follow the instructions
provided by the bot. You will only need to do this once across all repos using our CLA.

This project has adopted the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/).
For more information see the [Code of Conduct FAQ](https://opensource.microsoft.com/codeofconduct/faq/) or
contact [opencode@microsoft.com](mailto:opencode@microsoft.com) with any additional questions or comments..

## License ##

Copyright (c) Microsoft Corporation. All rights reserved.<br/>
Licensed under the [MIT](LICENSE.txt) license.
