Direct Universal Access<br/>
Making Data Center Resources Available to FPGA
=
("Code - DUA | SiliconNet")
-
<br/>

## Introduction ##

DUA is a reference design of a non-blocking hardware switch that connects various resources at PCIe Gen3x8 line rate. All source files are written in Verilog/SystemVerilog.

## Feature List ##

This release includes a non-blocking hardware switch of up to 16 ports with the following features:
* A replacable shim layer that supports up to four virtual channels per port.
* Support for variable packet size ranging from (256 bits x 4 cycles) to (512 bits x 8 cycles).
* Support for variable message size, from 32 Bytes to 4 Kilo-Bytes.
* Messages are indicated by a "first" signal and a "last" signal with the ability to pause by deasserting a “valid” signal.
* A RoundRobin scheduler.
* Intel (formerly Altera) devices are the targeted devices but should work on Xilinx devices with interface wrapper modules.

## Goal ##

DUA is a unified interconnection framework that provides communication among all physical interfaces between FPGAs without CPU involvement by leveraging existing networking and FPGA appliance infrastructure. With DUA, FPGA applications are provided a unified address format and a single set of communication capabilities to access all resources, regardless of the location (remote or local), or the type of the target device (CPU, GPU, FPGA DRAM, server DRAM, SSD, etc.). DUA  incurs negligible latency and logic area overhead over existing communication mechanisms.

## Build ##

ModelSim (10.5b) and Quartus Prime (Std 17.0.2) are needed to simulate and synthesis the design.
The following link provides you the resources before building DUA
https://www.intel.com/content/www/us/en/software/programmable/quartus-prime/download.html

## External Dependency ##

There is no external dependencies for this release.

## Publication ##

This release source code is described in our NSDI'19 paper:
https://www.usenix.org/system/files/nsdi19-shu.pdf
and under active development to support more features and devices in the future.

## Feedback ##

* Refer to Wiki page for roadmap. Refer to Issues page to raise an issue.<br/>
* To contact with us, please send an email to DUA@microsoft.com.<br/>
* Please report potential security vulnerabilities to us through Microsoft Security Response Center (https://www.microsoft.com/en-us/msrc) privately.

## Contributing ##

DUA provides a switching platform for networking and hardware systems, so we encourage developers to use DUA to build stacks to access different resources.

This project welcomes contributions and suggestions.  Most contributions require you to agree to a
Contributor License Agreement (CLA) declaring that you have the right to, and actually do, grant us
the rights to use your contribution. For details, visit https://cla.microsoft.com.

When you submit a pull request, a CLA-bot will automatically determine whether you need to provide
a CLA and decorate the PR appropriately (e.g., label, comment). Simply follow the instructions
provided by the bot. You will only need to do this once across all repos using our CLA.

This project has adopted the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/).
For more information see the [Code of Conduct FAQ](https://opensource.microsoft.com/codeofconduct/faq/) or
contact [opencode@microsoft.com](mailto:opencode@microsoft.com) with any additional questions or comments.

## License ##

Copyright (c) Microsoft Corporation. All rights reserved.<br/>
Licensed under the [MIT](LICENSE.txt) license.
