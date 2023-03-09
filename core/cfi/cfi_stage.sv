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
 * Module `cfi_stage`
 *
 * This module wraps the Control-Flow Integrity logic for the CVA6 core.
 *
 * Author: Emanuele Parisi <emanuele.parisi@unibo.it> 
 */

module cfi_stage import ariane_pkg::*, cfi_pkg::*; #(
    parameter int unsigned NR_COMMIT_PORTS  = 2,
    parameter int unsigned NR_QUEUE_ENTRIES = 8
) (
    input  logic                                    clk_i,
    input  logic                                    rst_ni,
    input  scoreboard_entry_t [NR_COMMIT_PORTS-1:0] commit_sbe_i,
    input  logic              [NR_COMMIT_PORTS-1:0] commit_ack_i,
    output logic                                    cfi_wait_o,
    output exception_t                              cfi_fault_o
);

    cfi_commit_log_t [NR_COMMIT_PORTS-1:0] filter_log;
    logic            [NR_COMMIT_PORTS-1:0] filter_cfi;
    logic                                  queue_full;
    logic                                  queue_empty;
    logic                                  queue_usage;
    logic                                  queue_data_in;
    logic                                  queue_push;
    logic                                  queue_data_out;
    logic                                  queue_pop;

    cfi_filter #(
        .NR_COMMIT_PORTS(NR_COMMIT_PORTS)
    ) cfi_filter_i (
        .instr_i    ( commit_sbe_i      ),
        .flags_m_i  ( 'b1111            ),
        .flags_h_i  ( 'b0000            ),
        .flags_s_i  ( 'b0000            ),
        .flags_u_i  ( 'b0000            ),
        .priv_lvl_i ( riscv::PRIV_LVL_M ),
        .log_o      ( filter_log        ),
        .cfi_o      ( filter_cfi        )
    );

    logic [NR_COMMIT_PORTS-1:0] filter_cfi2;

    always_comb begin
        filter_cfi2[0] = filter_cfi[0] && (filter_log[0].addr_pc > 'h80000000);
        filter_cfi2[1] = filter_cfi[1] && (filter_log[1].addr_pc > 'h80000000);
    end 

    cfi_queue_ctrl #(
        .NR_COMMIT_PORTS ( NR_COMMIT_PORTS )
    ) cfi_queue_ctrl_i (
        .clk_i        ( clk_i         ),
        .rst_ni       ( rst_ni        ),
        .log_i        ( filter_log    ),
        .log_cfi_i    ( filter_cfi2   ),
        .log_ack_i    ( commit_ack_i  ),
        .queue_full_i ( queue_full    ),
        .queue_push_o ( queue_push    ),
        .queue_data_o ( queue_data_in ),
        .cfi_halt_o   ( cfi_wait_o    )
    );

    fifo_v3 #(
        .FALL_THROUGH ( 1'b1                      ),
        .DATA_WIDTH   ( $bits(scoreboard_entry_t) ),
        .DEPTH        ( NR_QUEUE_ENTRIES          )
    ) cfi_queue_i (
        .clk_i      ( clk_i          ),
        .rst_ni     ( rst_ni         ),
        .flush_i    ( 'b0            ),
        .testmode_i ( 'b0            ),
        .full_o     ( queue_full     ),
        .empty_o    ( queue_empty    ),
        .usage_o    ( queue_usage    ),
        .data_i     ( queue_data_in  ),
        .push_i     ( queue_push     ),
        .data_o     ( queue_data_out ),
        .pop_i      ( queue_pop      )
    );

    cfi_backend_dummy #(
        .NR_STALL_BRANCH ( 3 ),
        .NR_STALL_JUMP   ( 3 ),
        .NR_STALL_CALL   ( 3 ),
        .NR_STALL_RETURN ( 3 )
    ) cfi_backend_dummy_i (
        .clk_i             ( clk_i          ),
        .rst_ni            ( rst_ni         ),
        .log_i             ( queue_data_out ),
        .queue_empty_i     ( queue_empty    ),
        .queue_pop_o       ( queue_pop      ),
        .cfi_fault_o       ( cfi_fault_o    )
    );

endmodule
