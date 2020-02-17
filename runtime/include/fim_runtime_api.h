#ifndef _FIM_RUNTIME_API_H_
#define _FIM_RUNTIME_API_H_

#include "fim_data_types.h"

__FIM_API__ int FimInitialize(FimRuntimeType rt_type = RT_TYPE_HIP, FimPrecision = FIM_FP16);
__FIM_API__ int FimDeinitialize(void);

__FIM_API__ int FimAllocMemory(void** ptr, size_t size, FimMemType mem_type = MEM_TYPE_FIM);
__FIM_API__ int FimAllocMemory(FimBo* fim_bo);

__FIM_API__ int FimFreeMemory(void* ptr, FimMemType mem_type = MEM_TYPE_FIM);
__FIM_API__ int FimFreeMemory(FimBo* fim_bo);

__FIM_API__ int FimConvertDataLayout(void* dst, void* src, size_t size, FimOpType op_type);
__FIM_API__ int FimConvertDataLayout(FimBo* dst, FimBo* src, FimOpType op_type);
__FIM_API__ int FimConvertDataLayout(FimBo* dst, FimBo* src0, FimBo* src1, FimOpType op_type);

__FIM_API__ int FimCopyMemory(void* dst, void* src, size_t size, FimMemCpyType cpy_type);
__FIM_API__ int FimCopyMemory(FimBo* dst, FimBo* src, FimMemCpyType cpy_type);

__FIM_API__ int FimExecute(void* output, void* operand0, void* operand1, size_t size, FimOpType op_type);
__FIM_API__ int FimExecute(FimBo* output, FimBo* operand0, FimBo* operand1, FimOpType op_type);
__FIM_API__ int FimExecute(FimBo* output, FimBo* fim_data, FimOpType op_type);

#endif /* _FIM_RUNTIME_API_H_ */
