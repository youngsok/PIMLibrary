/*
 * Copyright (C) 2022 Samsung Electronics Co. LTD
 *
 * This software is a property of Samsung Electronics.
 * No part of this software, either material or conceptual may be copied or distributed, transmitted,
 * transcribed, stored in a retrieval system or translated into any human or computer language in any form by any means,
 * electronic, mechanical, manual or otherwise, or disclosed
 * to third parties without the express written permission of Samsung Electronics.
 * (Use of the Software is restricted to non-commercial, personal or academic, research purpose only)
 */

#ifndef _PIM_GEMM_KERNELS_PIMK_
#define _PIM_GEMM_KERNELS_PIMK_

#define PREPARE_KERNEL 1
#define COMPUTE_GEMM 1

static __constant uint8_t gemv_crf[32] = {
    0x00, 0x80, 0x10, 0x3b, 0x02, 0x38, 0x00, 0xe0, 0x00, 0x80, 0x18, 0x3b, 0x02, 0x38, 0x00, 0xe0,
    0x07, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xf0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
};

static __constant uint8_t gemv_hab_to_hab_pim[32] = {
    0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
};

static __constant uint8_t gemv_hab_pim_to_hab[32] = {
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
};

__kernel void pim_chwise_gemm_bias_relu_fp16(
    __global uint8_t* __restrict__ pim_ctr, __global uint8_t* __restrict__ input, __global uint8_t* __restrict__ weight,
    __global uint8_t* __restrict__ bias, __global uint8_t* __restrict__ output,
    __global uint8_t* __restrict__ pim_partial_sum, int iter_cnt, int inout_h, int in_w, int out_w, int n_in_tile,
    int n_out_tile, int is_bias, int is_relu, __global uint8_t* crf_binary, int crf_size
#ifdef EMULATOR
    ,
    __global PimMemTraceData* fmtd16, __global size_t* frd_size, int mt_width, __global PimMemTracer* emulator_trace
#endif
    )
{
#ifdef EMULATOR
    emulator_trace->g_fba = (uint64_t)pim_ctr;
    emulator_trace->g_fmtd16 = fmtd16;
    emulator_trace->g_ridx[get_group_id(0)] = 0;
    emulator_trace->m_width = mt_width;
    barrier(CLK_LOCAL_MEM_FENCE);
#endif

#ifdef PREPARE_KERNEL
    int grf_shift = 3;
    int num_ba = 4;
    int ba_shift = 2;
    int num_col = 32;
    int trans_shift = 5;
    int even_row, odd_row, col, loc;
    int ch = get_group_id(0);
    int w_idx = get_local_id(0) % 2;
    int gidx = get_local_id(0) >> 1;
    uint64_t offset = w_idx << 4;
    uint64_t addr;
    int chs_per_op = 64 / (4096 / out_w);
    input += ((get_group_id(0) / chs_per_op) * in_w << 1);
    __global uint8_t* __restrict__ t_pim_partial_sum = pim_partial_sum;
#endif

#if PARK_IN
    if (get_local_id(0) < 32) {
        addr = addr_gen_(ch, 0, (gidx >> ba_shift), gidx % num_ba, (1 << 13), 0);
        W_CMD(&pim_ctr[addr + offset]);
        B_CMD(1);
    }
#endif

#if CHANGE_SB_HAB
    if (get_local_id(0) < 2) {
        /* change SB mode to HAB mode */
        addr = addr_gen_(ch, 0, 2, 0, 0x27ff, 0x1f);
        W_CMD(&pim_ctr[addr + offset]);
        B_CMD(1);
        addr = addr_gen_(ch, 0, 2, 1, 0x27ff, 0x1f);
        W_CMD(&pim_ctr[addr + offset]);
        B_CMD(1);
        addr = addr_gen_(ch, 0, 0, 0, 0x27ff, 0x1f);
        W_CMD(&pim_ctr[addr + offset]);
        B_CMD(1);
        addr = addr_gen_(ch, 0, 0, 1, 0x27ff, 0x1f);
        W_CMD(&pim_ctr[addr + offset]);
        B_CMD(1);
    }
#endif

#if PROGRAM_CRF
    if (get_local_id(0) < (crf_size >> 4)) {
        addr = addr_gen_(get_group_id(0), 0, 0, 1, 0x3fff, 0x4 + gidx);
        W_CMD_R(&pim_ctr[addr + offset], crf_binary + (get_local_id(0) << 4));
        R_CMD(&pim_ctr[addr + offset]);
        B_CMD(1);
    }
#endif

#if COMPUTE_GEMM
    if (get_local_id(0) < 16) {
        for (int i = 0; i < iter_cnt; i++) {
            /* change HAB mode to HAB_PIM mode */
            for (int in_idx = 0; in_idx < inout_h; in_idx++) {
                addr = addr_gen_(ch, 0, 0, 0, 0x3fff, 0x0);
                W_CMD_R_C(&pim_ctr[addr + offset], gemv_hab_to_hab_pim + offset);
                R_CMD(&pim_ctr[addr + offset]);
                B_CMD(1);

                uint64_t i_offset = 0;
                int r_offset = 0;
                for (int i_idx = 0; i_idx < n_in_tile; i_idx += 2) {
                    /* write grf_A from WRIO */
                    uint64_t i_addr = (i_offset + ((i_idx << grf_shift) + gidx)) << trans_shift;
                    addr = addr_gen_(ch, 0, 0, 0, 0x3fff, 0x8 + gidx);
                    W_CMD_R(&pim_ctr[addr + offset], &input[i_addr + offset]);
                    R_CMD(&pim_ctr[addr + offset]);
                    B_CMD(1);

                    even_row = ((i_idx >> 1) + r_offset) << 1;
                    odd_row = even_row + 1;

                    addr = addr_gen_(ch, 0, 0, 0, even_row, gidx);
                    R_CMD(&weight[addr + offset]);

                    addr = addr_gen_(ch, 0, 0, 0, even_row, gidx + 8);
                    R_CMD(&weight[addr + offset]);

                    addr = addr_gen_(ch, 0, 0, 0, even_row, gidx + 16);
                    R_CMD(&weight[addr + offset]);

                    addr = addr_gen_(ch, 0, 0, 0, even_row, gidx + 24);
                    R_CMD(&weight[addr + offset]);

                    addr = addr_gen_(ch, 0, 0, 0, odd_row, gidx);
                    R_CMD(&weight[addr + offset]);

                    addr = addr_gen_(ch, 0, 0, 0, odd_row, gidx + 8);
                    R_CMD(&weight[addr + offset]);

                    addr = addr_gen_(ch, 0, 0, 0, odd_row, gidx + 16);
                    R_CMD(&weight[addr + offset]);

                    addr = addr_gen_(ch, 0, 0, 0, odd_row, gidx + 24);
                    R_CMD(&weight[addr + offset]);
                    B_CMD(1);
                }

                for (int i_idx = 1; i_idx < n_in_tile; i_idx += 2) {
                    uint64_t i_addr = (i_offset + ((i_idx << grf_shift) + gidx)) << trans_shift;
                    addr = addr_gen_(ch, 0, 0, 1, 0x3fff, 0x8 + gidx);
                    W_CMD_R(&pim_ctr[addr + offset], &input[i_addr + offset]);
                    R_CMD(&pim_ctr[addr + offset]);
                    B_CMD(1);

                    even_row = ((i_idx >> 1) + r_offset) << 1;
                    odd_row = even_row + 1;

                    addr = addr_gen_(ch, 0, 0, 1, even_row, gidx);
                    R_CMD(&weight[addr + offset]);

                    addr = addr_gen_(ch, 0, 0, 1, even_row, gidx + 8);
                    R_CMD(&weight[addr + offset]);

                    addr = addr_gen_(ch, 0, 0, 1, even_row, gidx + 16);
                    R_CMD(&weight[addr + offset]);

                    addr = addr_gen_(ch, 0, 0, 1, even_row, gidx + 24);
                    R_CMD(&weight[addr + offset]);

                    addr = addr_gen_(ch, 0, 0, 1, odd_row, gidx);
                    R_CMD(&weight[addr + offset]);

                    addr = addr_gen_(ch, 0, 0, 1, odd_row, gidx + 8);
                    R_CMD(&weight[addr + offset]);

                    addr = addr_gen_(ch, 0, 0, 1, odd_row, gidx + 16);
                    R_CMD(&weight[addr + offset]);

                    addr = addr_gen_(ch, 0, 0, 1, odd_row, gidx + 24);
                    R_CMD(&weight[addr + offset]);
                    B_CMD(1);
                }
                loc = gidx;
                col = loc % num_col;

                // pipeline delay
                // FIX : If alu is in operation, NOP should be added.
                addr = addr_gen_(ch, 0, 0, 1, 0, col);
                W_CMD(&t_pim_partial_sum[addr + offset]);
                W_CMD(&t_pim_partial_sum[addr + offset]);
                R_CMD(&t_pim_partial_sum[addr + offset]);
                B_CMD(1);

                addr = addr_gen_(ch, 0, 0, 0, 0x3fff, 0x0);
                W_CMD_R_C(&pim_ctr[addr + offset], gemv_hab_pim_to_hab + offset);
                R_CMD(&pim_ctr[addr + offset]);
                B_CMD(1);
            }
            input += (in_w * (4096 / out_w) * 2);
            weight += (in_w << 13);
            t_pim_partial_sum += (1 << 18);
        }
    }
#endif

#if CHANGE_HAB_SB
    if (get_local_id(0) < 4) {
        /* change HAB mode to SB mode */
        addr = addr_gen_(ch, 0, 0, gidx, 0x2fff, 0x1f);
        W_CMD(&pim_ctr[addr + offset]);
        R_CMD(&pim_ctr[addr + offset]);
        B_CMD(1);
    }
#endif

#if PARK_OUT
    if (get_local_id(0) < 32) {
        addr = addr_gen_(ch, 0, gidx >> ba_shift, gidx % num_ba, (1 << 13), 0);
        W_CMD(&pim_ctr[addr + offset]);
        B_CMD(1);
    }
#endif

#ifdef EMULATOR
    if (get_group_id(0) == 0 && get_local_id(0) == 0) {
        frd_size[0] = emulator_trace->g_ridx[0];
    }
#endif

#if REDUCE_SUM
    int bg = get_local_id(0) >> 4;
    int ba = (((get_local_id(0) >> 3) % 2) << 1) + 1;
    int t_idx = get_local_id(0);
    int out_offset = 0;
    half t_output = 0;
    t_pim_partial_sum = pim_partial_sum;

    for (int i = 0; i < iter_cnt; i++) {
        for (int in_idx = 0; in_idx < inout_h; in_idx++) {
            loc = gidx;
            col = get_local_id(0) % 8;
            addr = addr_gen_(ch, 0, bg, ba, 0, col);
            t_output = 0;
            for (int ti = 0; ti < 16; ti++) {
                t_output += ((half*)t_pim_partial_sum)[(addr >> 1) + ti];
            }
            out_offset = (get_group_id(0) << 6) + t_idx;
            if (is_bias) t_output += ((half*)bias)[out_offset];
            if (is_relu)
                if (t_output < (half)0.) t_output = (half)0.;
            ((half*)output)[out_offset] = t_output;
        }
        output += 8192;
        t_pim_partial_sum += (1 << 18);
    }
#endif
}

