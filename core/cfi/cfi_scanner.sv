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
 * Module `cfi_scanner`
 *
 * This module outputs the control-flow integrity log extracting information from the scoreboard 
 * entries coming from the issue stage. It also outputs a flag which signals wheter the input
 * scoreboard entry referred to a contol flow instruction or not.
 *
 * Author: Emanuele Parisi <emanuele.parisi@unibo.it> 
 */

module cfi_scanner import ariane_pkg::*, cfi_pkg::*; (
    input  scoreboard_entry_t sbe_i,
    output cfi_commit_log_t   log_o,
    output logic              cfi_o
);

    logic insn_ctrl_flow;
    logic insn_branch;
    logic insn_jal;
    logic insn_jalr;

    // Scan the input scoreboard entry to detect the type of control flow transfer.
    always_comb begin
        insn_ctrl_flow = 'b0;
        insn_branch    = 'b0;
        insn_jal       = 'b0;
        insn_jalr      = 'b0;
        if (sbe_i.fu == CTRL_FLOW) begin
            insn_ctrl_flow = 'b1;
            unique case (sbe_i.op)
                EQ, NE, LTS, GES, LTU, GEU: insn_branch = 'b1;
                JALR:                       insn_jalr   = 'b1;
                default:                    insn_jal    = 'b1;
            endcase
        end
    end

    // Assign CFI log port.
    always_comb begin
        log_o.is_branch   = 'b0;
        log_o.is_jump     = 'b0;
        log_o.is_call     = 'b0;
        log_o.is_return   = 'b0;
        log_o.addr_pc     = 'b0;
        log_o.addr_npc    = 'b0;
        log_o.addr_target = 'b0;
        if (sbe_i.valid && insn_ctrl_flow) begin
            log_o.is_branch   = insn_branch;
            log_o.is_jump     = insn_jal || insn_jalr;
            log_o.is_call     = (insn_jal || insn_jalr) && (sbe_i.rd == 5'd1 || sbe_i.rd == 5'd5);
            log_o.is_return   = insn_jalr && (sbe_i.rs1 == 5'd1 || sbe_i.rs1 == 5'd5);
            log_o.addr_pc     = sbe_i.pc;
            log_o.addr_npc    = sbe_i.result;
            log_o.addr_target = sbe_i.bp.predict_address;
        end
    end

    // Assign the control-flow entry port.
    assign cfi_o = insn_ctrl_flow && sbe_i.valid;

endmodule
