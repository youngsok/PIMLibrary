#include <assert.h>
#include <gtest/gtest.h>
#include <stdio.h>
#include <stdlib.h>
#include <algorithm>
#include <iostream>
#include "fim_runtime_api.h"
#include "hip/hip_fp16.h"
#include "utility/fim_dump.hpp"

#define LENGTH (64 * 1024)

using namespace std;

int verifyResult(FimBo& host_input, FimBo& host_weight, FimBo& host_output, FimBo& device_output);

int fim_elt_add(void)
{
    int ret = 0;

    FimBo host_input = {.size = LENGTH * sizeof(FP16), .mem_type = MEM_TYPE_HOST};
    FimBo host_weight = {.size = LENGTH * sizeof(FP16), .mem_type = MEM_TYPE_HOST};
    FimBo host_output = {.size = LENGTH * sizeof(FP16), .mem_type = MEM_TYPE_HOST};
    FimBo device_output = {.size = LENGTH * sizeof(FP16), .mem_type = MEM_TYPE_DEVICE};
    FimBo fim_weight = {.size = 2 * LENGTH * sizeof(FP16), .mem_type = MEM_TYPE_FIM};

    /* __FIM_API__ call : Initialize FimRuntime */
    FimInitialize(RT_TYPE_HIP, FIM_FP16);

    /* __FIM_API__ call : Allocate host(CPU) memory */
    FimAllocMemory(&host_input);
    FimAllocMemory(&host_weight);
    FimAllocMemory(&host_output);
    /* __FIM_API__ call : Allocate device(GPU) memory */
    FimAllocMemory(&device_output);
    /* __FIM_API__ call : Allocate device(FIM) memory */
    FimAllocMemory(&fim_weight);

    /* Initialize the input, weight, output data */
    load_fp16_data("../test_vectors/load/elt_add_input0_64K_fp16.txt", (FP16*)host_input.data, host_input.size);
    load_fp16_data("../test_vectors/load/elt_add_input1_64K_fp16.txt", (FP16*)host_weight.data, host_weight.size);
    load_fp16_data("../test_vectors/load/elt_add_output_64K_fp16.txt", (FP16*)host_output.data, host_output.size);

    /* __FIM_API__ call : Preload weight data on FIM memory */
    FimConvertDataLayout(&fim_weight, &host_input, &host_weight, OP_ELT_ADD);

    dump_fp16_data("../test_vectors/dump/elt_add_preloaded_input_128K_fp16.txt", (FP16*)fim_weight.data,
                   fim_weight.size);

    /* __FIM_API__ call : Execute FIM kernel (ELT_ADD) */
    FimExecute(&device_output, &fim_weight, OP_ELT_ADD);

    /* __FIM_API__ call : Free device(FIM) memory */
    FimFreeMemory(&fim_weight);
    /* __FIM_API__ call : Free host(CPU) memory */
    FimFreeMemory(&host_input);
    FimFreeMemory(&host_weight);

    /* __FIM_API__ call : Deinitialize FimRuntime */
    FimDeinitialize();

    return ret;
}
TEST(IntegrationTest, FimEltAdd) { EXPECT_TRUE(fim_elt_add() == 0); }
