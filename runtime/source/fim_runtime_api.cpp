#include "fim_runtime_api.h"
#include <iostream>
#include "FimRuntime.h"
#include "hip/hip_runtime.h"

using namespace fim::runtime;

FimRuntime* fimRuntime = nullptr;

int FimInitialize(FimRuntimeType rtType, FimPrecision precision)
{
    std::cout << "fim::runtime::api Initialize call" << std::endl;

    int ret = 0;

    if (fimRuntime == nullptr) fimRuntime = new FimRuntime(rtType, precision);

    ret = fimRuntime->Initialize();

    return ret;
}

int FimDeinitialize(void)
{
    std::cout << "fim::runtime::api Deinitialize call" << std::endl;

    int ret = 0;

    if (fimRuntime != nullptr) {
        ret = fimRuntime->Deinitialize();
        delete fimRuntime;
        fimRuntime = nullptr;
    }

    return ret;
}

int FimAllocMemory(void** ptr, size_t size, FimMemType memType)
{
    std::cout << "fim::runtime::api FimAllocMemory call" << std::endl;

    int ret = 0;

    if (fimRuntime == nullptr) {
        return -1;
    }

    ret = fimRuntime->AllocMemory(ptr, size, memType);

    return ret;
}

int FimAllocMemory(FimBo* fimBo)
{
    int ret = 0;

    if (fimRuntime == nullptr) {
        return -1;
    }

    ret = fimRuntime->AllocMemory(fimBo);

    return ret;
}

int FimFreeMemory(void* ptr, FimMemType memType)
{
    std::cout << "fim::runtime::api FimFreeMemory call" << std::endl;

    int ret = 0;

    if (fimRuntime == nullptr) {
        return -1;
    }
    ret = fimRuntime->FreeMemory(ptr, memType);

    return ret;
}

int FimFreeMemory(FimBo* fimBo)
{
    int ret = 0;

    if (fimRuntime == nullptr) {
        return -1;
    }
    ret = fimRuntime->FreeMemory(fimBo);

    return ret;
}

int FimConvertDataLayout(void* dst, void* src, size_t size, FimOpType opType)
{
    std::cout << "fim::runtime::api FimPreprocessor call" << std::endl;

    int ret = 0;

    if (fimRuntime == nullptr) {
        return -1;
    }
    ret = fimRuntime->ConvertDataLayout(dst, src, size, opType);

    return ret;
}

int FimConvertDataLayout(FimBo* dst, FimBo* src, FimOpType opType)
{
    int ret = 0;

    if (fimRuntime == nullptr) {
        return -1;
    }
    ret = fimRuntime->ConvertDataLayout(dst, src, opType);

    return ret;
}

int FimCopyMemory(void* dst, void* src, size_t size, FimMemcpyType cpyType)
{
    std::cout << "fim::runtime::api FimAllocMemory call" << std::endl;

    int ret = 0;

    if (fimRuntime == nullptr) {
        return -1;
    }

    ret = fimRuntime->CopyMemory(dst, src, size, cpyType);

    return ret;
}

int FimCopyMemory(FimBo* dst, FimBo* src, FimMemcpyType cpyType)
{
    int ret = 0;

    if (fimRuntime == nullptr) {
        return -1;
    }

    ret = fimRuntime->CopyMemory(dst, src, cpyType);

    return ret;
}

int FimExecute(void* output, void* operand0, void* operand1, size_t size, FimOpType opType)
{
    std::cout << "fim::runtime::api FimExecute call" << std::endl;

    int ret = 0;

    if (fimRuntime == nullptr) {
        return -1;
    }

    ret = fimRuntime->Execute(output, operand0, operand1, size, opType);

    return ret;
}

int FimExecute(FimBo* output, FimBo* operand0, FimBo* operand1, FimOpType opType)
{
    int ret = 0;

    if (fimRuntime == nullptr) {
        return -1;
    }

    ret = fimRuntime->Execute(output, operand0, operand1, opType);

    return ret;
}
