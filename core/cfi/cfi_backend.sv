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
    logic [7:0] transaction_counter; 
    logic en_transaction_count, rst_n_trans_count;
   
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
	            if(transaction_counter == 3'b111)
		            fsm_log_wrt_n_state = WRITE_DOORBELL_ADDR;
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
        unique case (fsm_log_wrt_c_state)        
            WRITE_ADDR: begin
	        en_transaction_count = 1'b1;   
                axi_req_o.aw.burst   = 2'b1;
		axi_req_o.aw.len  = 8'd7;
		axi_req_o.aw.size    = 3'd4;            
                axi_req_o.aw.addr    = 64'h0000000010404000; //-- insert base_addr of the mailbox
                axi_req_o.aw_valid   = 1'b1;       
            end
            
            WRITE_DATA: begin
                axi_req_o.w_valid    = 1'b1;
                axi_req_o.w          = log_i[transaction_counter << 5 +: 32];
                
		if(axi_rsp_i.w_ready)
		    en_transaction_count = 1'b1;
            end
	    
	    WRITE_DOORBELL_ADDR: begin
           	axi_req_o.aw.burst   = 2'b0;
		axi_req_o.aw.len  = 8'd1;
		axi_req_o.aw.size    = 3'd40;
 		axi_req_o.aw.addr    = 64'h0000000010404020;
                axi_req_o.aw_valid   = 1'b1;
		rst_n_trans_count    = 1'b0;
            end

            WRITE_DOORBELL_DATA: begin
		axi_req_o.w_valid    = 1'b1;
                axi_req_o.w          = 32'd1; //-- set doorbell register to 1
		rst_n_trans_count    = 1'b0;
		if(axi_rsp_i.w_ready)
	 	    queue_pop_o  = 1'b1;
            end
        endcase 
    end
endmodule