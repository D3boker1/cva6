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

module cfi_stage import ariane_pkg::*; #(
    parameter int unsigned                   NR_COMMIT_PORTS       = 2,
    parameter int unsigned                   NR_CFI_RULES          = 4,
    parameter int unsigned                   NR_CFI_QUEUE_ENTRIES  = 4,
    parameter logic        [riscv::VLEN-1:0] CFI_MAILBOX_ADDR      = 'h10404000,
    parameter logic        [riscv::VLEN-1:0] CFI_MAILBOX_DB_ADDR   = 'h10404020,
    parameter int unsigned                   CFI_XFER_SIZE         = 32,
    parameter int unsigned                   CFI_TEST_MODE_ENABLE  = 0,
    parameter int unsigned                   CFI_TEST_MODE_LATENCY = 10
)(
    input  logic                                    clk_i,
    input  logic                                    rst_ni,
    input  scoreboard_entry_t [NR_COMMIT_PORTS-1:0] commit_sbe_i,
    input  logic              [NR_COMMIT_PORTS-1:0] commit_ack_i,
    input  cfi_rule_t         [NR_CFI_RULES-1:0]    cfi_rules_i,
    input  logic                                    mbox_completion_irq_i,
    output logic                                    cfi_halt_o,
    output ariane_axi::req_t                        cfi_axi_req_o,
    input  ariane_axi::resp_t                       cfi_axi_resp_i
);

    cfi_log_t [NR_COMMIT_PORTS-1:0] filter_log;
    logic     [NR_COMMIT_PORTS-1:0] filter_valid;
    logic                           queue_full;
    logic                           queue_empty;
    cfi_log_t                       queue_data_in;
    logic                           queue_push;
    cfi_log_t                       queue_data_out;
    logic                           queue_pop;

    cfi_filter #(
        .NR_COMMIT_PORTS ( NR_COMMIT_PORTS ),
        .NR_CFI_RULES    ( NR_CFI_RULES    )
    ) cfi_filter_i (
        .commit_sbe_i ( commit_sbe_i ),
        .commit_ack_i ( commit_ack_i ),
        .cfi_rules_i  ( cfi_rules_i  ),
        .log_o        ( filter_log   ),
        .log_valid_o  ( filter_valid )
    );

    cfi_queue_ctrl #(
        .NR_COMMIT_PORTS ( NR_COMMIT_PORTS )
    ) cfi_queue_ctrl_i (
        .clk_i        ( clk_i         ),
        .rst_ni       ( rst_ni        ),
        .log_i        ( filter_log    ),
        .log_valid_i  ( filter_valid  ),
        .queue_full_i ( queue_full    ),
        .queue_push_o ( queue_push    ),
        .queue_data_o ( queue_data_in ),
        .cfi_halt_o   ( cfi_halt_o    )
    );

    fifo_v3 #(
        .FALL_THROUGH ( 1'b1                 ),
        .dtype        ( cfi_log_t            ),
        .DEPTH        ( NR_CFI_QUEUE_ENTRIES )
    ) cfi_queue_i (
        .clk_i      ( clk_i          ),
        .rst_ni     ( rst_ni         ),
        .flush_i    ( 'b0            ),
        .testmode_i ( 'b0            ),
        .full_o     ( queue_full     ),
        .empty_o    ( queue_empty    ),
        .usage_o    (                ),
        .data_i     ( queue_data_in  ),
        .push_i     ( queue_push     ),
        .data_o     ( queue_data_out ),
        .pop_i      ( queue_pop      )
    );

    cfi_backend #(
        .MAILBOX_ADDR           ( CFI_MAILBOX_ADDR      ),
        .MAILBOX_DB_ADDR        ( CFI_MAILBOX_DB_ADDR   ),
        .XFER_SIZE              ( CFI_XFER_SIZE         ),
        .TEST_MODE_ENABLE       ( CFI_TEST_MODE_ENABLE  ),
        .TEST_MODE_LATENCY      ( CFI_TEST_MODE_LATENCY )
    ) cfi_backend_i (
        .clk_i                  ( clk_i                 ),
        .rst_ni                 ( rst_ni                ),
        .log_i                  ( queue_data_out        ),
        .mbox_completion_irq_i  ( mbox_completion_irq_i ),
        .queue_empty_i          ( queue_empty           ),
        .queue_pop_o            ( queue_pop             ),
        .axi_req_o              ( cfi_axi_req_o         ),
        .axi_resp_i             ( cfi_axi_resp_i        )
    );

endmodule
