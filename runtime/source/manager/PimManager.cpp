/*
 * Copyright (C) 2021 Samsung Electronics Co. LTD
 *
 * This software is a property of Samsung Electronics.
 * No part of this software, either material or conceptual may be copied or distributed, transmitted,
 * transcribed, stored in a retrieval system or translated into any human or computer language in any form by any means,
 * electronic, mechanical, manual or otherwise, or disclosed
 * to third parties without the express written permission of Samsung Electronics.
 */

#include "manager/PimManager.h"
#include <assert.h>
#include <stdlib.h>
#include <iostream>
#include "manager/PimMemoryManagerFactory.h"
#include "utility/pim_log.h"
#include "utility/pim_util.h"

std::map<uint32_t, HostInfo*> host_devices;

namespace pim
{
namespace runtime
{
namespace manager
{
PimManager::PimManager(PimRuntimeType rt_type, PimPrecision precision) : rt_type_(rt_type), precision_(precision)
{
    DLOG(INFO) << "[START] " << __FUNCTION__ << " called";
    pim_device_ = new PimDevice();
    PimMemoryManagerFactory memory_manager_factory{};
    pim_memory_manager_ = memory_manager_factory.getPimMemoryManager(pim_device_, rt_type_, precision_);
    pim_control_manager_ = new PimControlManager(pim_device_, rt_type_, precision_);
    pim_crf_generator_ = new PimCrfBinGen();
    DLOG(INFO) << "[END] " << __FUNCTION__ << " called";
}

PimManager::~PimManager(void)
{
    DLOG(INFO) << "[START] " << __FUNCTION__ << " called";
    delete pim_device_;
    delete pim_control_manager_;
    delete pim_memory_manager_;
    delete pim_crf_generator_;
    DLOG(INFO) << "[END] " << __FUNCTION__ << " called";
}

PimManager* PimManager::get_instance(PimRuntimeType rt_type, PimPrecision precision)
{
    DLOG(INFO) << "[START] " << __FUNCTION__ << " called";
    static PimManager* instance_ = new PimManager(rt_type, precision);

    DLOG(INFO) << "[END] " << __FUNCTION__ << " called";
    return instance_;
}

int PimManager::initialize(void)
{
    DLOG(INFO) << "[START] " << __FUNCTION__ << " called";
    int ret = 0;

    pim_control_manager_->initialize();
    pim_memory_manager_->initialize();

    DLOG(INFO) << "[END] " << __FUNCTION__ << " called";
    return ret;
}

int PimManager::deinitialize(void)
{
    DLOG(INFO) << "[START] " << __FUNCTION__ << " called";
    int ret = 0;

    pim_memory_manager_->deinitialize();
    pim_control_manager_->deinitialize();

    DLOG(INFO) << "[END] " << __FUNCTION__ << " called";
    return ret;
}

int PimManager::alloc_memory(void** ptr, size_t size, PimMemType mem_type)
{
    DLOG(INFO) << "[START] " << __FUNCTION__ << " called";
    int ret = 0;

    ret = pim_memory_manager_->alloc_memory(ptr, size, mem_type);

    DLOG(INFO) << "[END] " << __FUNCTION__ << " called";
    return ret;
}

int PimManager::alloc_memory(PimBo* pim_bo)
{
    DLOG(INFO) << "[START] " << __FUNCTION__ << " called";
    int ret = 0;

    ret = pim_memory_manager_->alloc_memory(pim_bo);

    DLOG(INFO) << "[END] " << __FUNCTION__ << " called";
    return ret;
}

int PimManager::free_memory(void* ptr, PimMemType mem_type)
{
    DLOG(INFO) << "[START] " << __FUNCTION__ << " called";
    int ret = 0;

    ret = pim_memory_manager_->free_memory(ptr, mem_type);

    DLOG(INFO) << "[END] " << __FUNCTION__ << " called";
    return ret;
}

int PimManager::free_memory(PimBo* pim_bo)
{
    DLOG(INFO) << "[START] " << __FUNCTION__ << " called";
    int ret = 0;

    ret = pim_memory_manager_->free_memory(pim_bo);

    DLOG(INFO) << "[END] " << __FUNCTION__ << " called";
    return ret;
}

int PimManager::copy_memory(void* dst, void* src, size_t size, PimMemCpyType cpy_type)
{
    DLOG(INFO) << "[START] " << __FUNCTION__ << " called";
    int ret = 0;

    ret = pim_memory_manager_->copy_memory(dst, src, size, cpy_type);

    DLOG(INFO) << "[END] " << __FUNCTION__ << " called";
    return ret;
}

int PimManager::copy_memory(PimBo* dst, PimBo* src, PimMemCpyType cpy_type)
{
    DLOG(INFO) << "[START] " << __FUNCTION__ << " called";
    int ret = 0;

    ret = pim_memory_manager_->copy_memory(dst, src, cpy_type);

    DLOG(INFO) << "[END] " << __FUNCTION__ << " called";
    return ret;
}

int PimManager::copy_memory_3d(const PimCopy3D* copy_params)
{
    DLOG(INFO) << "[START] " << __FUNCTION__ << " called";
    int ret = 0;

    ret = pim_memory_manager_->copy_memory_3d(copy_params);

    DLOG(INFO) << "[END] " << __FUNCTION__ << " called";
    return ret;
}

int PimManager::convert_data_layout(PimBo* dst, PimBo* src, PimOpType op_type)
{
    DLOG(INFO) << "[START] " << __FUNCTION__ << " called";
    int ret = 0;
    if (rt_type_ == RT_TYPE_HIP) {
        ret = pim_memory_manager_->convert_data_layout(dst, src, op_type);
    } else {
        DLOG(ERROR) << "not yet implemented";
    }
    DLOG(INFO) << "[END] " << __FUNCTION__ << " called";
    return ret;
}
} /* namespace manager */
} /* namespace runtime */
} /*namespace pim */
