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

module cfi_filter import cfi_pkg::*; #(
    paramenter int unsigned NR_COMMIT_PORTS=2
) (
    input  ariane_pkg::scoreboard_entry_t [NR_COMMIT_PORTS-1:0] instr_i,
    input  cfi_flags_t                                          flags_m_i,
    input  cfi_flags_t                                          flags_h_i,
    input  cfi_flags_t                                          flags_s_i,
    input  cfi_flags_t                                          flags_u_i,
    input  riscv::priv_lvl_t                                    priv_lvl_i,
    output cfi_log_t                      [NR_COMMIT_PORTS-1:0] log_o,
    output logic                          [NR_COMMIT_PORTS-1:0] cfi_o
);

    logic [NR_COMMIT_PORTS-1:0] instr_branch;
    logic [NR_COMMIT_PORTS-1:0] instr_jal;
    logic [NR_COMMIT_PORTS-1:0] instr_jalr;
    logic [NR_COMMIT_PORTS-1:0] instr_rd_x1_x5;
    logic [NR_COMMIT_PORTS-1:0] instr_rs_x1_x5;

    for (genvar i=0; i<NR_COMMIT_PORTS; i++) begin
        always_comb begin
            // Detect control flow transfer type.
            instr_branch[i]    = 'b0;
            instr_jal[i]       = 'b0;
            instr_jalr[i]      = 'b0;
            if (instr_i[i].fu == CTRL_FLOW) begin
                unique case (instr_i[i].op)
                    EQ, NE, LTS, GES, LTU, GEU: instr_branch[i] = 'b1;
                    JALR:                       instr_jalr[i]   = 'b1;
                    default:                    instr_jal[i]    = 'b1;
                endcase
            end

            // Detect if the destination/source registers are x1 or x5.
            instr_rs_x1_x5[i] = (instr_i[i].rs == 5'd1) || (instr_i[i].rs == 5'd5);
            instr_rd_x1_x5[i] = (instr_i[i].rd == 5'd1) || (instr_i[i].rd == 5'd5);        

            // Extract CFI log from scoreboard entry.
            log_o[i].flags.is_branch = 'b0;
            log_o[i].flags.is_jump   = 'b0;
            log_o[i].flags.is_call   = 'b0;
            log_o[i].flags.is_return = 'b0;
            log_o[i].addr_pc         = 'b0;
            log_o[i].addr_npc        = 'b0;
            log_o[i].addr_target     = 'b0;
            if (sbe_i.valid && sbe_i.fu == CTRL_FLOW) begin
                log_o[i].flags.is_branch = instr_branch[i];
                log_o[i].flags.is_jump   = instr_jal[i] || instr_jalr[i];
                log_o[i].flags.is_call   = (instr_jal[i] || instr_jalr[i]) && instr_rd_x1_x5[i];
                log_o[i].flags.is_return = instr_jalr[i] && instr_rs_x1_x5[i];
                log_o[i].addr_pc         = instr_i[i].pc;
                log_o[i].addr_npc        = instr_i[i].result;
                log_o[i].addr_target     = instr_i[i].bp.predict_address;
            end

            // Control the control-flow integrity output flag.
            unique case (priv_lvl_i)
                PRIV_LVL_M:  cfi_o = |(flags_m_i && log_o[i].flags);
                PRIV_LVL_HS: cfi_o = |(flags_h_i && log_o[i].flags);
                PRIV_LVL_S:  cfi_o = |(flags_s_i && log_o[i].flags);
                default:     cfi_o = |(flags_u_i && log_o[i].flags);
            endcase
        end
    end

endmodule
