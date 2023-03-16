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
 * This module outputs the control-flow integrity log extracting information from the scoreboard 
 * entries coming from the issue stage.
 * This module decides wheter the CFI log should be analyzed according to user defined masks and
 * priviledge filters.
 *
 * Author: Emanuele Parisi <emanuele.parisi@unibo.it> 
 */

module cfi_filter import ariane_pkg::*, cfi_pkg::*; #(
    parameter int unsigned                   NR_COMMIT_PORTS=2,
    parameter logic        [riscv::VLEN-1:0] CHECK_ADDR_START='h8000_0000,
    parameter logic        [riscv::VLEN-1:0] CHECK_ADDR_LIMIT='h9000_0000
) (
    input  scoreboard_entry_t [NR_COMMIT_PORTS-1:0] instr_i,
    input  cfi_flags_t                              flags_m_i,
    input  cfi_flags_t                              flags_h_i,
    input  cfi_flags_t                              flags_s_i,
    input  cfi_flags_t                              flags_u_i,
    input  riscv::priv_lvl_t                        priv_lvl_i,
    output cfi_log_t          [NR_COMMIT_PORTS-1:0] log_o,
    output logic              [NR_COMMIT_PORTS-1:0] cfi_o
);

    logic [NR_COMMIT_PORTS-1:0] op_branch;
    logic [NR_COMMIT_PORTS-1:0] op_jal;
    logic [NR_COMMIT_PORTS-1:0] op_jalr;
    logic [NR_COMMIT_PORTS-1:0] rd_x1_x5;
    logic [NR_COMMIT_PORTS-1:0] rs1_x1_x5;
    logic [NR_COMMIT_PORTS-1:0] check_valid;
    logic [NR_COMMIT_PORTS-1:0] check_flags;
    logic [NR_COMMIT_PORTS-1:0] check_addr;

    for (genvar i=0; i<NR_COMMIT_PORTS; i++) begin
        always_comb begin
            // Get control flow operation.
            op_branch[i]    = 'b0;
            op_jal[i]       = 'b0;
            op_jalr[i]      = 'b0;
            if (instr_i[i].fu == CTRL_FLOW) begin
                unique case (instr_i[i].op)
                    EQ, NE, LTS, GES, LTU, GEU: op_branch[i] = 'b1;
                    JALR:                       op_jalr[i]   = 'b1;
                    default:                    op_jal[i]    = 'b1;
                endcase
            end

            // Get instruction RD and RS1 registers.
            rs1_x1_x5[i] = (instr_i[i].rs1 == 5'd1) || (instr_i[i].rs1 == 5'd5);
            rd_x1_x5[i]  = (instr_i[i].rd == 5'd1) || (instr_i[i].rd == 5'd5);

            // Compute CFI log.
            log_o[i].flags.branch = op_branch[i];
            log_o[i].flags.jump   = (op_jalr[i] || op_jal[i]) && !rs1_x1_x5[i] && !rd_x1_x5[i];
            log_o[i].flags.call   = (op_jalr[i] || op_jal[i]) && rd_x1_x5[i];
            log_o[i].flags.ret    = op_jalr[i] && rs1_x1_x5[i];
            log_o[i].addr_pc      = instr_i[i].pc;
            log_o[i].addr_npc     = instr_i[i].result;
            log_o[i].addr_target  = instr_i[i].bp.predict_address;

            // Check if the current control-flow transfer instruction is valid.
            check_valid[i] = 'b0;
            if (instr_i[i].valid) begin
                check_valid[i] = 'b1;
            end

            // Check if the current control-flow transfer type should be ignored.
            check_flags[i] = 'b0;
            unique case (priv_lvl_i)
                riscv::PRIV_LVL_M:  check_flags[i] = |(flags_m_i & log_o[i].flags);
                riscv::PRIV_LVL_HS: check_flags[i] = |(flags_h_i & log_o[i].flags);
                riscv::PRIV_LVL_S:  check_flags[i] = |(flags_s_i & log_o[i].flags);
                default:            check_flags[i] = |(flags_u_i & log_o[i].flags);
            endcase

            // Check if the current control-flow transfer PC should be ignored.
            check_addr[i] = 'b0;
            if (instr_i[i].pc >= CHECK_ADDR_START && instr_i[i].pc < CHECK_ADDR_LIMIT) begin
                check_addr[i] = 'b1;
            end

            // Compute CFI flag.
            cfi_o[i] = check_valid[i] && check_flags[i] && check_addr[i];
        end
    end

endmodule

