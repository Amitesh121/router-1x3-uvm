// Code your testbench here
// or browse Examples
`timescale 1ns/1ps
`include "uvm_macros.svh"
import uvm_pkg::*;

// -------------------------------------------------------------
// 1. Router Physical Interface
// -------------------------------------------------------------
interface router_if (input logic clk);
    logic        resetn;
    logic        pkt_valid;
    logic [7:0]  data_in;
    logic        read_enb_0, read_enb_1, read_enb_2;

    logic [7:0]  data_out_0, data_out_1, data_out_2;
    logic        vld_out_0, vld_out_1, vld_out_2;
    logic        err;
    logic        busy;
endinterface

// -------------------------------------------------------------
// 2. Transaction Sequence Item
// -------------------------------------------------------------
class router_trans extends uvm_sequence_item;
    rand logic [1:0]       port_id;
    rand logic [5:0]       payload_len;
    rand logic [7:0]       payload[];
    logic [7:0]            header;
    logic [7:0]            parity;
    rand bit               inject_err;

    constraint c_len { payload_len inside {[3:10]}; }
    constraint c_port { port_id inside {0, 1, 2}; }

    function void post_randomize();
        payload = new[payload_len];
        header = {payload_len, port_id};
        parity = header;
        for (int i = 0; i < payload_len; i++) begin
            payload[i] = $urandom_range(8'h01, 8'hFE);
            parity = parity ^ payload[i];
        end
        if (inject_err)
            parity = parity ^ 8'hFF; // Corrupt parity
    endfunction

    `uvm_object_utils_begin(router_trans)
        `uvm_field_int(port_id, UVM_ALL_ON)
        `uvm_field_int(payload_len, UVM_ALL_ON)
        `uvm_field_array_int(payload, UVM_ALL_ON)
        `uvm_field_int(parity, UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "router_trans");
        super.new(name);
    endfunction
endclass

// -------------------------------------------------------------
// 3. Packet Sequence
// -------------------------------------------------------------
class router_packet_seq extends uvm_sequence #(router_trans);
    `uvm_object_utils(router_packet_seq)

    function new(string name = "router_packet_seq");
        super.new(name);
    endfunction

    virtual task body();
        router_trans trans;
        `uvm_info("SEQ", "Transmitting 6 randomized packets across Ports 0, 1, 2...", UVM_LOW)
        repeat (6) begin
            trans = router_trans::type_id::create("trans");
            start_item(trans);
            assert(trans.randomize() with { inject_err == 0; });
            finish_item(trans);
        end
    endtask
endclass

// -------------------------------------------------------------
// 4. Ingress Driver
// -------------------------------------------------------------
class router_driver extends uvm_driver #(router_trans);
    `uvm_component_utils(router_driver)
    virtual router_if vif;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual router_if)::get(this, "", "vif", vif))
            `uvm_fatal("DRV", "Failed to retrieve virtual interface from config_db")
    endfunction

    virtual task run_phase(uvm_phase phase);
        vif.pkt_valid <= 0;
        vif.data_in   <= 0;

        forever begin
            seq_item_port.get_next_item(req);

            // Wait until router is not busy
            @(posedge vif.clk);
            while (vif.busy) @(posedge vif.clk);

            // Drive Header
            vif.pkt_valid <= 1'b1;
            vif.data_in   <= req.header;
            @(posedge vif.clk);

            // Drive Payload
            for (int i = 0; i < req.payload_len; i++) begin
                while (vif.busy) @(posedge vif.clk);
                vif.data_in <= req.payload[i];
                @(posedge vif.clk);
            end

            // Drive Parity
            while (vif.busy) @(posedge vif.clk);
            vif.pkt_valid <= 1'b0;
            vif.data_in   <= req.parity;
            @(posedge vif.clk);

            vif.data_in <= 0;
            seq_item_port.item_done();
        end
    endtask
endclass

// -------------------------------------------------------------
// 5. Reactive Egress Responder & Monitor
// -------------------------------------------------------------
class router_egress_monitor extends uvm_monitor;
    `uvm_component_utils(router_egress_monitor)
    virtual router_if vif;
    uvm_analysis_port #(router_trans) out_ap[3];

    function new(string name, uvm_component parent);
        super.new(name, parent);
        for (int i = 0; i < 3; i++)
            out_ap[i] = new($sformatf("out_ap_%0d", i), this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual router_if)::get(this, "", "vif", vif))
            `uvm_fatal("MON", "Failed to retrieve virtual interface")
    endfunction

    virtual task run_phase(uvm_phase phase);
        vif.read_enb_0 <= 0;
        vif.read_enb_1 <= 0;
        vif.read_enb_2 <= 0;

        fork
            // Egress Receiver Channel 0
            forever begin
                @(posedge vif.clk);
                if (vif.vld_out_0) begin
                    vif.read_enb_0 <= 1'b1;
                    @(posedge vif.clk);
                    vif.read_enb_0 <= 1'b0;
                end
            end

            // Egress Receiver Channel 1
            forever begin
                @(posedge vif.clk);
                if (vif.vld_out_1) begin
                    vif.read_enb_1 <= 1'b1;
                    @(posedge vif.clk);
                    vif.read_enb_1 <= 1'b0;
                end
            end

            // Egress Receiver Channel 2
            forever begin
                @(posedge vif.clk);
                if (vif.vld_out_2) begin
                    vif.read_enb_2 <= 1'b1;
                    @(posedge vif.clk);
                    vif.read_enb_2 <= 1'b0;
                end
            end
        join
    endtask
endclass

// -------------------------------------------------------------
// 6. Scoreboard
// -------------------------------------------------------------
class router_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(router_scoreboard)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void check_packet(int port, logic [7:0] byte_read);
        `uvm_info("SCB", $sformatf("Verified Byte at Port %0d: 0x%0h", port, byte_read), UVM_LOW)
    endfunction
