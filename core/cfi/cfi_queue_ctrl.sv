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
 * Module `cfi_queue_ctrl`
 *
 * This module controls the process of pushing control-flow integrity logs into the log queue. It
 * handles the reception of multiple commit acks halting the core and pushing the control-flow 
 * instructions ready to be checked one by one. If the commit log queue is full the core is halted.
 *
 * Author: Emanuele Parisi <emanuele.parisi@unibo.it> 
 */

module cfi_queue_ctrl import ariane_pkg::*, cfi_pkg::*; #(
    NR_COMMIT_PORTS = 2
) (
    input  logic                           clk_i,
    input  logic                           rst_ni,
    input  cfi_log_t [NR_COMMIT_PORTS-1:0] log_i,
    input  logic     [NR_COMMIT_PORTS-1:0] log_cfi_i,
    input  logic     [NR_COMMIT_PORTS-1:0] log_ack_i,
    input  logic                           queue_full_i,
    output logic                           queue_push_o,
    output cfi_log_t                       queue_data_o,
    output logic                           cfi_halt_o
);

    cfi_log_t [NR_COMMIT_PORTS-1:0]         reg_l_d, reg_l_q;
    logic     [NR_COMMIT_PORTS-1:0]         reg_v_d, reg_v_q;
    logic     [$clog2(NR_COMMIT_PORTS):0]   reg_v_popcount;
    logic     [$clog2(NR_COMMIT_PORTS)-1:0] reg_v_lzc;
    logic                                   reg_v_empty;
    logic     [NR_COMMIT_PORTS-1:0]         reg_v_mask;
    logic                                   flag_halt;
    logic                                   flag_push;

    popcount #(
        .INPUT_WIDTH (NR_COMMIT_PORTS)
    ) popcount_i (
        .data_i     (reg_v_q),
        .popcount_o (reg_v_popcount)
    );

    lzc #(
        .WIDTH (NR_COMMIT_PORTS),
        .MODE  ('b0)
    ) (
        .in_i    (reg_v_q),
        .cnt_o   (reg_v_lzc),
        .empty_o (reg_v_empty)
    );

    always_comb begin
        reg_v_d    = 'b0;
        reg_v_mask = 'b0;

        // Helper signals.
        flag_halt = (reg_v_popcount > 'b1) || (!reg_v_empty && queue_full_i);
        flag_push = !reg_v_empty && !queue_full_i;

        // CFI halt signal.
        cfi_halt_o = flag_halt;

        // Instruction queue control signals.
        queue_push_o = flag_push;
        queue_data_o = reg_l_q[reg_v_lzc];

        // Register L input control.
        reg_l_d = log_i;

        // Register V input control.
        reg_v_mask            = 'b0;
        reg_v_mask[reg_v_lzc] = 'b1;
        if (flag_halt) begin
            if (flag_push) begin
                reg_v_d = reg_v_q ^ reg_v_mask;
            end
            else begin
                reg_v_d = reg_v_q;
            end
        end
        else begin
            reg_v_d = log_cfi_i & log_ack_i;
        end
    end

    always_ff @(posedge clk_i, negedge rst_ni) begin
        if (!rst_ni) begin
            reg_l_q <= 'b0;
            reg_v_q <= 'b0;
        end
        else begin
            reg_l_q <= reg_l_d;
            reg_v_q <= reg_v_d;
        end
        
    end

endmodule
