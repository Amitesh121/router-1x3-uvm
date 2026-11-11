// Code your design here
`timescale 1ns/1ps

// =============================================================
// Router 1x3 Top-Level RTL Module
// =============================================================
module router_top (
    input  logic        clk,
    input  logic        resetn,
    input  logic        pkt_valid,
    input  logic [7:0]  data_in,
    input  logic        read_enb_0,
    input  logic        read_enb_1,
    input  logic        read_enb_2,

    output logic [7:0]  data_out_0,
    output logic [7:0]  data_out_1,
    output logic [7:0]  data_out_2,
    output logic        vld_out_0,
    output logic        vld_out_1,
    output logic        vld_out_2,
    output logic        err,
    output logic        busy
);

    // Internal inter-module nets
    logic [2:0]  write_enb;
    logic [7:0]  internal_dout;
    logic        full_0, full_1, full_2;
    logic        empty_0, empty_1, empty_2;
    logic        soft_reset_0, soft_reset_1, soft_reset_2;
    logic        detect_add, ld_state, laf_state, full_state, lfd_state, rst_int_reg;
    logic        parity_done, low_pkt_valid;

    assign vld_out_0 = ~empty_0;
    assign vld_out_1 = ~empty_1;
    assign vld_out_2 = ~empty_2;

    // ---------------------------------------------------------
    // Synchronizer & Routing Engine
    // ---------------------------------------------------------
    router_sync sync_inst (
        .clk(clk),
        .resetn(resetn),
        .detect_add(detect_add),
        .data_in(data_in[1:0]),
        .write_enb_reg(write_enb),
        .full_0(full_0),
        .full_1(full_1),
        .full_2(full_2),
        .empty_0(empty_0),
        .empty_1(empty_1),
        .empty_2(empty_2),
        .read_enb_0(read_enb_0),
        .read_enb_1(read_enb_1),
        .read_enb_2(read_enb_2),
        .soft_reset_0(soft_reset_0),
        .soft_reset_1(soft_reset_1),
        .soft_reset_2(soft_reset_2)
    );

    // ---------------------------------------------------------
    // Central Controller FSM
    // ---------------------------------------------------------
    router_fsm fsm_inst (
        .clk(clk),
        .resetn(resetn),
        .pkt_valid(pkt_valid),
        .data_in(data_in[1:0]),
        .fifo_full_0(full_0),
        .fifo_full_1(full_1),
        .fifo_full_2(full_2),
        .fifo_empty_0(empty_0),
        .fifo_empty_1(empty_1),
        .fifo_empty_2(empty_2),
        .soft_reset_0(soft_reset_0),
        .soft_reset_1(soft_reset_1),
        .soft_reset_2(soft_reset_2),
        .parity_done(parity_done),
        .low_pkt_valid(low_pkt_valid),
        .write_enb_reg(write_enb),
        .detect_add(detect_add),
        .ld_state(ld_state),
        .laf_state(laf_state),
        .lfd_state(lfd_state),
        .full_state(full_state),
        .rst_int_reg(rst_int_reg),
        .busy(busy)
    );

    // ---------------------------------------------------------
    // Internal Datapath Register & Parity Checker
    // ---------------------------------------------------------
    router_reg reg_inst (
        .clk(clk),
        .resetn(resetn),
        .pkt_valid(pkt_valid),
        .data_in(data_in),
        .fifo_full_0(full_0),
        .fifo_full_1(full_1),
        .fifo_full_2(full_2),
        .detect_add(detect_add),
        .ld_state(ld_state),
        .laf_state(laf_state),
        .full_state(full_state),
        .lfd_state(lfd_state),
        .rst_int_reg(rst_int_reg),
        .err(err),
        .parity_done(parity_done),
        .low_pkt_valid(low_pkt_valid),
        .dout(internal_dout)
    );

    // ---------------------------------------------------------
    // Three Egress Channel FIFO Buffers
    // ---------------------------------------------------------
    router_fifo fifo_0 (
        .clk(clk),
        .resetn(resetn),
        .soft_reset(soft_reset_0),
        .write_enb(write_enb[0]),
        .read_enb(read_enb_0),
        .lfd_state(lfd_state),
        .data_in(internal_dout),
        .data_out(data_out_0),
        .empty(empty_0),
        .full(full_0)
    );

    router_fifo fifo_1 (
        .clk(clk),
        .resetn(resetn),
        .soft_reset(soft_reset_1),
        .write_enb(write_enb[1]),
        .read_enb(read_enb_1),
        .lfd_state(lfd_state),
        .data_in(internal_dout),
        .data_out(data_out_1),
        .empty(empty_1),
        .full(full_1)
    );

    router_fifo fifo_2 (
        .clk(clk),
        .resetn(resetn),
        .soft_reset(soft_reset_2),
        .write_enb(write_enb[2]),
        .read_enb(read_enb_2),
        .lfd_state(lfd_state),
        .data_in(internal_dout),
        .data_out(data_out_2),
        .empty(empty_2),
        .full(full_2)
    );

endmodule

// =============================================================
// Synchronizer & Soft-Reset Module
// =============================================================
module router_sync (
    input  logic       clk,
    input  logic       resetn,
    input  logic       detect_add,
    input  logic [1:0] data_in,
    input  logic [2:0] write_enb_reg,
    input  logic       full_0, full_1, full_2,
    input  logic       empty_0, empty_1, empty_2,
    input  logic       read_enb_0, read_enb_1, read_enb_2,
    output logic       soft_reset_0, soft_reset_1, soft_reset_2
);
    logic [1:0] int_addr_reg;
    logic [4:0] count_0, count_1, count_2;

    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn)
            int_addr_reg <= 2'b0;
        else if (detect_add)
            int_addr_reg <= data_in;
    end

    // Soft-Reset Counters (triggers soft reset if packet waits unread for 30 cycles)
    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            count_0 <= '0; soft_reset_0 <= '0;
            count_1 <= '0; soft_reset_1 <= '0;
            count_2 <= '0; soft_reset_2 <= '0;
        end else begin
            // Port 0
            if (!empty_0 && !read_enb_0) begin
                if (count_0 == 5'd29) begin soft_reset_0 <= 1'b1; count_0 <= '0; end
                else begin count_0 <= count_0 + 1'b1; soft_reset_0 <= 1'b0; end
            end else begin count_0 <= '0; soft_reset_0 <= 1'b0; end

            // Port 1
            if (!empty_1 && !read_enb_1) begin
                if (count_1 == 5'd29) begin soft_reset_1 <= 1'b1; count_1 <= '0; end
                else begin count_1 <= count_1 + 1'b1; soft_reset_1 <= 1'b0; end
            end else begin count_1 <= '0; soft_reset_1 <= 1'b0; end

            // Port 2
            if (!empty_2 && !read_enb_2) begin
                if (count_2 == 5'd29) begin soft_reset_2 <= 1'b1; count_2 <= '0; end
                else begin count_2 <= count_2 + 1'b1; soft_reset_2 <= 1'b0; end
            end else begin count_2 <= '0; soft_reset_2 <= 1'b0; end
        end
    end
endmodule

// =============================================================
// Central FSM Controller
// =============================================================
module router_fsm (
    input  logic       clk,
    input  logic       resetn,
    input  logic       pkt_valid,
    input  logic [1:0] data_in,
    input  logic       fifo_full_0, fifo_full_1, fifo_full_2,
    input  logic       fifo_empty_0, fifo_empty_1, fifo_empty_2,
    input  logic       soft_reset_0, soft_reset_1, soft_reset_2,
    input  logic       parity_done,
    input  logic       low_pkt_valid,
    output logic [2:0] write_enb_reg,
    output logic       detect_add,
    output logic       ld_state,
    output logic       laf_state,
    output logic       lfd_state,
    output logic       full_state,
    output logic       rst_int_reg,
    output logic       busy
);
    typedef enum logic [2:0] {
        DECODE_ADDRESS       = 3'b000,
        LOAD_FIRST_DATA      = 3'b001,
        LOAD_DATA            = 3'b010,
        FIFO_FULL_STATE      = 3'b011,
        LOAD_AFTER_FULL      = 3'b100,
        LOAD_PARITY          = 3'b101,
        CHECK_PARITY_ERROR   = 3'b110,
        WAIT_TILL_EMPTY      = 3'b111
    } state_t;

    state_t state, next_state;
    logic [1:0] addr_latched;

    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn)
            addr_latched <= 2'b0;
        else if (detect_add)
            addr_latched <= data_in;
    end

    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn)
            state <= DECODE_ADDRESS;
        else if (soft_reset_0 || soft_reset_1 || soft_reset_2)
            state <= DECODE_ADDRESS;
        else
            state <= next_state;
    end

    // Next State Logic
    always_comb begin
        next_state = state;
        case (state)
            DECODE_ADDRESS: begin
                if ((pkt_valid && (data_in == 2'b00) && fifo_empty_0) ||
                    (pkt_valid && (data_in == 2'b01) && fifo_empty_1) ||
                    (pkt_valid && (data_in == 2'b10) && fifo_empty_2))
                    next_state = LOAD_FIRST_DATA;
                else if (pkt_valid)
                    next_state = WAIT_TILL_EMPTY;
            end
            LOAD_FIRST_DATA: next_state = LOAD_DATA;
            LOAD_DATA: begin
                if ((addr_latched == 2'b00 && fifo_full_0) ||
                    (addr_latched == 2'b01 && fifo_full_1) ||
                    (addr_latched == 2'b10 && fifo_full_2))
                    next_state = FIFO_FULL_STATE;
                else if (!pkt_valid)
                    next_state = LOAD_PARITY;
            end
            FIFO_FULL_STATE: begin
                if ((addr_latched == 2'b00 && !fifo_full_0) ||
                    (addr_latched == 2'b01 && !fifo_full_1) ||
                    (addr_latched == 2'b10 && !fifo_full_2))
                    next_state = LOAD_AFTER_FULL;
            end
            LOAD_AFTER_FULL: begin
                if (!parity_done && low_pkt_valid)
                    next_state = LOAD_PARITY;
                else if (!parity_done)
                    next_state = LOAD_DATA;
                else
                    next_state = DECODE_ADDRESS;
            end
            LOAD_PARITY: next_state = CHECK_PARITY_ERROR;
            CHECK_PARITY_ERROR: begin
                if ((addr_latched == 2'b00 && fifo_full_0) ||
                    (addr_latched == 2'b01 && fifo_full_1) ||
                    (addr_latched == 2'b10 && fifo_full_2))
                    next_state = FIFO_FULL_STATE;
                else
                    next_state = DECODE_ADDRESS;
            end
            WAIT_TILL_EMPTY: begin
                if ((addr_latched == 2'b00 && fifo_empty_0) ||
                    (addr_latched == 2'b01 && fifo_empty_1) ||
                    (addr_latched == 2'b10 && fifo_empty_2))
                    next_state = LOAD_FIRST_DATA;
            end
            default: next_state = DECODE_ADDRESS;
        endcase
    end

    // Output assignments
    assign detect_add  = (state == DECODE_ADDRESS);
    assign lfd_state   = (state == LOAD_FIRST_DATA);
    assign ld_state    = (state == LOAD_DATA);
    assign full_state  = (state == FIFO_FULL_STATE);
    assign laf_state   = (state == LOAD_AFTER_FULL);
    assign rst_int_reg = (state == CHECK_PARITY_ERROR);
    assign busy        = (state != DECODE_ADDRESS && state != LOAD_DATA);

    always_comb begin
        write_enb_reg = 3'b0;
        if (state == LOAD_DATA || state == LOAD_AFTER_FULL || state == LOAD_PARITY) begin
            case (addr_latched)
                2'b00: write_enb_reg = 3'b001;
                2'b01: write_enb_reg = 3'b010;
                2'b10: write_enb_reg = 3'b100;
                default: write_enb_reg = 3'b000;
            endcase
        end
    end
endmodule

// =============================================================
// Router Datapath Register & Parity Check Logic
// =============================================================
module router_reg (
    input  logic       clk,
    input  logic       resetn,
    input  logic       pkt_valid,
    input  logic [7:0] data_in,
    input  logic       fifo_full_0, fifo_full_1, fifo_full_2,
    input  logic       detect_add,
    input  logic       ld_state,
    input  logic       laf_state,
    input  logic       full_state,
    input  logic       lfd_state,
    input  logic       rst_int_reg,
    output logic       err,
    output logic       parity_done,
    output logic       low_pkt_valid,
    output logic [7:0] dout
);
    logic [7:0] header_byte, fifo_full_state_byte, internal_parity, packet_parity;

    // Latch low packet valid
    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn)
            low_pkt_valid <= 1'b0;
        else if (rst_int_reg)
            low_pkt_valid <= 1'b0;
        else if (ld_state && !pkt_valid)
            low_pkt_valid <= 1'b1;
    end

    // Parity Done
    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn)
            parity_done <= 1'b0;
        else if (detect_add)
            parity_done <= 1'b0;
        else if ((ld_state && !pkt_valid) || (laf_state && low_pkt_valid && !parity_done))
            parity_done <= 1'b1;
    end

    // Dout Logic
    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            dout <= 8'b0;
            header_byte <= 8'b0;
            fifo_full_state_byte <= 8'b0;
        end else begin
            if (detect_add && pkt_valid)
                header_byte <= data_in;
            else if (lfd_state)
                dout <= header_byte;
            else if (ld_state && !fifo_full_0 && !fifo_full_1 && !fifo_full_2)
                dout <= data_in;
            else if (ld_state && (fifo_full_0 || fifo_full_1 || fifo_full_2))
                fifo_full_state_byte <= data_in;
            else if (laf_state)
                dout <= fifo_full_state_byte;
        end
    end

    // Parity Calculation & Verification
    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            internal_parity <= 8'b0;
            packet_parity   <= 8'b0;
            err             <= 1'b0;
        end else if (detect_add) begin
            internal_parity <= 8'b0;
            err             <= 1'b0;
        end else if (lfd_state) begin
            internal_parity <= internal_parity ^ header_byte;
        end else if (ld_state && pkt_valid) begin
            internal_parity <= internal_parity ^ data_in;
        end else if (!pkt_valid && ld_state) begin
            packet_parity <= data_in;
        end else if (rst_int_reg) begin
            if (packet_parity != internal_parity)
                err <= 1'b1;
            else
                err <= 1'b0;
        end
    end
endmodule

// =============================================================
// Synchronous Egress FIFO Block
// =============================================================
module router_fifo (
    input  logic       clk,
    input  logic       resetn,
    input  logic       soft_reset,
    input  logic       write_enb,
    input  logic       read_enb,
    input  logic       lfd_state,
    input  logic [7:0] data_in,
    output logic [7:0] data_out,
    output logic       empty,
    output logic       full
);
    logic [4:0] wr_ptr, rd_ptr;
    logic [8:0] mem [0:15]; // Bit 8 is the lfd header marker
    logic [6:0] count;

    assign full  = (wr_ptr == {~rd_ptr[4], rd_ptr[3:0]});
    assign empty = (wr_ptr == rd_ptr);

    // Write Logic
    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn || soft_reset) begin
            wr_ptr <= '0;
        end else if (write_enb && !full) begin
            mem[wr_ptr[3:0]] <= {lfd_state, data_in};
            wr_ptr <= wr_ptr + 1'b1;
        end
    end

    // Read Logic
    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn || soft_reset) begin
            rd_ptr   <= '0;
            data_out <= '0;
        end else if (read_enb && !empty) begin
            data_out <= mem[rd_ptr[3:0]][7:0];
            rd_ptr   <= rd_ptr + 1'b1;
        end
    end
endmodule