__kernel void pim_chwise_gemm_bias_relu_32tile_fp16(
    __global uint8_t* __restrict__ pim_ctr, __global uint8_t* __restrict__ input, __global uint8_t* __restrict__ weight,
    __global uint8_t* __restrict__ bias, __global uint8_t* __restrict__ output,
    __global uint8_t* __restrict__ pim_partial_sum, int iter_cnt, int inout_h, int in_w, int out_w, int n_in_tile,
    int n_out_tile, int is_bias, int is_relu, __global uint8_t* crf_binary, int crf_size
#ifdef EMULATOR
    ,
    __global PimMemTraceData* fmtd16, __global size_t* frd_size, int mt_width, __global PimMemTracer* emulator_trace
#endif
    )
{
#ifdef EMULATOR
    emulator_trace->g_fba = (uint64_t)pim_ctr;
    emulator_trace->g_fmtd16 = fmtd16;
    emulator_trace->g_ridx[get_group_id(0)] = 0;
    emulator_trace->m_width = mt_width;
    barrier(CLK_LOCAL_MEM_FENCE);
#endif

#ifdef PREPARE_KERNEL
    int grf_shift = 3;
    int num_ba = 4;
    int ba_shift = 2;
    int num_col = 32;
    int trans_shift = 5;
    int even_row, odd_row, col, loc;
    int ch = get_group_id(0);
    int w_idx = get_local_id(0) % 2;
    int gidx = get_local_id(0) >> 1;
    uint64_t offset = w_idx << 4;
    uint64_t addr;
    int chs_per_op = 64 / (4096 / out_w);
    input += ((get_group_id(0) / chs_per_op) * in_w << 1);
    __global uint8_t* __restrict__ t_pim_partial_sum = pim_partial_sum;
#endif

#if PARK_IN
    if (get_local_id(0) < 32) {
        addr = addr_gen_(ch, 0, (gidx >> ba_shift), gidx % num_ba, (1 << 13), 0);
        W_CMD(&pim_ctr[addr + offset]);
        B_CMD(1);
    }
#endif

#if CHANGE_SB_HAB
    if (get_local_id(0) < 2) {
        /* change SB mode to HAB mode */
        addr = addr_gen_(ch, 0, 2, 0, 0x27ff, 0x1f);
        W_CMD(&pim_ctr[addr + offset]);
        B_CMD(1);
        addr = addr_gen_(ch, 0, 2, 1, 0x27ff, 0x1f);
        W_CMD(&pim_ctr[addr + offset]);
        B_CMD(1);
        addr = addr_gen_(ch, 0, 0, 0, 0x27ff, 0x1f);
        W_CMD(&pim_ctr[addr + offset]);
        B_CMD(1);
        addr = addr_gen_(ch, 0, 0, 1, 0x27ff, 0x1f);
        W_CMD(&pim_ctr[addr + offset]);
        B_CMD(1);
    }
#endif

#if PROGRAM_CRF
    if (get_local_id(0) < (crf_size >> 4)) {
        addr = addr_gen_(get_group_id(0), 0, 0, 1, 0x3fff, 0x4 + gidx);
        W_CMD_R(&pim_ctr[addr + offset], crf_binary + (get_local_id(0) << 4));
        R_CMD(&pim_ctr[addr + offset]);
        B_CMD(1);
    }
#endif

#if COMPUTE_GEMM
    if (get_local_id(0) < 16) {
        for (int i = 0; i < iter_cnt; i++) {
            /* change HAB mode to HAB_PIM mode */
            for (int in_idx = 0; in_idx < inout_h; in_idx++) {
                addr = addr_gen_(ch, 0, 0, 0, 0x3fff, 0x0);
                W_CMD_R_C(&pim_ctr[addr + offset], gemv_hab_to_hab_pim + offset);
                R_CMD(&pim_ctr[addr + offset]);
                B_CMD(1);

                uint64_t i_offset = 0;
                int r_offset = 0;
                for (int i = 0, i_idx = 0; i < 16; i++, i_idx += 2) {
                    /* write grf_A from WRIO */
                    uint64_t i_addr = (i_offset + ((i_idx << grf_shift) + gidx)) << trans_shift;
                    addr = addr_gen_(ch, 0, 0, 0, 0x3fff, 0x8 + gidx);
                    W_CMD_R(&pim_ctr[addr + offset], &input[i_addr + offset]);
                    R_CMD(&pim_ctr[addr + offset]);
                    B_CMD(1);

                    even_row = ((i_idx >> 1) + r_offset) << 1;
                    odd_row = even_row + 1;

                    addr = addr_gen_(ch, 0, 0, 0, even_row, gidx);
                    R_CMD(&weight[addr + offset]);

                    addr = addr_gen_(ch, 0, 0, 0, even_row, gidx + 8);
                    R_CMD(&weight[addr + offset]);

                    addr = addr_gen_(ch, 0, 0, 0, even_row, gidx + 16);
                    R_CMD(&weight[addr + offset]);

                    addr = addr_gen_(ch, 0, 0, 0, even_row, gidx + 24);
                    R_CMD(&weight[addr + offset]);

                    addr = addr_gen_(ch, 0, 0, 0, odd_row, gidx);
                    R_CMD(&weight[addr + offset]);

                    addr = addr_gen_(ch, 0, 0, 0, odd_row, gidx + 8);
                    R_CMD(&weight[addr + offset]);

                    addr = addr_gen_(ch, 0, 0, 0, odd_row, gidx + 16);
                    R_CMD(&weight[addr + offset]);

                    addr = addr_gen_(ch, 0, 0, 0, odd_row, gidx + 24);
                    R_CMD(&weight[addr + offset]);
                    B_CMD(1);
                }

                for (int i = 0, i_idx = 1; i < 16; i++, i_idx += 2) {
                    uint64_t i_addr = (i_offset + ((i_idx << grf_shift) + gidx)) << trans_shift;
                    addr = addr_gen_(ch, 0, 0, 1, 0x3fff, 0x8 + gidx);
                    W_CMD_R(&pim_ctr[addr + offset], &input[i_addr + offset]);
                    R_CMD(&pim_ctr[addr + offset]);
                    B_CMD(1);

                    even_row = ((i_idx >> 1) + r_offset) << 1;
                    odd_row = even_row + 1;

                    addr = addr_gen_(ch, 0, 0, 1, even_row, gidx);
                    R_CMD(&weight[addr + offset]);

                    addr = addr_gen_(ch, 0, 0, 1, even_row, gidx + 8);
                    R_CMD(&weight[addr + offset]);

                    addr = addr_gen_(ch, 0, 0, 1, even_row, gidx + 16);
                    R_CMD(&weight[addr + offset]);

                    addr = addr_gen_(ch, 0, 0, 1, even_row, gidx + 24);
                    R_CMD(&weight[addr + offset]);

                    addr = addr_gen_(ch, 0, 0, 1, odd_row, gidx);
                    R_CMD(&weight[addr + offset]);

                    addr = addr_gen_(ch, 0, 0, 1, odd_row, gidx + 8);
                    R_CMD(&weight[addr + offset]);

                    addr = addr_gen_(ch, 0, 0, 1, odd_row, gidx + 16);
                    R_CMD(&weight[addr + offset]);

                    addr = addr_gen_(ch, 0, 0, 1, odd_row, gidx + 24);
                    R_CMD(&weight[addr + offset]);
                    B_CMD(1);
                }
                loc = gidx;
                col = loc % num_col;

                // pipeline delay
                // FIX : If alu is in operation, NOP should be added.
                addr = addr_gen_(ch, 0, 0, 1, 0, col);
                W_CMD(&t_pim_partial_sum[addr + offset]);
                W_CMD(&t_pim_partial_sum[addr + offset]);
                R_CMD(&t_pim_partial_sum[addr + offset]);
                B_CMD(1);

                addr = addr_gen_(ch, 0, 0, 0, 0x3fff, 0x0);
                W_CMD_R_C(&pim_ctr[addr + offset], gemv_hab_pim_to_hab + offset);
                R_CMD(&pim_ctr[addr + offset]);
                B_CMD(1);
            }
            input += (in_w * (4096 / out_w) * 2);
            weight += (in_w << 13);
            t_pim_partial_sum += (1 << 18);
        }
    }
#endif

#if CHANGE_HAB_SB
    if (get_local_id(0) < 4) {
        /* change HAB mode to SB mode */
        addr = addr_gen_(ch, 0, 0, gidx, 0x2fff, 0x1f);
        W_CMD(&pim_ctr[addr + offset]);
        R_CMD(&pim_ctr[addr + offset]);
        B_CMD(1);
    }
#endif

#if PARK_OUT
    if (get_local_id(0) < 32) {
        addr = addr_gen_(ch, 0, gidx >> ba_shift, gidx % num_ba, (1 << 13), 0);
        W_CMD(&pim_ctr[addr + offset]);
        B_CMD(1);
    }
#endif

#ifdef EMULATOR
    if (get_group_id(0) == 0 && get_local_id(0) == 0) {
        frd_size[0] = emulator_trace->g_ridx[0];
    }
#endif

#if REDUCE_SUM
    int bg = get_local_id(0) >> 4;
    int ba = (((get_local_id(0) >> 3) % 2) << 1) + 1;
    int t_idx = get_local_id(0);
    int out_offset = 0;
    half t_output = 0;
    t_pim_partial_sum = pim_partial_sum;

    for (int i = 0; i < iter_cnt; i++) {
        for (int in_idx = 0; in_idx < inout_h; in_idx++) {
            loc = gidx;
            col = get_local_id(0) % 8;
            addr = addr_gen_(ch, 0, bg, ba, 0, col);
            t_output = 0;
            for (int ti = 0; ti < 16; ti++) {
                t_output += ((half*)t_pim_partial_sum)[(addr >> 1) + ti];
            }
            out_offset = (get_group_id(0) << 6) + t_idx;
            if (is_bias) t_output += ((half*)bias)[out_offset];
            if (is_relu)
                if (t_output < (half)0.) t_output = (half)0.;
            ((half*)output)[out_offset] = t_output;
        }
        output += 8192;
        t_pim_partial_sum += (1 << 18);
    }
#endif
}

