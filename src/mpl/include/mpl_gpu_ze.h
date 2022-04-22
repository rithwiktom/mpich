/*
 * Copyright (C) by Argonne National Laboratory
 *     See COPYRIGHT in top-level directory
 */

#ifndef MPL_GPU_ZE_H_INCLUDED
#define MPL_GPU_ZE_H_INCLUDED

#include "level_zero/ze_api.h"

typedef struct {
    ze_memory_allocation_properties_t prop;
    ze_device_handle_t device;
} ze_alloc_attr_t;

typedef ze_ipc_mem_handle_t MPL_gpu_ipc_mem_handle_t;
typedef ze_ipc_event_pool_handle_t MPL_gpu_ipc_event_pool_handle_t;
typedef ze_event_pool_handle_t MPL_gpu_event_pool_handle_t;
typedef ze_device_handle_t MPL_gpu_device_handle_t;
typedef ze_alloc_attr_t MPL_gpu_device_attr;

typedef struct MPL_cmdlist_pool {
    ze_command_list_handle_t cmdList;
    int dev;
    int engine;
    struct MPL_cmdlist_pool *next, *prev;
} MPL_cmdlist_pool_t;

typedef struct {
    ze_event_handle_t event;
    MPL_cmdlist_pool_t *cmdList;
} MPL_gpu_request;

#define MPL_GPU_DEVICE_INVALID NULL

#define MPL_GPU_ZE_COMPUTE_ENGINE_TYPE                 0
#define MPL_GPU_ZE_MAIN_COPY_ENGINE_TYPE               1
#define MPL_GPU_ZE_LINK_COPY_ENGINE_TYPE               2

/* ZE specific function */
int MPL_ze_init_device_fds(int *num_fds, int *device_fds);
void MPL_ze_set_fds(int num_fds, int *fds);
void MPL_ze_ipc_remove_cache_handle(void *dptr);
int MPL_ze_ipc_handle_create(const void *ptr, MPL_gpu_device_attr * ptr_attr, int local_dev_id,
                             int use_shared_fd, MPL_gpu_ipc_mem_handle_t * ipc_handle);
int MPL_ze_ipc_handle_map(MPL_gpu_ipc_mem_handle_t ipc_handle, int is_shared_handle, int dev_id,
                          int is_mmap, size_t size, void **ptr);
int MPL_ze_ipc_handle_mmap_host(MPL_gpu_ipc_mem_handle_t ipc_handle, int shared_handle, int dev_id,
                                size_t size, void **ptr);
int MPL_ze_mmap_device_pointer(void *dptr, MPL_gpu_device_attr * attr,
                               MPL_gpu_device_handle_t device, void **mmaped_ptr);
int MPL_ze_mmap_handle_unmap(void *ptr, int dev_id);
int MPL_ze_ipc_event_pool_handle_create(MPL_gpu_ipc_event_pool_handle_t * ipc_event_pool_handle);
int MPL_ze_ipc_event_pool_handle_size(void);
int MPL_ze_ipc_event_pool_handle_open(MPL_gpu_ipc_event_pool_handle_t gpu_ipc_event_pool_handle,
                                      MPL_gpu_event_pool_handle_t * gpu_event_pool_handle);
int MPL_ze_ipc_event_pool_handle_close(MPL_gpu_event_pool_handle_t gpu_event_pool_handle);

#endif /* ifndef MPL_GPU_ZE_H_INCLUDED */
