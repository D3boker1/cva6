/**************************************************************************************************
 * Copyright 2023 ETH Zurich and University of Bologna.
 * Copyright and related rights are licensed under the Solderpad Hardware License, Version 0.51 
 * (the "License"); you may not use this file except in compliance with the License.  You may
 * obtain a copy of the License at http://solderpad.org/licenses/SHL-0.51. Unless required by
 * applicable law or agreed to in writing, software, hardware and materials distributed under this
 * License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either
 * express or implied. See the License for the specific language governing permissions and
 * limitations under the License.
 *************************************************************************************************/
/*
 * Module `cfi_backend`
 *
 * The CFI backend pops data out of the log queue and sends it to the CFI mailbox using AXI. The
 * module can be configured in test mode to pop data out of the log queue and wait a configurable
 * number of cycle without triggering any AXI transaction.
 *
 * Author: Simone Manoni <simone.manoni3@unibo.it>
 *         Emanuele Parisi <emanuele.parisi@unibo.it>
 */

module cfi_backend_test import ariane_pkg::*; #(
    parameter int unsigned TEST_MODE_LATENCY = 10
) (
    input  logic              clk_i,
    input  logic              rst_ni,
    input  cfi_log_t          log_i,
    input  logic              queue_empty_i,
    output logic              queue_pop_o,
    output ariane_axi::req_t  axi_req_o,
    input  ariane_axi::resp_t axi_resp_i
);

    enum {IDLE, BUSY} state_d, state_q;

    int unsigned cnt_d, cnt_q;

    always_comb begin
        state_d     = IDLE;
        queue_pop_o = 'b0;
        cnt_d       = 'b0;
        axi_req_o   = 'b0;

        unique case (state_q)
            IDLE: begin
                queue_pop_o = 'b0;
                if (queue_empty_i) begin
                    state_d = IDLE;
                    cnt_d   = 'b0;
                end
                else begin
                    state_d = BUSY;
                    cnt_d   = TEST_MODE_LATENCY;
                end
            end
            BUSY: begin
                state_d     = BUSY;
                queue_pop_o = 'b0;
                cnt_d       = cnt_q - 1;
                if (cnt_q == 'b1) begin
                    state_d     = IDLE;
                    queue_pop_o = 'b1;
                end
            end
            default: begin
                state_d     = IDLE;
                queue_pop_o = 'b0;
                cnt_d       = 'b0;
            end
        endcase
    end

    always_ff @(posedge clk_i, negedge rst_ni) begin
        if (!rst_ni) begin
            state_q   <= IDLE;
            cnt_q     <= 'b0;
        end
        else begin
            state_q   <= state_d;
            cnt_q     <= cnt_d;
        end 
    end

endmodule


module cfi_backend_axi import ariane_pkg::*; #(
    parameter logic        [riscv::VLEN-1:0] MAILBOX_ADDR    = 'h10404000,
    parameter logic        [riscv::VLEN-1:0] MAILBOX_DB_ADDR = 'h10404020,
    parameter int unsigned                   XFER_SIZE       = 32
) (
    input  logic              clk_i,
    input  logic              rst_ni,
    input  cfi_log_t          log_i,
    input  logic              mbox_completion_irq_i,
    input  logic              queue_empty_i,
    output logic              queue_pop_o,
    output ariane_axi::req_t  axi_req_o,
    input  ariane_axi::resp_t axi_resp_i
);

    localparam int unsigned LOG_SIZE        = $bits(cfi_log_t);
    localparam int unsigned LOG_NR_XFERS    = $rtoi($ceil(1.0 * LOG_SIZE / XFER_SIZE));
    localparam int unsigned LOG_PADDED_SIZE = LOG_NR_XFERS << $clog2(XFER_SIZE);
    localparam int unsigned CNT_NR_BITS     = $clog2(LOG_NR_XFERS) + $clog2(XFER_SIZE);

    localparam int unsigned REG_TO_READ     = 8; //-- TODO: Make it configurable by an external parameter

    enum {IDLE, W_ADDR, W_DATA, W_DB_ADDR, W_DB_DATA, WAIT_COMPLETION, READ_MBOX, CHECK_RESULT, CLEAN_COMPLETION_ADDR, CLEAN_COMPLETION_W} state_d, state_q;

    logic [CNT_NR_BITS-1:0]     xfer_cnt_d, xfer_cnt_q;
    logic [LOG_PADDED_SIZE-1:0] log_padded;
    logic          fifo_full;
    logic          fifo_empty;
    logic          fifo_push;
    logic          fifo_flush;
    logic          fifo_pop;
    logic [63 : 0] fifo_data_out;

    always_comb begin
        state_d           = IDLE;
        xfer_cnt_d        = 'b0;
        log_padded        = {'0, log_i};
        queue_pop_o       = 'b0;
        axi_req_o         = 'b0;
        axi_req_o.r_ready = 'b1;
        axi_req_o.b_ready = 'b1;
        axi_req_o.w.last  = 1'b0;
        fifo_full         = 1'b0;
        fifo_empty        = 1'b0;
        fifo_push         = 1'b0;
        fifo_flush        = 1'b0;     
        fifo_pop          = 1'b0;
        unique case (state_q)
            IDLE: begin
                if (queue_empty_i) begin
                    state_d = IDLE; 
                end
                else begin
                    state_d = W_ADDR;
                end
            end
            W_ADDR: begin
                if (axi_resp_i.aw_ready) begin
                    state_d = W_DATA;
                end
                else begin
                    state_d = W_ADDR;
                end
                xfer_cnt_d         = xfer_cnt_q;
                axi_req_o.aw.id    = 'd3;
                axi_req_o.aw.burst = 'b1;
                axi_req_o.aw.len   = LOG_NR_XFERS;
                axi_req_o.aw.size  = 'b010;
                axi_req_o.aw.addr  = MAILBOX_ADDR + (xfer_cnt_q << ($clog2(XFER_SIZE) - 3));
                axi_req_o.aw_valid = 'b1;

                axi_req_o.aw.cache = 4'b0010;
            end
            W_DATA: begin
                if ((xfer_cnt_q == LOG_NR_XFERS) && axi_resp_i.w_ready) begin
                    state_d    = W_DB_ADDR;
                    xfer_cnt_d = 'b0;
                    axi_req_o.w.last  = 'b1; 
                end
                else if (axi_resp_i.w_ready) begin
                    state_d    = W_DATA;
                    xfer_cnt_d = xfer_cnt_q + 1;
                end
                else begin
                    state_d       = W_DATA;
                    xfer_cnt_d    = xfer_cnt_q;
                end
                axi_req_o.w_valid = 'b1; 
                axi_req_o.w.strb  = 'hff; 
                axi_req_o.w.data  = {'0, log_padded[xfer_cnt_q << $clog2(XFER_SIZE)+:XFER_SIZE]}; 
            end
            W_DB_ADDR: begin
                xfer_cnt_d = 'b0;
                if (axi_resp_i.aw_ready) begin
                    state_d = W_DB_DATA;
                end
                else begin
                    state_d = W_DB_ADDR;
                end
                axi_req_o.aw.burst = 'b1;
                axi_req_o.aw.size  = 'b010;
                axi_req_o.aw.addr  = MAILBOX_DB_ADDR;
                axi_req_o.aw_valid = 'b1; 
            end
            W_DB_DATA: begin
                if(axi_resp_i.w_ready) begin
                    state_d = WAIT_COMPLETION;
                end
                else begin
                    state_d = W_DB_DATA;
                end
                axi_req_o.w_valid = 'b1;
                axi_req_o.w.data  = 'b1;
                axi_req_o.w.last  = 'b1;
                axi_req_o.w.strb  = 'hff;
                if (axi_resp_i.w_ready) begin
                    queue_pop_o = 1'b1;
                end
            end
            WAIT_COMPLETION: begin
                if(mbox_completion_irq_i)
                    state_d = READ_MBOX;

                else
                    state_d = WAIT_COMPLETION;       
            end
            READ_MBOX: begin
                if(axi_resp_i.aw_ready)
                    xfer_cnt_d = xfer_cnt_q + 2;
                if(xfer_cnt_d == REG_TO_READ)
                    state_d = CLEAN_COMPLETION_ADDR;    
                else    
                    state_d = READ_MBOX;  
                if(axi_resp_i.r_valid && !fifo_full)
                    fifo_push = 1'b1;
                axi_req_o.ar_valid = 1'b1;
                axi_req_o.ar.addr  = MAILBOX_ADDR;
                axi_req_o.ar.burst = 1'b1;
                axi_req_o.aw.size  = 3'd3;
                axi_req_o.aw.len   = REG_TO_READ >> 1;
                axi_req_o.r_ready  = !fifo_full;
            end
            CLEAN_COMPLETION_ADDR: begin
                axi_req_o.aw.burst = 'b1;
                axi_req_o.aw.size  = 'b010;
                axi_req_o.aw.addr  = MAILBOX_DB_ADDR + 4; // Mbox Completion Addr
                axi_req_o.aw_valid = 'b1;
                if(axi_resp_i.aw_ready)
                    state_d = CLEAN_COMPLETION_W;
                else    
                    state_d = CLEAN_COMPLETION_ADDR; 
            end  
            CLEAN_COMPLETION_W: begin
                axi_req_o.w_valid = 'b1;
                axi_req_o.w.data  = 'b1;
                axi_req_o.w.last  = 'b1;
                axi_req_o.w.strb  = 'hff;
                if(axi_resp_i.w_ready)
                    state_d = IDLE;
                else    
                    state_d = CLEAN_COMPLETION_W;
            end  
            default: begin
                state_d = IDLE;
            end
        endcase
    end

    always_ff @(posedge clk_i, negedge rst_ni) begin
        if (!rst_ni) begin
            state_q    <= IDLE;
            xfer_cnt_q <= 'b0;
        end
        else begin
            state_q    <= state_d;
            xfer_cnt_q <= xfer_cnt_d;
        end
    end

    //-- FIFO to store reccived data

    fifo_v3 #(
        .FALL_THROUGH   (1'b0         ),     // fifo is in fall-through mode
        .DATA_WIDTH     (64           ),    // default data width if the fifo is of type logic
        .DEPTH          (REG_TO_READ  )    // depth can be arbitrary from 0 to 2**32
    ) i_rx_fifo (
        .clk_i          (clk_i        ), 
        .rst_ni         (rst_ni       ), 
        .flush_i        (fifo_flush   ), 
        .testmode_i     (1'b0         ), 
    // status flags
        .full_o         (fifo_full    ),  
        .empty_o        (fifo_empty   ),   
        .usage_o        (             ),  
    // as long as the queue is not full 
        .data_i         (axi_resp_i.r ), 
        .push_i         (fifo_push    ), 
    // as long as the queue is not empty we can pop new elements
        .data_o         (fifo_data_out),  
        .pop_i          (fifo_pop     )   
    );

endmodule


module cfi_backend import ariane_pkg::*; #(
    parameter logic        [riscv::VLEN-1:0] MAILBOX_ADDR      = 'h10404000,
    parameter logic        [riscv::VLEN-1:0] MAILBOX_DB_ADDR   = 'h10404020,
    parameter int unsigned                   XFER_SIZE         = 32,
    parameter int unsigned                   TEST_MODE_ENABLE  = 0,
    parameter int unsigned                   TEST_MODE_LATENCY = 10
) (
    input  logic              clk_i,
    input  logic              rst_ni,
    input  cfi_log_t          log_i,
    input  logic              mbox_completion_irq_i,
    input  logic              queue_empty_i,
    output logic              queue_pop_o,
    output ariane_axi::req_t  axi_req_o,
    input  ariane_axi::resp_t axi_resp_i
);

    generate
        if (TEST_MODE_ENABLE) begin
            cfi_backend_test #(
                .TEST_MODE_LATENCY ( TEST_MODE_LATENCY )
            ) cfi_backend_core_i (
                .clk_i         ( clk_i         ),
                .rst_ni        ( rst_ni        ),
                .log_i         ( log_i         ),
                .queue_empty_i ( queue_empty_i ),
                .queue_pop_o   ( queue_pop_o   ),
                .axi_req_o     ( axi_req_o     ),
                .axi_resp_i    ( axi_resp_i    )
            );
        end
        else begin
            cfi_backend_axi #(
                .MAILBOX_ADDR           ( MAILBOX_ADDR          ),
                .MAILBOX_DB_ADDR        ( MAILBOX_DB_ADDR       ),
                .XFER_SIZE              ( XFER_SIZE             )
            ) cfi_backend_core_i (      
                .clk_i                  ( clk_i                 ),
                .rst_ni                 ( rst_ni                ),
                .log_i                  ( log_i                 ),
                .mbox_completion_irq_i  ( mbox_completion_irq_i ),
                .queue_empty_i          ( queue_empty_i         ),
                .queue_pop_o            ( queue_pop_o           ),
                .axi_req_o              ( axi_req_o             ),
                .axi_resp_i             ( axi_resp_i            )
            );
        end
    endgenerate

endmodule
