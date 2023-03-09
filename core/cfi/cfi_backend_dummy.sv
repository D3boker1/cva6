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
 * Module `cfi_backend_dummy`
 *
 * A dummy CFI backend which pops data out of the log queue and fakes some processing for a fixed
 * number of cycles. It is meant to test the CFI control module, and it never signals a CFI fault.
 *
 * Author: Emanuele Parisi <emanuele.parisi@unibo.it> 
 */

module cfi_backend_dummy import ariane_pkg::*, cfi_pkg::*; #(
    parameter int unsigned NR_STALL_BRANCH = 1,
    parameter int unsigned NR_STALL_JUMP   = 1,
    parameter int unsigned NR_STALL_CALL   = 1,
    parameter int unsigned NR_STALL_RETURN = 1
) (
    input  logic       clk_i,
    input  logic       rst_ni,
    input  cfi_log_t   log_i,
    input  logic       queue_empty_i,
    output logic       queue_pop_o,
    output exception_t cfi_fault_o
);

    enum logic {IDLE, BUSY} curr_state, next_state;

    int unsigned counter_d, counter_q;

    always_comb begin
        next_state  = IDLE;
        queue_pop_o = 'b0;
        counter_d   = 'b0;
        cfi_fault_o = 'b0;

        unique case (curr_state)
            IDLE: begin
                if (queue_empty_i) begin
                    next_state  = IDLE;
                    queue_pop_o = 'b0;
                    counter_d   = 'b0;
                end
                else begin
                    queue_pop_o = 'b1;
                    unique case (log_i.flags)
                        4'b1000: begin
                            next_state = BUSY;
                            counter_d  = NR_STALL_BRANCH;
                        end
                        4'b0100: begin
                            next_state = BUSY;
                            counter_d  = NR_STALL_JUMP;
                        end
                        4'b0010: begin
                            next_state = BUSY;
                            counter_d  = NR_STALL_CALL;
                        end
                        4'b0001: begin
                            next_state = BUSY;
                            counter_d  = NR_STALL_RETURN;
                        end
                        default: begin
                            next_state = IDLE;
                            counter_d  = 'b0;
                        end
                    endcase
                end
            end
            BUSY: begin
                next_state  = BUSY;
                queue_pop_o = 'b0;
                counter_d   = counter_q - 1;
                if (counter_q == 'b1) begin
                    next_state = IDLE;
                end
            end
            default: begin
                next_state  = IDLE;
                queue_pop_o = 'b0;
                counter_d   = 'b0;
            end
        endcase
    end

    always_ff @(posedge clk_i, negedge rst_ni) begin
        if (!rst_ni) begin
            curr_state <= next_state;
            counter_q  <= 'b0;
        end
        else begin
            curr_state <= next_state;
            counter_q  <= counter_d;
        end 
    end

endmodule
