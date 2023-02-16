/*******************************************************************************
 * Copyright 2023 ETH Zurich and University of Bologna.
 * Copyright and related rights are licensed under the Solderpad Hardware
 * License, Version 0.51 (the "License"); you may not use this file except in
 * compliance with the License.  You may obtain a copy of the License at
 * http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
 * or agreed to in writing, software, hardware and materials distributed under
 * this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
 * CONDITIONS OF ANY KIND, either express or implied. See the License for the
 * specific language governing permissions and limitations under the License.
 ******************************************************************************/
/*
 * Module `cfi_stage`
 *
 * This module wraps the Control-Flow Integrity logic for the CVA6 core.
 *
 * Author: Emanuele Parisi <emanuele.parisi@unibo.it> 
 */

module cfi_stage import ariane_pkg::*; #(
  NR_COMMIT_PORTS = 2
) (
  input  logic                                    clk_i,
  input  logic                                    rst_ni,
  input  scoreboard_entry_t [NR_COMMIT_PORTS-1:0] commit_sbe_i,
  input  logic              [NR_COMMIT_PORTS-1:0] commit_ack_i,
  output logic                                    cfi_wait_o,
  output exception_t                              cfi_fault_o
);

  assign cfi_wait_o  = 'b0;
  assign cfi_fault_o = 'b0;

endmodule
