// Copyright 2018 ETH Zurich and University of Bologna.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.
//
// Author: Florian Zaruba, ETH Zurich
// Date: 08.02.2018
// Description: Ariane Instruction Fetch Frontend

import ariane_pkg::*;

typedef struct packed {
    logic        valid;
    logic [63:0] pc;             // update at PC
    logic [63:0] target_address;
    logic        is_lower_16;
    logic        clear;
} btb_update_t;

typedef struct packed {
    logic        valid;
    logic [63:0] target_address;
    logic        is_lower_16;
} btb_prediction_t;

typedef struct packed {
    logic        valid;
    logic [63:0] ra;
} ras_t;

typedef struct packed {
    logic        valid;
    logic [63:0] pc;          // update at PC
    logic        mispredict;
    logic        taken;
} bht_update_t;

typedef struct packed {
    logic       valid;
    logic       taken;
    logic       strongly_taken;
    logic [1:0] saturation_counter;
} bht_prediction_t;

module frontend #(
    parameter int unsigned BTB_ENTRIES = 8,
    parameter int unsigned BHT_ENTRIES = 32,
    parameter int unsigned RAS_DEPTH   = 2
)(
    input  logic               clk_i,              // Clock
    input  logic               rst_ni,             // Asynchronous reset active low
    input  logic               flush_i,            // flush request for PCGEN
    input  logic               flush_bp_i,         // flush branch prediction
    input  logic               i_fence_i,          // instruction fence in
    input  logic               flush_itlb_i,       // flush itlb
    // global input
    input  logic [63:0]        boot_addr_i,
    input  logic               fetch_enable_i,     // start fetching instructions
    // Set a new PC
    // mispredict
    input  branchpredict_t     resolved_branch_i,  // from controller signaling a branch_predict -> update BTB
    // from commit, when flushing the whole pipeline
    input  logic [63:0]        pc_commit_i,        // PC of instruction in commit stage
    // CSR input
    input  logic [63:0]        epc_i,              // exception PC which we need to return to
    input  logic               eret_i,             // return from exception
    input  logic [63:0]        trap_vector_base_i, // base of trap vector
    input  logic               ex_valid_i,         // exception is valid - from commit
    // Debug
    input  logic [63:0]        debug_pc_i,         // PC from debug stage
    input  logic               debug_set_pc_i,     // Set PC request from debug
    // Instruction Fetch
    AXI_BUS.Master             axi,
    output logic               l1_icache_miss_o,    // instruction cache missed
    //
    // instruction output port -> to processor back-end
    output fetch_entry_t       fetch_entry_o,       // fetch entry containing all relevant data for the ID stage
    output logic               fetch_entry_valid_o, // instruction in IF is valid
    input  logic               fetch_ack_i          // ID acknowledged this instruction
);
    // Registers
    logic [31:0] icache_data_d,  icache_data_q;
    logic        icache_valid_d, icache_valid_q;
    logic        set_pc_d,       set_pc_q;

    // BHT, BTB and RAS prediction
    bht_prediction_t bht_prediction;
    btb_prediction_t btb_prediction;
    ras_t ras_predict;

    // icache controll signals
    logic icache_req, icache_kill_req, icache_ready;

    logic ras_push, ras_pop;
    logic [63:0] ras_update;

    // instruction fetch is ready
    logic          if_ready;
    logic [63:0]   npc_d, npc_q; // next PC
    // RVI ctrl flow prediction
    logic          rvi_return, rvi_call, rvi_branch, rvi_jalr, rvi_jump;
    logic [63:0]   rvi_imm;



    bht_update_t     bht_update_i;
    logic [63:0]     vpc_i;
    btb_update_t     btb_update_i;
    logic [11:0]     index_i;
    logic [43:0]     tag_i;

    logic [31:0]     instr;

    logic            is_rvc;

    logic            rvc_branch;
    logic            rvc_jump;
    logic            rvc_jr;
    logic            rvc_return;
    logic            rvc_jalr;
    logic            rvc_call;
    logic [63:0]     rvc_imm;

    // control frontend
    always_comb begin : frontend_ctrl

        if_ready = 1'b0;
        icache_req = 1'b0;
        icache_kill_req = 1'b0;

    end

    // -------------------
    // Next PC
    // -------------------
    // next PC (NPC) can come from (in order of precedence):
    // 0. Default assignment
    // 1. Branch Predict taken
    // 2. Control flow change request
    // 3. Return from environment call
    // 4. Exception/Interrupt
    // 5. Pipeline Flush because of CSR side effects
    // 6. Debug
    // Mis-predict handling is a little bit different
    // select PC a.k.a PC Gen

    // virtual address of current fetch
    logic [63:0] fetch_vaddr;
    logic take_rvi_cf; // take the control flow change

    always_comb begin : npc_select
        automatic logic [63:0] fetch_address;
        ras_pop     = 1'b0;
        ras_push    = 1'b0;
        ras_update  = '0;
        take_rvi_cf = 1'b0;

        fetch_address    = npc_q;
        set_pc_d         = set_pc_q;
        // keep stable by default
        npc_d            = fetch_address;
        // -------------------------------
        // 0. Default assignment
        // -------------------------------
        if (if_ready && fetch_enable_i)
            npc_d = {fetch_address[63:2], 2'b0}  + 64'h4;

        // -------------------------------
        // 1. Branch Prediction
        // -------------------------------
        // is it a return and the RAS contains a valid prediction? **speculative**
        if (if_ready && rvi_return && ras_predict.valid) begin
            fetch_address = ras_predict.ra;
            ras_pop = 1'b1;
        end

        if (if_ready && rvi_call) begin
            ras_push = 1'b1;
            ras_update = fetch_address; // not sure here
        end

        // Branch Prediction - **speculative**
        if (if_ready && rvi_branch) begin
            // dynamic prediction valid?
            if (bht_prediction.valid) begin
                if (bht_prediction.taken || bht_prediction.strongly_taken)
                    take_rvi_cf = 1'b1;
            // default to static prediction
            end else begin
                // set if immediate is negative
                if (rvi_imm[63]) begin
                    take_rvi_cf = 1'b1;
                end
            end
        end

        // unconditional jump
        if (if_ready && rvi_jump) begin
            take_rvi_cf = 1'b1;
        end

        // to take this jump we need a valid prediction target
        if (if_ready && rvi_jalr && btb_prediction.valid) begin
            fetch_address = btb_prediction.target_address;
        end

        if (take_rvi_cf) begin
            fetch_address = npc_q + rvi_imm;
        end
        // -------------------------------
        // 3. Return from environment call
        // -------------------------------
        if (eret_i) begin
            npc_d                  = epc_i;
        end


        // -------------------------------
        // 4. Exception/Interrupt
        // -------------------------------
        if (ex_valid_i) begin
            npc_d                  = trap_vector_base_i;
            branch_predict_o.valid = 1'b0;
            set_pc_d               = 1'b1;
        end

        // -----------------------------------------------
        // 5. Pipeline Flush because of CSR side effects
        // -----------------------------------------------
        // On a pipeline flush start fetching from the next address
        // of the instruction in the commit stage
        if (flush_i) begin
            // we came here from a flush request of a CSR instruction,
            // as CSR instructions do not exist in a compressed form
            // we can unconditionally do PC + 4 here
            npc_d    = pc_commit_i + 64'h4;
            set_pc_d = 1'b1;
            branch_predict_o.valid = 1'b0;
        end

        // -------------------------------
        // 6. Debug
        // -------------------------------
        if (debug_set_pc_i) begin
            npc_d = debug_pc_i;
            branch_predict_o.valid = 1'b0;
            set_pc_d = 1'b1;
        end

        fetch_vaddr = fetch_address;
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (~rst_ni) begin
            npc_q             <= boot_addr_i;
            icache_data_q     <= '0;
            icache_valid_q    <= 1'b0;
            set_pc_q          <= 1'b0;
        end else begin
            npc_q             <= npc_d;
            icache_data_q     <= icache_data_q;
            icache_valid_q    <= icache_valid_d;
            set_pc_q          <= set_pc_d;
        end
    end

    ras #(
        .DEPTH  ( RAS_DEPTH   )
    ) i_ras (
        .push_i ( ras_push    ),
        .pop_i  ( ras_pop     ),
        .data_i ( ras_update  ),
        .data_o ( ras_predict ),
        .*
    );

    btb #(
        .NR_ENTRIES       ( BTB_ENTRIES      )
    ) i_btb (
        .flush_i          ( flush_bp_i       ),
        .vpc_i            ( fetch_vaddr      ),
        .btb_update_i     ( btb_update_i     ),
        .btb_prediction_o ( btb_prediction   ),
        .*
    );

    bht #(
        .NR_ENTRIES       ( BHT_ENTRIES      )
    ) i_bht (
        .flush_i          ( flush_bp_i       ),
        .vpc_i            ( fetch_vaddr      ),
        .bht_update_i     ( bht_update_i     ),
        .bht_prediction_o ( bht_prediction   ),
        .*
    );

    icache #(
        .SET_ASSOCIATIVITY ( 4          )
    ) i_icache (
        .clk_i      ( clk_i             ),
        .rst_ni     ( rst_ni            ),
        .flush_i    ( 1'b0              ),
        .index_i    ( fetch_vaddr[11:0] ),
        .tag_i      (                   ),
        .data_o     ( icache_data_d     ),
        .req_i      ( icache_req        ),
        .kill_req_i ( icache_kill_req   ),
        .ready_o    ( icache_ready      ),
        .valid_o    ( icache_valid_d    ),
        .axi        ( axi               ),
        .miss_o     ( l1_icache_miss_o  )
    );

    instr_scan i_instr_scan (
        .instr_i      ( instr        ),
        .is_rvc_o     ( is_rvc       ),
        .rvi_return_o ( rvi_return   ),
        .rvi_call_o   ( rvi_call     ),
        .rvc_branch_o ( rvc_branch   ),
        .rvc_jump_o   ( rvc_jump     ),
        .rvc_jr_o     ( rvc_jr       ),
        .rvc_return_o ( rvc_return   ),
        .rvc_jalr_o   ( rvc_jalr     ),
        .rvc_call_o   ( rvc_call     ),
        .rvi_imm_o    ( rvi_imm      ),
        .rvc_imm_o    ( rvc_imm      ),
        .rvi_branch_o ( rvi_branch   ),
        .rvi_jalr_o   ( rvi_jalr     ),
        .rvi_jump_o   ( rvi_jump     )
    );

endmodule

// ------------------------------
// Instruction Scanner
// ------------------------------
module instr_scan (
    input  logic [31:0] instr_i,        // expect aligned instruction, compressed or not
    output logic        is_rvc_o,
    output logic        rvi_return_o,
    output logic        rvi_call_o,
    output logic        rvc_branch_o,
    output logic        rvc_jump_o,
    output logic        rvc_jr_o,
    output logic        rvc_return_o,
    output logic        rvc_jalr_o,
    output logic        rvc_call_o,
    output logic [63:0] rvi_imm_o,
    output logic [63:0] rvc_imm_o,
    output logic        rvi_branch_o,
    output logic        rvi_jalr_o,
    output logic        rvi_jump_o
);
    assign is_rvc_o     = (instr_i[1:0] != 2'b00);
    // check that rs1 is either x1 or x5 and that rs1 is not x1 or x5, TODO: check the fact about bit 7
    assign rvi_return_o = rvi_jalr_o & ~instr_i[7] & ~instr_i[19] & ~instr_i[18] & instr_i[17] & ~instr_i[15];
    assign rvi_call_o   = (rvi_jalr_o | rvi_jump_o) & instr_i[7]; // TODO: check that this captures calls
    assign rvc_branch_o = (instr_i[15:13] == OPCODE_C_BEQZ) | (instr_i[15:13] == OPCODE_C_BNEZ);
    // opcode JAL
    assign rvc_jump_o   = (instr_i[15:13] == OPCODE_C_J);
    assign rvc_jr_o     = (instr_i[15:12] == 4'b1000) & (instr_i[6:2] == 5'b00000);
    // check that rs1 is x1 or x5
    assign rvc_return_o = rvc_jr_o & ~instr_i[11] & ~instr_i[10] & ~instr_i[8] & ~instr_i[7];
    assign rvc_jalr_o   = (instr_i[15:12] == 4'b1001) & (instr_i[6:2] == 5'b00000);
    assign rvc_call_o   = rvc_jalr_o;  // TODO: check that this captures calls

    // differentiates between JAL and BRANCH opcode, JALR comes from BHT
    assign rvi_imm_o    = (instr_i[3]) ? uj_imm(instr_i) : sb_imm(instr_i);
    // // differentiates between JAL and BRANCH opcode, JALR comes from BHT
    assign rvc_imm_o    = (instr_i[14]) ? {{56{instr_i[12]}}, instr_i[6:5], instr_i[2], instr_i[11:10], instr_i[4:3], 1'b0}
                                       : {{53{instr_i[12]}}, instr_i[8], instr_i[10:9], instr_i[6], instr_i[7], instr_i[2], instr_i[11], instr_i[5:3], 1'b0};

    assign rvi_branch_o = (instr_i[6:0] == OPCODE_BRANCH) ? 1'b1 : 1'b0;
    assign rvi_jalr_o   = (instr_i[6:0] == OPCODE_JALR)   ? 1'b1 : 1'b0;
    assign rvi_jump_o   = (instr_i[6:0] == OPCODE_JAL)    ? 1'b1 : 1'b0;
endmodule

// ------------------------------
// Branch Prediction
// ------------------------------

// branch target buffer
module btb #(
    parameter int NR_ENTRIES = 8
)(
    input  logic               clk_i,           // Clock
    input  logic               rst_ni,          // Asynchronous reset active low
    input  logic               flush_i,         // flush the btb

    input  logic [63:0]        vpc_i,           // virtual PC from IF stage
    input  btb_update_t        btb_update_i,    // update btb with this information
    output btb_prediction_t    btb_prediction_o // prediction from btb
);
    // number of bits which are not used for indexing
    localparam OFFSET = 1; // we are using compressed instructions so do use the lower 2 bits for prediction
    localparam ANTIALIAS_BITS = 8;
    // number of bits we should use for prediction
    localparam PREDICTION_BITS = $clog2(NR_ENTRIES) + OFFSET;
    // typedef for all branch target entries
    // we may want to try to put a tag field that fills the rest of the PC in-order to mitigate aliasing effects
    btb_prediction_t btb_d [NR_ENTRIES-1:0], btb_q [NR_ENTRIES-1:0];
    logic [$clog2(NR_ENTRIES)-1:0]          index, update_pc;

    assign index     = vpc_i[PREDICTION_BITS - 1:OFFSET];
    assign update_pc = btb_update_i.pc[PREDICTION_BITS - 1:OFFSET];

    // output matching prediction
    assign btb_prediction_o = btb_q[index];

    // -------------------------
    // Update Branch Prediction
    // -------------------------
    // update on a mis-predict
    always_comb begin : update_branch_predict
        btb_d = btb_q;

        if (btb_update_i.valid) begin
            btb_d[update_pc].valid = 1'b1;
            // the target address is simply updated
            btb_d[update_pc].target_address = btb_update_i.target_address;
            // as is the information whether this was a compressed branch
            btb_d[update_pc].is_lower_16    = btb_update_i.is_lower_16;
            // check if we should invalidate this entry, this happens in case we predicted a branch
            // where actually none-is (aliasing)
            if (btb_update_i.clear) begin
                btb_d[update_pc].valid = 1'b0;
            end
        end
    end

    // sequential process
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (~rst_ni) begin
            // Bias the branches to be taken upon first arrival
            for (int i = 0; i < NR_ENTRIES; i++)
                btb_q[i] <= '{default: 0};
        end else begin
            // evict all entries
            if (flush_i) begin
                for (int i = 0; i < NR_ENTRIES; i++) begin
                    btb_q[i].valid <=  1'b0;
                end
            end else begin
                btb_q <=  btb_d;
            end
        end
    end
endmodule

// return address stack
module ras #(
    parameter int unsigned DEPTH = 2
)(
    input  logic        clk_i,
    input  logic        rst_ni,
    input  logic        push_i,
    input  logic        pop_i,
    input  logic [63:0] data_i,
    output ras_t        data_o
);

    ras_t [DEPTH-1:0] stack_d, stack_q;

    assign data_o = stack_q[0];

    always_comb begin
        stack_d = stack_q;

        // push on the stack
        if (push_i) begin
            stack_d[0].ra = data_i;
            // mark the new return address as valid
            stack_d[0].valid = 1'b1;
            stack_d[DEPTH-1:1] = stack_q[DEPTH-2:0];
        end

        if (pop_i) begin
            stack_d[DEPTH-2:0] = stack_q[DEPTH-1:1];
            // we popped the value so invalidate the end of the stack
            stack_d[DEPTH-1].valid = 1'b0;
            stack_d[DEPTH-1].ra = 'b0;
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (~rst_ni) begin
            stack_q <= '0;
        end else begin
            stack_q <= stack_d;
        end
    end
endmodule

// branch history table - 2 bit saturation counter
module bht #(
    parameter int unsigned NR_ENTRIES = 64
)(
    input  logic            clk_i,
    input  logic            rst_ni,
    input  logic            flush_i,
    input  logic [63:0]     vpc_i,
    input  bht_update_t     bht_update_i,
    output bht_prediction_t bht_prediction_o
);
    localparam OFFSET = 2; // we are using compressed instructions so do not use the lower 2 bits for prediction
    localparam ANTIALIAS_BITS = 8;
    // number of bits we should use for prediction
    localparam PREDICTION_BITS = $clog2(NR_ENTRIES) + OFFSET;

    bht_prediction_t                        bht_d[NR_ENTRIES-1:0], bht_q[NR_ENTRIES-1:0];
    logic [$clog2(NR_ENTRIES)-1:0]          index, update_pc;
    logic [1:0]     saturation_counter;

    assign index     = vpc_i[PREDICTION_BITS - 1:OFFSET];
    assign update_pc = bht_update_i.pc[PREDICTION_BITS - 1:OFFSET];
    // prediction assignment
    assign bht_prediction_o = bht_q[index];

    always_comb begin : update_bht
        bht_d = bht_q;
        saturation_counter = bht_q[update_pc].saturation_counter;

        if (bht_update_i.valid) begin
            bht_d[update_pc].valid = 1'b1;

            if (saturation_counter == 2'b11) begin
                // we can safely decrease it
                if (~bht_update_i.taken)
                    bht_d[update_pc].saturation_counter = saturation_counter - 1;
            // then check if it saturated in the negative regime e.g.: branch not taken
            end else if (saturation_counter == 2'b00) begin
                // we can safely increase it
                if (bht_update_i.taken)
                    bht_d[update_pc].saturation_counter = saturation_counter + 1;
            end else begin // otherwise we are not in any boundaries and can decrease or increase it
                if (bht_update_i.taken)
                    bht_d[update_pc].saturation_counter = saturation_counter + 1;
                else
                    bht_d[update_pc].saturation_counter = saturation_counter - 1;
            end
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (~rst_ni) begin
            for (int unsigned i = 0; i < NR_ENTRIES; i++)
                bht_q[i] <= '0;
        end else begin
            // evict all entries
            if (flush_i) begin
                for (int i = 0; i < NR_ENTRIES; i++) begin
                    bht_q[i].valid <=  1'b0;
                end
            end else begin
                bht_q <= bht_d;
            end
        end
    end
endmodule
