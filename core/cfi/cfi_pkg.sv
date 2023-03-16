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
 * Package `cfi_pkg`
 *
 * This package has type definitions and utilities for the CFI stage of the CVA6 core.
 *
 * Author: Emanuele Parisi <emanuele.parisi@unibo.it> 
 */

package cfi_pkg;

    typedef struct packed {
        logic branch;
        logic jump;
        logic call;
        logic ret;
    } cfi_flags_t;

    typedef struct packed {
        cfi_flags_t             flags;
        logic [riscv::VLEN-1:0] addr_pc;
        logic [riscv::VLEN-1:0] addr_npc;
        logic [riscv::VLEN-1:0] addr_target;
    } cfi_log_t;
    
endpackage

