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
 * Module `cfi_filter`
 *
 * Filter each CVA6 commit port according to the CFI rules received as input.
 *
 * Author: Emanuele Parisi <emanuele.parisi@unibo.it> 
 */

module cfi_filter import ariane_pkg::*; #(
    parameter int unsigned NR_COMMIT_PORTS = 2,
    parameter int unsigned NR_CFI_RULES    = 4
)(
    input  scoreboard_entry_t [NR_COMMIT_PORTS-1:0] commit_sbe_i,
    input  logic              [NR_COMMIT_PORTS-1:0] commit_ack_i,
    input  cfi_rule_t         [NR_CFI_RULES-1:0]    cfi_rules_i,
    output cfi_log_t          [NR_COMMIT_PORTS-1:0] log_o,
    output logic              [NR_COMMIT_PORTS-1:0] log_valid_o
);

    logic [NR_COMMIT_PORTS-1:0][NR_CFI_RULES-1:0][31:0] rule_masked;
    logic [NR_COMMIT_PORTS-1:0][NR_CFI_RULES-1:0]       rule_match;
    logic [NR_COMMIT_PORTS-1:0][NR_CFI_RULES-1:0]       rule_enable;

    always_comb begin
        // Extract CFI commit log from the input scoreboard entry.
        for (int unsigned i=0; i<NR_COMMIT_PORTS; i++) begin
            log_o[i].instr       = commit_sbe_i[i].instr;
            log_o[i].addr_pc     = commit_sbe_i[i].pc;
            log_o[i].addr_npc    = commit_sbe_i[i].result;
            log_o[i].addr_target = commit_sbe_i[i].bp.predict_address;
        end

        // Match the commit instruction with the configured CFI rules.
        for (int unsigned i=0; i<NR_COMMIT_PORTS; i++) begin
            for (int unsigned j=0; j<NR_CFI_RULES; j++) begin
                rule_masked[i][j] = commit_sbe_i[i].instr & cfi_rules_i[j].mask;
                rule_match[i][j]  = rule_masked[i][j] == cfi_rules_i[j].pred;
                rule_enable[i][j] = cfi_rules_i[j].en;
            end
        end

        // Compute `log_valid_o` output signal.
        for (int unsigned i=0; i<NR_COMMIT_PORTS; i++) begin
            log_valid_o[i] = rule_match[i] & rule_enable[i] & commit_ack_i[i];
        end
    end

endmodule
