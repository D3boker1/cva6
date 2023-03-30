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

module cfi_backend import ariane_pkg::*, cfi_pkg::*; 
(
    input  logic       		clk_i,
    input  logic       		rst_ni,

//-- Input from log queue
    input  cfi_log_t   		log_i,
    input  logic       		queue_empty_i,
//-- log queue control 
    output logic       		queue_pop_o,
    output exception_t 		cfi_fault_o,

//-- AXI Control 
    output ariane_axi::req_t    axi_req_o,
    input  ariane_axi::resp_t   axi_rsp_i
);

//------------------------------------------------------------- Mailbox Write --------------------------------------------------------------//
    enum logic [2:0] {IDLE, WRITE_ADDR, WRITE_DATA, WRITE_DOORBELL_ADDR, WRITE_DOORBELL_DATA} fsm_log_wrt_c_state, fsm_log_wrt_n_state; 
    logic [8:0]   transaction_counter; 
    //logic [255:0] log_i_padded;
    logic [319:0] log_i_padded;
    logic en_transaction_count, rst_n_trans_count;

    logic [10:0] base_data_addr; 
    localparam N_TRANS = 9;
    
    assign log_i_padded   = {64'd1, 60'd0, log_i};
    assign base_data_addr = transaction_counter << 5;
    
//-- State memory
    always_ff @(posedge clk_i, negedge rst_ni)
        if(!rst_ni) 
            fsm_log_wrt_c_state <= IDLE;
        else
            fsm_log_wrt_c_state <= fsm_log_wrt_n_state;

    always_ff @(posedge clk_i, negedge rst_ni)
        if(!rst_ni) 
            transaction_counter <= '0;
	
	else if(!rst_n_trans_count) 
            transaction_counter <= '0;	
	
        else if(en_transaction_count)
            transaction_counter <= transaction_counter + 1;
	    
//-- next state computation
    always_comb begin
    	fsm_log_wrt_n_state  = IDLE;
    	unique case (fsm_log_wrt_c_state)
        IDLE: 
            if (queue_empty_i) 
                fsm_log_wrt_n_state = IDLE;
   	        else
	            fsm_log_wrt_n_state = WRITE_ADDR;
    
        WRITE_ADDR: 
        	if(axi_rsp_i.aw_ready)
                fsm_log_wrt_n_state = WRITE_DATA;
            else
                fsm_log_wrt_n_state = WRITE_ADDR;                 

        WRITE_DATA:
	        if(transaction_counter == N_TRANS && axi_rsp_i.w_ready)
		        fsm_log_wrt_n_state = IDLE;
            else if(axi_rsp_i.w_ready)
                fsm_log_wrt_n_state = WRITE_ADDR;
            else
		        fsm_log_wrt_n_state = WRITE_DATA;     

	    WRITE_DOORBELL_ADDR:
	        if(axi_rsp_i.aw_ready)
 	            fsm_log_wrt_n_state = WRITE_DOORBELL_DATA;
            else
		        fsm_log_wrt_n_state = WRITE_DOORBELL_ADDR;
 
	    WRITE_DOORBELL_DATA:
            if(axi_rsp_i.w_ready)
	            fsm_log_wrt_n_state = IDLE;
            else
		        fsm_log_wrt_n_state = WRITE_DOORBELL_DATA;    
        endcase 
    end

//-- fsm outputs computation
    always_comb begin
        en_transaction_count = 1'b0;
	    axi_req_o            = '0;
	    rst_n_trans_count    = 1'b1;
	    queue_pop_o          = 1'b0;

        //-- AXI default values
        axi_req_o.w_valid    = 1'b0;
        axi_req_o.w.data     = 64'd0;
        axi_req_o.w.strb     = 8'd0;
        axi_req_o.w.last     = 1'b0;
        axi_req_o.w.user     = 1'b0;

        axi_req_o.aw.burst   = 2'b0;
        axi_req_o.aw.id      = 5'h0;
        axi_req_o.aw.size    =   '0;
        axi_req_o.aw.len     = 8'd0;
        axi_req_o.aw.lock    = 1'b0;
        axi_req_o.aw.prot    =   '0;
        axi_req_o.aw.qos     =   '0;
        axi_req_o.aw.qos     =   '0;
        axi_req_o.aw.region  =   '0;
        axi_req_o.aw.user    =   '0;

        axi_req_o.ar.burst   = 2'b0;
        axi_req_o.ar.id      = 5'h0;
        axi_req_o.ar.size    =   '0;
        axi_req_o.ar.lock    = 1'b0;
        axi_req_o.ar.prot    =   '0;
        axi_req_o.ar.qos     =   '0;
        axi_req_o.ar.qos     =   '0;
        axi_req_o.ar.region  =   '0;
        axi_req_o.ar.user    =   '0;
        
        axi_req_o.ar_valid   = 1'b0;
        axi_req_o.r_ready    = 1'b1;
        axi_req_o.b_ready    = 1'b1;
    
        unique case (fsm_log_wrt_c_state)        
            WRITE_ADDR: begin
	            //en_transaction_count = 1'b1;
                axi_req_o.aw.id      = 5'd3;   
                axi_req_o.aw.burst   = 2'b1;
		        axi_req_o.aw.len     = 8'd0;
		        axi_req_o.aw.size    = 3'b010;            
                axi_req_o.aw.addr    = 64'h0000000010404000 + (transaction_counter << 2); //-- insert base_addr of the mailbox
                //axi_req_o.aw.addr    = 64'h0000000010404018;
                axi_req_o.aw_valid   = 1'b1;       
            end
            
            WRITE_DATA: begin
                axi_req_o.w_valid    = 1'b1;
                axi_req_o.w.strb     = 8'hFF;
                axi_req_o.w.data     = {'0, log_i_padded[transaction_counter << 5 +: 32]};
                axi_req_o.w.last     = 1'b1; 
                //axi_req_o.w.data     = log_i_padded[transaction_counter << 6 +: 64];
                if(transaction_counter == N_TRANS && axi_rsp_i.w_ready)
                    rst_n_trans_count= 1'b0; 
		        else if(axi_rsp_i.w_ready)
		            en_transaction_count = 1'b1;
            end
	    
	        WRITE_DOORBELL_ADDR: begin
               	axi_req_o.aw.burst   = 2'b1;
		        //axi_req_o.aw.len     = 8'd1;
		        axi_req_o.aw.size    = 3'b001;
 		        axi_req_o.aw.addr    = 64'h0000000010404020;
                axi_req_o.aw_valid   = 1'b1;
		        rst_n_trans_count    = 1'b0;
            end
    
            WRITE_DOORBELL_DATA: begin
		        axi_req_o.w_valid    = 1'b1;
                axi_req_o.w.data     = 64'd1; //-- set doorbell register to 1
                axi_req_o.w.last     = 1'b1;
		        rst_n_trans_count    = 1'b0;
                axi_req_o.w.strb     = 8'hFF;
		        if(axi_rsp_i.w_ready)
	 	            queue_pop_o  = 1'b1;
            end
        endcase 
    end
endmodule