__kernel void pim_aligned_gemm_bias_relu_fp16(
    __global uint8_t* __restrict__ pim_ctr, __global uint8_t* __restrict__ input, __global uint8_t* __restrict__ weight,
    __global uint8_t* __restrict__ bias, __global uint8_t* __restrict__ output,
    __global uint8_t* __restrict__ pim_partial_sum, int iter_cnt, int inout_h, int in_w, int out_w, int n_in_tile,
    int n_out_tile, int is_bias, int is_relu, __global uint8_t* crf_binary, int crf_size
#ifdef EMULATOR
    ,
    __global PimMemTraceData* fmtd16, __global size_t* frd_size, int mt_width, __global PimMemTracer* emulator_trace
#endif
    )
{
#ifdef EMULATOR
    emulator_trace->g_fba = (uint64_t)pim_ctr;
    emulator_trace->g_fmtd16 = fmtd16;
    emulator_trace->g_ridx[get_group_id(0)] = 0;
    emulator_trace->m_width = mt_width;
    barrier(CLK_LOCAL_MEM_FENCE);
#endif

#ifdef PREPARE_KERNEL
    int grf_shift = 3;
    int num_ba = 4;
    int ba_shift = 2;
    int num_col = 32;
    int col_shift = 5;
    int trans_shift = 5;
    int even_row, odd_row, row, col, loc;
    int ch = get_group_id(0);
    int w_idx = get_local_id(0) % 2;
    int gidx = get_local_id(0) >> 1;
    uint64_t offset = w_idx << 4;
    uint64_t addr;
    int gemv_cnt = 0;
#endif

#if PARK_IN
    if (get_local_id(0) < 32) {
        addr = addr_gen_(ch, 0, (gidx >> ba_shift), gidx % num_ba, (1 << 13), 0);
        W_CMD(&pim_ctr[addr + offset]);
        B_CMD(1);
    }
#endif

#if CHANGE_SB_HAB
    if (get_local_id(0) < 2) {
        /* change SB mode to HAB mode */
        addr = addr_gen_(ch, 0, 2, 0, 0x27ff, 0x1f);
        W_CMD(&pim_ctr[addr + offset]);
        B_CMD(1);
        addr = addr_gen_(ch, 0, 2, 1, 0x27ff, 0x1f);
        W_CMD(&pim_ctr[addr + offset]);
        B_CMD(1);
        addr = addr_gen_(ch, 0, 0, 0, 0x27ff, 0x1f);
        W_CMD(&pim_ctr[addr + offset]);
        B_CMD(1);
        addr = addr_gen_(ch, 0, 0, 1, 0x27ff, 0x1f);
        W_CMD(&pim_ctr[addr + offset]);
        B_CMD(1);
    }
#endif

#if PROGRAM_CRF
    if (get_local_id(0) < (crf_size >> 4)) {
        addr = addr_gen_(get_group_id(0), 0, 0, 1, 0x3fff, 0x4 + gidx);
        W_CMD_R(&pim_ctr[addr + offset], crf_binary + (get_local_id(0) << 4));
        R_CMD(&pim_ctr[addr + offset]);
        B_CMD(1);
    }
#endif

#if COMPUTE_GEMM
    if (get_local_id(0) < 16) {
        for (int i = 0; i < iter_cnt; i++) {
            /* change HAB mode to HAB_PIM mode */
            for (int in_idx = 0; in_idx < inout_h; in_idx++) {
                for (int o_idx = 0; o_idx < n_out_tile; o_idx++) {
                    addr = addr_gen_(ch, 0, 0, 0, 0x3fff, 0x0);
                    W_CMD_R_C(&pim_ctr[addr + offset], gemv_hab_to_hab_pim + offset);
                    R_CMD(&pim_ctr[addr + offset]);
                    B_CMD(1);

                    uint64_t i_offset = gemv_cnt * (n_in_tile << grf_shift);
                    int r_offset = (o_idx * n_in_tile) >> 1;

                    for (int i_idx = 0; i_idx < n_in_tile; i_idx += 2) {
                        /* write grf_A from WRIO */
                        uint64_t i_addr = (i_offset + ((i_idx << grf_shift) + gidx)) << trans_shift;
                        addr = addr_gen_(ch, 0, 0, 0, 0x3fff, 0x8 + gidx);
                        W_CMD_R(&pim_ctr[addr + offset], &input[i_addr + offset]);
                        R_CMD(&pim_ctr[addr + offset]);
                        B_CMD(1);

                        even_row = ((i_idx >> 1) + r_offset) << 1;
                        odd_row = even_row + 1;

                        addr = addr_gen_(ch, 0, 0, 0, even_row, gidx);
                        R_CMD(&weight[addr + offset]);

                        addr = addr_gen_(ch, 0, 0, 0, even_row, gidx + 8);
                        R_CMD(&weight[addr + offset]);

                        addr = addr_gen_(ch, 0, 0, 0, even_row, gidx + 16);
                        R_CMD(&weight[addr + offset]);

                        addr = addr_gen_(ch, 0, 0, 0, even_row, gidx + 24);
                        R_CMD(&weight[addr + offset]);

                        addr = addr_gen_(ch, 0, 0, 0, odd_row, gidx);
                        R_CMD(&weight[addr + offset]);

                        addr = addr_gen_(ch, 0, 0, 0, odd_row, gidx + 8);
                        R_CMD(&weight[addr + offset]);

                        addr = addr_gen_(ch, 0, 0, 0, odd_row, gidx + 16);
                        R_CMD(&weight[addr + offset]);

                        addr = addr_gen_(ch, 0, 0, 0, odd_row, gidx + 24);
                        R_CMD(&weight[addr + offset]);
                        B_CMD(1);
                    }

                    for (int i_idx = 1; i_idx < n_in_tile; i_idx += 2) {
                        uint64_t i_addr = (i_offset + ((i_idx << grf_shift) + gidx)) << trans_shift;
                        addr = addr_gen_(ch, 0, 0, 1, 0x3fff, 0x8 + gidx);
                        W_CMD_R(&pim_ctr[addr + offset], &input[i_addr + offset]);
                        R_CMD(&pim_ctr[addr + offset]);
                        B_CMD(1);

                        even_row = ((i_idx >> 1) + r_offset) << 1;
                        odd_row = even_row + 1;

                        addr = addr_gen_(ch, 0, 0, 1, even_row, gidx);
                        R_CMD(&weight[addr + offset]);

                        addr = addr_gen_(ch, 0, 0, 1, even_row, gidx + 8);
                        R_CMD(&weight[addr + offset]);

                        addr = addr_gen_(ch, 0, 0, 1, even_row, gidx + 16);
                        R_CMD(&weight[addr + offset]);

                        addr = addr_gen_(ch, 0, 0, 1, even_row, gidx + 24);
                        R_CMD(&weight[addr + offset]);

                        addr = addr_gen_(ch, 0, 0, 1, odd_row, gidx);
                        R_CMD(&weight[addr + offset]);

                        addr = addr_gen_(ch, 0, 0, 1, odd_row, gidx + 8);
                        R_CMD(&weight[addr + offset]);

                        addr = addr_gen_(ch, 0, 0, 1, odd_row, gidx + 16);
                        R_CMD(&weight[addr + offset]);

                        addr = addr_gen_(ch, 0, 0, 1, odd_row, gidx + 24);
                        R_CMD(&weight[addr + offset]);
                        B_CMD(1);
                    }
                    loc = (gemv_cnt * n_out_tile << grf_shift) + (o_idx << grf_shift) + gidx;
                    row = loc >> col_shift;
                    col = loc % num_col;

                    // pipeline delay
                    // FIX : If alu is in operation, NOP should be added.
                    addr = addr_gen_(ch, 0, 0, 1, row, col);
                    W_CMD(&pim_partial_sum[addr + offset]);
                    W_CMD(&pim_partial_sum[addr + offset]);
                    R_CMD(&pim_partial_sum[addr + offset]);
                    B_CMD(1);

                    addr = addr_gen_(ch, 0, 0, 0, 0x3fff, 0x0);
                    W_CMD_R_C(&pim_ctr[addr + offset], gemv_hab_pim_to_hab + offset);
                    R_CMD(&pim_ctr[addr + offset]);
                    B_CMD(1);
                }
                gemv_cnt++;
            }
            weight += (in_w * out_w << 1);
        }
    }
#endif

#if CHANGE_HAB_SB
    if (get_local_id(0) < 4) {
        /* change HAB mode to SB mode */
        addr = addr_gen_(ch, 0, 0, gidx, 0x2fff, 0x1f);
        W_CMD(&pim_ctr[addr + offset]);
        R_CMD(&pim_ctr[addr + offset]);
        B_CMD(1);
    }
#endif

#if PARK_OUT
    if (get_local_id(0) < 32) {
        addr = addr_gen_(ch, 0, gidx >> ba_shift, gidx % num_ba, (1 << 13), 0);
        W_CMD(&pim_ctr[addr + offset]);
        B_CMD(1);
    }
#endif

#ifdef EMULATOR
    if (get_group_id(0) == 0 && get_local_id(0) == 0) {
        frd_size[0] = emulator_trace->g_ridx[0];
    }
#endif

#if REDUCE_SUM
    int bg = get_local_id(0) >> 4;
    int ba = (((get_local_id(0) >> 3) % 2) << 1) + 1;
    int t_idx = (get_group_id(0) << 6) + get_local_id(0);
    int out_idx;
    int out_offset;
    int li;
    half t_output;

    gemv_cnt = 0;

    for (int i = 0; i < iter_cnt; i++) {
        for (int in_idx = 0; in_idx < inout_h; in_idx++) {
            for (int oi = 0; oi < n_out_tile; oi++) {
                /* int out_per_tile = 4096; */
                /* out_idx = oi * out_per_tile + t_idx; */
                out_idx = (oi << 12) + t_idx;
                if (out_idx < out_w) {
                    li = gemv_cnt * n_out_tile + oi;
                    row = li >> 2;
                    col = get_local_id(0) % 8 + ((li % 4) << 3);
                    addr = addr_gen_(ch, 0, bg, ba, row, col);
                    t_output = 0;
                    for (int ti = 0; ti < 16; ti++) {
                        t_output += ((half*)pim_partial_sum)[(addr >> 1) + ti];
                    }
                    out_offset = gemv_cnt * out_w + out_idx;
                    if (is_bias) t_output += ((half*)bias)[out_offset];
                    if (is_relu)
                        if (t_output < (half)0.) t_output = (half)0.;
                    ((half*)output)[out_offset] = t_output;
                }
            }
            gemv_cnt++;
        }
    }
#endif
}

