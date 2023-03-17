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

    cfi_log_t [NR_COMMIT_PORTS-1:0]          filter_log;
    logic     [NR_COMMIT_PORTS-1:0]          filter_cfi;
    logic                                    queue_full;
    logic                                    queue_empty;
    logic     [$clog2(NR_QUEUE_ENTRIES)-1:0] queue_usage;
    cfi_log_t                                queue_data_in;
    logic                                    queue_push;
    cfi_log_t                                queue_data_out;
    logic                                    queue_pop;

    cfi_filter #(
        .NR_COMMIT_PORTS ( NR_COMMIT_PORTS ),
        .CHECK_ADDR_START( 'h8000_2000     ),
        .CHECK_ADDR_LIMIT( 'h9000_0000     )
    ) cfi_filter_i (
        .instr_i    ( commit_sbe_i      ),
        .flags_m_i  ( 4'b0100           ),
        .flags_h_i  ( 4'b0000           ),
        .flags_s_i  ( 4'b0000           ),
        .flags_u_i  ( 4'b0000           ),
        .priv_lvl_i ( riscv::PRIV_LVL_M ),
        .log_o      ( filter_log        ),
        .cfi_o      ( filter_cfi        )
    );

    cfi_queue_ctrl #(
        .NR_COMMIT_PORTS ( NR_COMMIT_PORTS )
    ) cfi_queue_ctrl_i (
        .clk_i        ( clk_i         ),
        .rst_ni       ( rst_ni        ),
        .log_i        ( filter_log    ),
        .log_cfi_i    ( filter_cfi    ),
        .log_ack_i    ( commit_ack_i  ),
        .queue_full_i ( queue_full    ),
        .queue_push_o ( queue_push    ),
        .queue_data_o ( queue_data_in ),
        .cfi_halt_o   ( cfi_wait_o    )
    );

    fifo_v3 #(
        .FALL_THROUGH ( 1'b1             ),
        .dtype        ( cfi_log_t        ),
        .DEPTH        ( NR_QUEUE_ENTRIES )
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
        .NR_STALL_BRANCH ( 5 ),
        .NR_STALL_JUMP   ( 5 ),
        .NR_STALL_CALL   ( 5 ),
        .NR_STALL_RETURN ( 5 )
    ) cfi_backend_dummy_i (
        .clk_i             ( clk_i          ),
        .rst_ni            ( rst_ni         ),
        .log_i             ( queue_data_out ),
        .queue_empty_i     ( queue_empty    ),
        .queue_pop_o       ( queue_pop      ),
        .cfi_fault_o       ( cfi_fault_o    )
    );

endmodule