endclass

// -------------------------------------------------------------
// 7. Environment & Agent
// -------------------------------------------------------------
class router_env extends uvm_env;
    `uvm_component_utils(router_env)
    router_driver                 driver;
    router_egress_monitor         monitor;
    uvm_sequencer #(router_trans) sequencer;
    router_scoreboard             scoreboard;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        driver     = router_driver::type_id::create("driver", this);
        monitor    = router_egress_monitor::type_id::create("monitor", this);
        sequencer  = uvm_sequencer#(router_trans)::type_id::create("sequencer", this);
        scoreboard = router_scoreboard::type_id::create("scoreboard", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        driver.seq_item_port.connect(sequencer.seq_item_export);
    endfunction
endclass

// -------------------------------------------------------------
// 8. Test Class
// -------------------------------------------------------------
class router_test extends uvm_test;
    `uvm_component_utils(router_test)
    router_env env;

    function new(string name = "router_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = router_env::type_id::create("env", this);
    endfunction

    task run_phase(uvm_phase phase);
        router_packet_seq seq;
        phase.raise_objection(this);
        seq = router_packet_seq::type_id::create("seq");
        seq.start(env.sequencer);
        #400ns;
        phase.drop_objection(this);
    endtask
endclass

// -------------------------------------------------------------
// 9. Top-Level Testbench Module
// -------------------------------------------------------------
module tb_top;
    logic clk = 0;
    always #5ns clk = ~clk; // 100 MHz Core Clock

    router_if vif(clk);

    router_top dut (
        .clk(vif.clk),
        .resetn(vif.resetn),
        .pkt_valid(vif.pkt_valid),
        .data_in(vif.data_in),
        .read_enb_0(vif.read_enb_0),
        .read_enb_1(vif.read_enb_1),
        .read_enb_2(vif.read_enb_2),
        .data_out_0(vif.data_out_0),
        .data_out_1(vif.data_out_1),
        .data_out_2(vif.data_out_2),
        .vld_out_0(vif.vld_out_0),
        .vld_out_1(vif.vld_out_1),
        .vld_out_2(vif.vld_out_2),
        .err(vif.err),
        .busy(vif.busy)
    );

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, tb_top);

        vif.resetn = 0;
        #25ns;
        vif.resetn = 1;

        uvm_config_db#(virtual router_if)::set(null, "*", "vif", vif);
        run_test("router_test");
    end
endmodule