# 1x3 Packet Router with UVM Verification

A SystemVerilog implementation of a 1-to-3 packet routing switch with an automated UVM 1.2 verification testbench.

## Overview
The router inspects incoming packet headers on a single ingress port and steers data payloads to one of three independent egress channels (Port 0, Port 1, or Port 2) based on the target address.

### Key Features
* **Packet Parsing:** Decodes 8-bit header containing destination address (`data_in[1:0]`) and payload length (`data_in[7:2]`).
* **Central FSM Controller:** 8-state machine managing address detection, payload forwarding, parity checks, and backpressure stalls.
* **Egress FIFO Buffers:** Three independent 16-deep FIFOs with programmable soft-reset timeout logic.
* **Error Detection:** On-the-fly Longitudinal Redundancy Check (LRC) parity verification.
* **Flow Control:** Dynamic `busy` feedback mechanism prevents buffer overflows during channel congestion.

## Verification Environment (UVM 1.2)
* **Driver:** Converts high-level packet sequence items into pin-level signal transitions while observing backpressure.
* **Reactive Monitors:** Three concurrent monitoring tasks asserting `read_enb` upon valid output detection (`vld_out`).
* **Scoreboard:** Golden reference queue checking that all payloads arrive in-order and without data corruption.

## Repository Structure
```text
├── rtl/
│   └── router_top.sv    # Top-level DUT and submodules (FSM, Sync, FIFO, Reg)
├── tb/
│   └── tb_top.sv        # UVM testbench (Interface, Driver, Monitor, Scoreboard, Top)
├── .gitignore           # Ignores simulation dump and compilation artifacts
└── README.md            # Project documentation
```

## How to Run

### Using EDA Playground
1. Paste `rtl/router_top.sv` into `design.sv`.
2. Paste `tb/tb_top.sv` into `testbench.sv`.
3. Under **Tools & Simulators**, select **Synopsys VCS** (or **Aldec Riviera-PRO**).
4. Set **UVM / OVM** to **UVM 1.2**.
5. Click **Run**.