__kernel void pim_aligned_gemm_bias_relu_8tile_fp16(
    __global uint8_t* __restrict__ pim_ctr, __global uint8_t* __restrict__ input, __global uint8_t* __restrict__ weight,
    __global uint8_t* __restrict__ bias, __global uint8_t* __restrict__ output,
    __global uint8_t* __restrict__ pim_partial_sum, int iter_cnt, int inout_h, int in_w, int out_w, int n_in_tile,
    int n_out_tile, int is_bias, int is_relu, __global uint8_t* crf_binary, int crf_size
#ifdef EMULATOR
    ,
    __global PimMemTraceData* fmtd16, __global size_t* frd_size, int mt_width, __global PimMemTracer* emulator_trace
#endif
    )
{
#ifdef EMULATOR
    emulator_trace->g_fba = (uint64_t)pim_ctr;
    emulator_trace->g_fmtd16 = fmtd16;
    emulator_trace->g_ridx[get_group_id(0)] = 0;
    emulator_trace->m_width = mt_width;
    barrier(CLK_LOCAL_MEM_FENCE);
#endif

#ifdef PREPARE_KERNEL
    int grf_shift = 3;
    int num_ba = 4;
    int ba_shift = 2;
    int num_col = 32;
    int col_shift = 5;
    int trans_shift = 5;
    int even_row, odd_row, row, col, loc;
    int ch = get_group_id(0);
    int w_idx = get_local_id(0) % 2;
    int gidx = get_local_id(0) >> 1;
    uint64_t offset = w_idx << 4;
    uint64_t addr;
    int gemv_cnt = 0;
#endif

#if PARK_IN
    if (get_local_id(0) < 32) {
        addr = addr_gen_(ch, 0, (gidx >> ba_shift), gidx % num_ba, (1 << 13), 0);
        W_CMD(&pim_ctr[addr + offset]);
        B_CMD(1);
    }
#endif

#if CHANGE_SB_HAB
    if (get_local_id(0) < 2) {
        /* change SB mode to HAB mode */
        addr = addr_gen_(ch, 0, 2, 0, 0x27ff, 0x1f);
        W_CMD(&pim_ctr[addr + offset]);
        B_CMD(1);
        addr = addr_gen_(ch, 0, 2, 1, 0x27ff, 0x1f);
        W_CMD(&pim_ctr[addr + offset]);
        B_CMD(1);
        addr = addr_gen_(ch, 0, 0, 0, 0x27ff, 0x1f);
        W_CMD(&pim_ctr[addr + offset]);
        B_CMD(1);
        addr = addr_gen_(ch, 0, 0, 1, 0x27ff, 0x1f);
        W_CMD(&pim_ctr[addr + offset]);
        B_CMD(1);
    }
#endif

#if PROGRAM_CRF
    if (get_local_id(0) < (crf_size >> 4)) {
        addr = addr_gen_(get_group_id(0), 0, 0, 1, 0x3fff, 0x4 + gidx);
        W_CMD_R(&pim_ctr[addr + offset], crf_binary + (get_local_id(0) << 4));
        R_CMD(&pim_ctr[addr + offset]);
        B_CMD(1);
    }
#endif

#if COMPUTE_GEMM
    if (get_local_id(0) < 16) {
        for (int i = 0; i < iter_cnt; i++) {
            /* change HAB mode to HAB_PIM mode */
            for (int in_idx = 0; in_idx < inout_h; in_idx++) {
                for (int o_idx = 0; o_idx < n_out_tile; o_idx++) {
                    addr = addr_gen_(ch, 0, 0, 0, 0x3fff, 0x0);
                    W_CMD_R_C(&pim_ctr[addr + offset], gemv_hab_to_hab_pim + offset);
                    R_CMD(&pim_ctr[addr + offset]);
                    B_CMD(1);

                    uint64_t i_offset = gemv_cnt * (n_in_tile << grf_shift);
                    int r_offset = (o_idx * n_in_tile) >> 1;

#pragma unroll
                    for (int i = 0, i_idx = 0; i < 4; i++, i_idx += 2) {
                        /* write grf_A from WRIO */
                        uint64_t i_addr = (i_offset + ((i_idx << grf_shift) + gidx)) << trans_shift;
                        addr = addr_gen_(ch, 0, 0, 0, 0x3fff, 0x8 + gidx);
                        W_CMD_R(&pim_ctr[addr + offset], &input[i_addr + offset]);
                        R_CMD(&pim_ctr[addr + offset]);
                        B_CMD(1);

                        even_row = ((i_idx >> 1) + r_offset) << 1;
                        odd_row = even_row + 1;

                        addr = addr_gen_(ch, 0, 0, 0, even_row, gidx);
                        R_CMD(&weight[addr + offset]);

                        addr = addr_gen_(ch, 0, 0, 0, even_row, gidx + 8);
                        R_CMD(&weight[addr + offset]);

                        addr = addr_gen_(ch, 0, 0, 0, even_row, gidx + 16);
                        R_CMD(&weight[addr + offset]);

                        addr = addr_gen_(ch, 0, 0, 0, even_row, gidx + 24);
                        R_CMD(&weight[addr + offset]);

                        addr = addr_gen_(ch, 0, 0, 0, odd_row, gidx);
                        R_CMD(&weight[addr + offset]);

                        addr = addr_gen_(ch, 0, 0, 0, odd_row, gidx + 8);
                        R_CMD(&weight[addr + offset]);

                        addr = addr_gen_(ch, 0, 0, 0, odd_row, gidx + 16);
                        R_CMD(&weight[addr + offset]);

                        addr = addr_gen_(ch, 0, 0, 0, odd_row, gidx + 24);
                        R_CMD(&weight[addr + offset]);
                        B_CMD(1);
                    }

#pragma unroll
                    for (int i = 0, i_idx = 1; i < 4; i++, i_idx += 2) {
                        uint64_t i_addr = (i_offset + ((i_idx << grf_shift) + gidx)) << trans_shift;
                        addr = addr_gen_(ch, 0, 0, 1, 0x3fff, 0x8 + gidx);
                        W_CMD_R(&pim_ctr[addr + offset], &input[i_addr + offset]);
                        R_CMD(&pim_ctr[addr + offset]);
                        B_CMD(1);

                        even_row = ((i_idx >> 1) + r_offset) << 1;
                        odd_row = even_row + 1;

                        addr = addr_gen_(ch, 0, 0, 1, even_row, gidx);
                        R_CMD(&weight[addr + offset]);

                        addr = addr_gen_(ch, 0, 0, 1, even_row, gidx + 8);
                        R_CMD(&weight[addr + offset]);

                        addr = addr_gen_(ch, 0, 0, 1, even_row, gidx + 16);
                        R_CMD(&weight[addr + offset]);

                        addr = addr_gen_(ch, 0, 0, 1, even_row, gidx + 24);
                        R_CMD(&weight[addr + offset]);

                        addr = addr_gen_(ch, 0, 0, 1, odd_row, gidx);
                        R_CMD(&weight[addr + offset]);

                        addr = addr_gen_(ch, 0, 0, 1, odd_row, gidx + 8);
                        R_CMD(&weight[addr + offset]);

                        addr = addr_gen_(ch, 0, 0, 1, odd_row, gidx + 16);
                        R_CMD(&weight[addr + offset]);

                        addr = addr_gen_(ch, 0, 0, 1, odd_row, gidx + 24);
                        R_CMD(&weight[addr + offset]);
                        B_CMD(1);
                    }
                    loc = (gemv_cnt * n_out_tile << grf_shift) + (o_idx << grf_shift) + gidx;
                    row = loc >> col_shift;
                    col = loc % num_col;

                    // pipeline delay
                    // FIX : If alu is in operation, NOP should be added.
                    addr = addr_gen_(ch, 0, 0, 1, row, col);
                    W_CMD(&pim_partial_sum[addr + offset]);
                    W_CMD(&pim_partial_sum[addr + offset]);
                    R_CMD(&pim_partial_sum[addr + offset]);
                    B_CMD(1);

                    addr = addr_gen_(ch, 0, 0, 0, 0x3fff, 0x0);
                    W_CMD_R_C(&pim_ctr[addr + offset], gemv_hab_pim_to_hab + offset);
                    R_CMD(&pim_ctr[addr + offset]);
                    B_CMD(1);
                }
                gemv_cnt++;
            }
            weight += (in_w * out_w << 1);
        }
    }
#endif

#if CHANGE_HAB_SB
    if (get_local_id(0) < 4) {
        /* change HAB mode to SB mode */
        addr = addr_gen_(ch, 0, 0, gidx, 0x2fff, 0x1f);
        W_CMD(&pim_ctr[addr + offset]);
        R_CMD(&pim_ctr[addr + offset]);
        B_CMD(1);
    }
#endif

#if PARK_OUT
    if (get_local_id(0) < 32) {
        addr = addr_gen_(ch, 0, gidx >> ba_shift, gidx % num_ba, (1 << 13), 0);
        W_CMD(&pim_ctr[addr + offset]);
        B_CMD(1);
    }
#endif

#ifdef EMULATOR
    if (get_group_id(0) == 0 && get_local_id(0) == 0) {
        frd_size[0] = emulator_trace->g_ridx[0];
    }
#endif

#if REDUCE_SUM
    int bg = get_local_id(0) >> 4;
    int ba = (((get_local_id(0) >> 3) % 2) << 1) + 1;
    int t_idx = (get_group_id(0) << 6) + get_local_id(0);
    int out_idx;
    int out_offset;
    int li;
    half t_output;

    gemv_cnt = 0;

    for (int i = 0; i < iter_cnt; i++) {
        for (int in_idx = 0; in_idx < inout_h; in_idx++) {
            for (int oi = 0; oi < n_out_tile; oi++) {
                /* int out_per_tile = 4096; */
                /* out_idx = oi * out_per_tile + t_idx; */
                out_idx = (oi << 12) + t_idx;
                if (out_idx < out_w) {
                    li = gemv_cnt * n_out_tile + oi;
                    row = li >> 2;
                    col = get_local_id(0) % 8 + ((li % 4) << 3);
                    addr = addr_gen_(ch, 0, bg, ba, row, col);
                    t_output = 0;
                    for (int ti = 0; ti < 16; ti++) {
                        t_output += ((half*)pim_partial_sum)[(addr >> 1) + ti];
                    }
                    out_offset = gemv_cnt * out_w + out_idx;
                    if (is_bias) t_output += ((half*)bias)[out_offset];
                    if (is_relu)
                        if (t_output < (half)0.) t_output = (half)0.;
                    ((half*)output)[out_offset] = t_output;
                }
            }
            gemv_cnt++;
        }
    }
#endif
}

#endif /* _PIM_GEMV_KERNELS_PIMK_ */
