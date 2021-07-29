/*
 * Copyright (C) by Argonne National Laboratory
 *     See COPYRIGHT in top-level directory
 */

#include <mpidimpl.h>
#include "ofi_impl.h"
MPIDI_OFI_global_t MPIDI_OFI_global;

MPIDI_OFI_huge_recv_t *MPIDI_unexp_huge_recv_head = NULL;
MPIDI_OFI_huge_recv_t *MPIDI_unexp_huge_recv_tail = NULL;
MPIDI_OFI_huge_recv_list_t *MPIDI_posted_huge_recv_head = NULL;
MPIDI_OFI_huge_recv_list_t *MPIDI_posted_huge_recv_tail = NULL;

unsigned long long PVAR_COUNTER_nic_sent_bytes_count[MPIDI_OFI_MAX_NICS] ATTRIBUTE((unused));
unsigned long long PVAR_COUNTER_nic_recvd_bytes_count[MPIDI_OFI_MAX_NICS] ATTRIBUTE((unused));
unsigned long long PVAR_COUNTER_striped_nic_sent_bytes_count[MPIDI_OFI_MAX_NICS]
ATTRIBUTE((unused));
unsigned long long PVAR_COUNTER_striped_nic_recvd_bytes_count[MPIDI_OFI_MAX_NICS]
ATTRIBUTE((unused));
unsigned long long PVAR_COUNTER_rma_pref_phy_nic_put_bytes_count[MPIDI_OFI_MAX_NICS]
ATTRIBUTE((unused));
unsigned long long PVAR_COUNTER_rma_pref_phy_nic_get_bytes_count[MPIDI_OFI_MAX_NICS]
ATTRIBUTE((unused));

MPIDI_OFI_capabilities_t MPIDI_OFI_caps_list[MPIDI_OFI_NUM_SETS] =
/* Initialize a runtime version of all of the capability sets defined in
 * ofi_capability_sets.h so we can refer to it if we want to preload a
 * capability set at runtime */
{
    {   /* default required capability */
     .enable_av_table = MPIDI_OFI_ENABLE_AV_TABLE_DEFAULT,
     .enable_scalable_endpoints = MPIDI_OFI_ENABLE_SCALABLE_ENDPOINTS_DEFAULT,
     .enable_shared_contexts = MPIDI_OFI_ENABLE_SHARED_CONTEXTS_DEFAULT,
     .enable_mr_virt_address = MPIDI_OFI_ENABLE_MR_VIRT_ADDRESS_DEFAULT,
     .enable_mr_allocated = MPIDI_OFI_ENABLE_MR_ALLOCATED_DEFAULT,
     .enable_mr_prov_key = MPIDI_OFI_ENABLE_MR_PROV_KEY_DEFAULT,
     .enable_tagged = MPIDI_OFI_ENABLE_TAGGED_DEFAULT,
     .enable_am = MPIDI_OFI_ENABLE_AM_DEFAULT,
     .enable_rma = MPIDI_OFI_ENABLE_RMA_DEFAULT,
     .enable_atomics = MPIDI_OFI_ENABLE_ATOMICS_DEFAULT,
     .enable_data_auto_progress = MPIDI_OFI_ENABLE_DATA_AUTO_PROGRESS_DEFAULT,
     .enable_control_auto_progress = MPIDI_OFI_ENABLE_CONTROL_AUTO_PROGRESS_DEFAULT,
     .enable_pt2pt_nopack = MPIDI_OFI_ENABLE_PT2PT_NOPACK_DEFAULT,
     .enable_triggered = MPIDI_OFI_ENABLE_TRIGGERED_DEFAULT,
     .num_am_buffers = MPIDI_OFI_NUM_AM_BUFFERS_DEFAULT,
     .max_endpoints = MPIDI_OFI_MAX_ENDPOINTS_DEFAULT,
     .max_endpoints_bits = MPIDI_OFI_MAX_ENDPOINTS_BITS_DEFAULT,
     .fetch_atomic_iovecs = MPIDI_OFI_FETCH_ATOMIC_IOVECS_DEFAULT,
     .context_bits = MPIDI_OFI_CONTEXT_BITS_DEFAULT,
     .source_bits = MPIDI_OFI_SOURCE_BITS_DEFAULT,
     .tag_bits = MPIDI_OFI_TAG_BITS_DEFAULT,
     .major_version = MPIDI_OFI_MAJOR_VERSION_DEFAULT,
     .minor_version = MPIDI_OFI_MINOR_VERSION_DEFAULT}
    ,
    {   /* minimal required capability */
     .enable_av_table = MPIDI_OFI_ENABLE_AV_TABLE_MINIMAL,
     .enable_scalable_endpoints = MPIDI_OFI_ENABLE_SCALABLE_ENDPOINTS_MINIMAL,
     .enable_shared_contexts = MPIDI_OFI_ENABLE_SHARED_CONTEXTS_MINIMAL,
     .enable_mr_virt_address = MPIDI_OFI_ENABLE_MR_VIRT_ADDRESS_MINIMAL,
     .enable_mr_allocated = MPIDI_OFI_ENABLE_MR_ALLOCATED_MINIMAL,
     .enable_mr_prov_key = MPIDI_OFI_ENABLE_MR_PROV_KEY_MINIMAL,
     .enable_tagged = MPIDI_OFI_ENABLE_TAGGED_MINIMAL,
     .enable_am = MPIDI_OFI_ENABLE_AM_MINIMAL,
     .enable_rma = MPIDI_OFI_ENABLE_RMA_MINIMAL,
     .enable_atomics = MPIDI_OFI_ENABLE_ATOMICS_MINIMAL,
     .enable_data_auto_progress = MPIDI_OFI_ENABLE_DATA_AUTO_PROGRESS_MINIMAL,
     .enable_control_auto_progress = MPIDI_OFI_ENABLE_CONTROL_AUTO_PROGRESS_MINIMAL,
     .enable_pt2pt_nopack = MPIDI_OFI_ENABLE_PT2PT_NOPACK_MINIMAL,
     .enable_triggered = MPIDI_OFI_ENABLE_TRIGGERED_MINIMAL,
     .num_am_buffers = MPIDI_OFI_NUM_AM_BUFFERS_MINIMAL,
     .max_endpoints = MPIDI_OFI_MAX_ENDPOINTS_MINIMAL,
     .max_endpoints_bits = MPIDI_OFI_MAX_ENDPOINTS_BITS_MINIMAL,
     .fetch_atomic_iovecs = MPIDI_OFI_FETCH_ATOMIC_IOVECS_MINIMAL,
     .context_bits = MPIDI_OFI_CONTEXT_BITS_MINIMAL,
     .source_bits = MPIDI_OFI_SOURCE_BITS_MINIMAL,
     .tag_bits = MPIDI_OFI_TAG_BITS_MINIMAL,
     .major_version = MPIDI_OFI_MAJOR_VERSION_MINIMAL,
     .minor_version = MPIDI_OFI_MINOR_VERSION_MINIMAL}
    ,
    {   /* psm2 */
     .enable_av_table = MPIDI_OFI_ENABLE_AV_TABLE_PSM2,
     .enable_scalable_endpoints = MPIDI_OFI_ENABLE_SCALABLE_ENDPOINTS_PSM2,
     .enable_shared_contexts = MPIDI_OFI_ENABLE_SHARED_CONTEXTS_PSM2,
     .enable_mr_virt_address = MPIDI_OFI_ENABLE_MR_VIRT_ADDRESS_PSM2,
     .enable_mr_allocated = MPIDI_OFI_ENABLE_MR_ALLOCATED_PSM2,
     .enable_mr_prov_key = MPIDI_OFI_ENABLE_MR_PROV_KEY_PSM2,
     .enable_tagged = MPIDI_OFI_ENABLE_TAGGED_PSM2,
     .enable_am = MPIDI_OFI_ENABLE_AM_PSM2,
     .enable_rma = MPIDI_OFI_ENABLE_RMA_PSM2,
     .enable_atomics = MPIDI_OFI_ENABLE_ATOMICS_PSM2,
     .enable_data_auto_progress = MPIDI_OFI_ENABLE_DATA_AUTO_PROGRESS_PSM2,
     .enable_control_auto_progress = MPIDI_OFI_ENABLE_CONTROL_AUTO_PROGRESS_PSM2,
     .enable_pt2pt_nopack = MPIDI_OFI_ENABLE_PT2PT_NOPACK_PSM2,
     .enable_triggered = MPIDI_OFI_ENABLE_TRIGGERED_PSM2,
     .num_am_buffers = MPIDI_OFI_NUM_AM_BUFFERS_PSM2,
     .max_endpoints = MPIDI_OFI_MAX_ENDPOINTS_PSM2,
     .max_endpoints_bits = MPIDI_OFI_MAX_ENDPOINTS_BITS_PSM2,
     .fetch_atomic_iovecs = MPIDI_OFI_FETCH_ATOMIC_IOVECS_PSM2,
     .context_bits = MPIDI_OFI_CONTEXT_BITS_PSM2,
     .source_bits = MPIDI_OFI_SOURCE_BITS_PSM2,
     .tag_bits = MPIDI_OFI_TAG_BITS_PSM2,
     .major_version = MPIDI_OFI_MAJOR_VERSION_PSM2,
     .minor_version = MPIDI_OFI_MINOR_VERSION_PSM2}
    ,
    {   /* sockets */
     .enable_av_table = MPIDI_OFI_ENABLE_AV_TABLE_SOCKETS,
     .enable_scalable_endpoints = MPIDI_OFI_ENABLE_SCALABLE_ENDPOINTS_SOCKETS,
     .enable_shared_contexts = MPIDI_OFI_ENABLE_SHARED_CONTEXTS_SOCKETS,
     .enable_mr_virt_address = MPIDI_OFI_ENABLE_MR_VIRT_ADDRESS_SOCKETS,
     .enable_mr_allocated = MPIDI_OFI_ENABLE_MR_ALLOCATED_SOCKETS,
     .enable_mr_prov_key = MPIDI_OFI_ENABLE_MR_PROV_KEY_SOCKETS,
     .enable_tagged = MPIDI_OFI_ENABLE_TAGGED_SOCKETS,
     .enable_am = MPIDI_OFI_ENABLE_AM_SOCKETS,
     .enable_rma = MPIDI_OFI_ENABLE_RMA_SOCKETS,
     .enable_atomics = MPIDI_OFI_ENABLE_ATOMICS_SOCKETS,
     .enable_data_auto_progress = MPIDI_OFI_ENABLE_DATA_AUTO_PROGRESS_SOCKETS,
     .enable_control_auto_progress = MPIDI_OFI_ENABLE_CONTROL_AUTO_PROGRESS_SOCKETS,
     .enable_pt2pt_nopack = MPIDI_OFI_ENABLE_PT2PT_NOPACK_SOCKETS,
     .enable_triggered = MPIDI_OFI_ENABLE_TRIGGERED_SOCKETS,
     .num_am_buffers = MPIDI_OFI_NUM_AM_BUFFERS_SOCKETS,
     .max_endpoints = MPIDI_OFI_MAX_ENDPOINTS_SOCKETS,
     .max_endpoints_bits = MPIDI_OFI_MAX_ENDPOINTS_BITS_SOCKETS,
     .fetch_atomic_iovecs = MPIDI_OFI_FETCH_ATOMIC_IOVECS_SOCKETS,
     .context_bits = MPIDI_OFI_CONTEXT_BITS_SOCKETS,
     .source_bits = MPIDI_OFI_SOURCE_BITS_SOCKETS,
     .tag_bits = MPIDI_OFI_TAG_BITS_SOCKETS,
     .major_version = MPIDI_OFI_MAJOR_VERSION_SOCKETS,
     .minor_version = MPIDI_OFI_MINOR_VERSION_SOCKETS}
    ,
    {   /* bgq */
     .enable_av_table = MPIDI_OFI_ENABLE_AV_TABLE_BGQ,
     .enable_scalable_endpoints = MPIDI_OFI_ENABLE_SCALABLE_ENDPOINTS_BGQ,
     .enable_shared_contexts = MPIDI_OFI_ENABLE_SHARED_CONTEXTS_BGQ,
     .enable_mr_virt_address = MPIDI_OFI_ENABLE_MR_VIRT_ADDRESS_BGQ,
     .enable_mr_allocated = MPIDI_OFI_ENABLE_MR_ALLOCATED_BGQ,
     .enable_mr_prov_key = MPIDI_OFI_ENABLE_MR_PROV_KEY_BGQ,
     .enable_tagged = MPIDI_OFI_ENABLE_TAGGED_BGQ,
     .enable_am = MPIDI_OFI_ENABLE_AM_BGQ,
     .enable_rma = MPIDI_OFI_ENABLE_RMA_BGQ,
     .enable_atomics = MPIDI_OFI_ENABLE_ATOMICS_BGQ,
     .enable_data_auto_progress = MPIDI_OFI_ENABLE_DATA_AUTO_PROGRESS_BGQ,
     .enable_control_auto_progress = MPIDI_OFI_ENABLE_CONTROL_AUTO_PROGRESS_BGQ,
     .enable_pt2pt_nopack = MPIDI_OFI_ENABLE_PT2PT_NOPACK_BGQ,
     .enable_triggered = MPIDI_OFI_ENABLE_TRIGGERED_BGQ,
     .num_am_buffers = MPIDI_OFI_NUM_AM_BUFFERS_BGQ,
     .max_endpoints = MPIDI_OFI_MAX_ENDPOINTS_BGQ,
     .max_endpoints_bits = MPIDI_OFI_MAX_ENDPOINTS_BITS_BGQ,
     .fetch_atomic_iovecs = MPIDI_OFI_FETCH_ATOMIC_IOVECS_BGQ,
     .context_bits = MPIDI_OFI_CONTEXT_BITS_BGQ,
     .source_bits = MPIDI_OFI_SOURCE_BITS_BGQ,
     .tag_bits = MPIDI_OFI_TAG_BITS_BGQ,
     .major_version = MPIDI_OFI_MAJOR_VERSION_BGQ,
     .minor_version = MPIDI_OFI_MINOR_VERSION_BGQ}
    ,
    {   /* cassini */
     .enable_av_table = MPIDI_OFI_ENABLE_AV_TABLE_CXI,
     .enable_scalable_endpoints = MPIDI_OFI_ENABLE_SCALABLE_ENDPOINTS_CXI,
     .enable_shared_contexts = MPIDI_OFI_ENABLE_SHARED_CONTEXTS_CXI,
     .enable_mr_virt_address = MPIDI_OFI_ENABLE_MR_VIRT_ADDRESS_CXI,
     .enable_mr_allocated = MPIDI_OFI_ENABLE_MR_ALLOCATED_CXI,
     .enable_mr_prov_key = MPIDI_OFI_ENABLE_MR_PROV_KEY_CXI,
     .enable_tagged = MPIDI_OFI_ENABLE_TAGGED_CXI,
     .enable_am = MPIDI_OFI_ENABLE_AM_CXI,
     .enable_rma = MPIDI_OFI_ENABLE_RMA_CXI,
     .enable_atomics = MPIDI_OFI_ENABLE_ATOMICS_CXI,
     .enable_data_auto_progress = MPIDI_OFI_ENABLE_DATA_AUTO_PROGRESS_CXI,
     .enable_control_auto_progress = MPIDI_OFI_ENABLE_CONTROL_AUTO_PROGRESS_CXI,
     .enable_pt2pt_nopack = MPIDI_OFI_ENABLE_PT2PT_NOPACK_CXI,
     .enable_triggered = MPIDI_OFI_ENABLE_TRIGGERED_CXI,
     .num_am_buffers = MPIDI_OFI_NUM_AM_BUFFERS_CXI,
     .max_endpoints = MPIDI_OFI_MAX_ENDPOINTS_CXI,
     .max_endpoints_bits = MPIDI_OFI_MAX_ENDPOINTS_BITS_CXI,
     .fetch_atomic_iovecs = MPIDI_OFI_FETCH_ATOMIC_IOVECS_CXI,
     .context_bits = MPIDI_OFI_CONTEXT_BITS_CXI,
     .source_bits = MPIDI_OFI_SOURCE_BITS_CXI,
     .tag_bits = MPIDI_OFI_TAG_BITS_CXI,
     .major_version = MPIDI_OFI_MAJOR_VERSION_MINIMAL,
     .minor_version = MPIDI_OFI_MINOR_VERSION_MINIMAL}
    ,
    {   /* VERBS_RXM */
     .enable_av_table = MPIDI_OFI_ENABLE_AV_TABLE_VERBS_RXM,
     .enable_scalable_endpoints = MPIDI_OFI_ENABLE_SCALABLE_ENDPOINTS_VERBS_RXM,
     .enable_shared_contexts = MPIDI_OFI_ENABLE_SHARED_CONTEXTS_VERBS_RXM,
     .enable_mr_virt_address = MPIDI_OFI_ENABLE_MR_VIRT_ADDRESS_VERBS_RXM,
     .enable_mr_allocated = MPIDI_OFI_ENABLE_MR_ALLOCATED_VERBS_RXM,
     .enable_mr_prov_key = MPIDI_OFI_ENABLE_MR_PROV_KEY_VERBS_RXM,
     .enable_tagged = MPIDI_OFI_ENABLE_TAGGED_VERBS_RXM,
     .enable_am = MPIDI_OFI_ENABLE_AM_VERBS_RXM,
     .enable_rma = MPIDI_OFI_ENABLE_RMA_VERBS_RXM,
     .enable_atomics = MPIDI_OFI_ENABLE_ATOMICS_VERBS_RXM,
     .enable_data_auto_progress = MPIDI_OFI_ENABLE_DATA_AUTO_PROGRESS_VERBS_RXM,
     .enable_control_auto_progress = MPIDI_OFI_ENABLE_CONTROL_AUTO_PROGRESS_VERBS_RXM,
     .enable_pt2pt_nopack = MPIDI_OFI_ENABLE_PT2PT_NOPACK_VERBS_RXM,
     .enable_triggered = MPIDI_OFI_ENABLE_TRIGGERED_VERBS_RXM,
     .num_am_buffers = MPIDI_OFI_NUM_AM_BUFFERS_VERBS_RXM,
     .max_endpoints = MPIDI_OFI_MAX_ENDPOINTS_VERBS_RXM,
     .max_endpoints_bits = MPIDI_OFI_MAX_ENDPOINTS_BITS_VERBS_RXM,
     .fetch_atomic_iovecs = MPIDI_OFI_FETCH_ATOMIC_IOVECS_VERBS_RXM,
     .context_bits = MPIDI_OFI_CONTEXT_BITS_VERBS_RXM,
     .source_bits = MPIDI_OFI_SOURCE_BITS_VERBS_RXM,
     .tag_bits = MPIDI_OFI_TAG_BITS_VERBS_RXM,
     .major_version = MPIDI_OFI_MAJOR_VERSION_RXM,
     .minor_version = MPIDI_OFI_MINOR_VERSION_RXM}
    ,
    {   /* RxM */
     .enable_av_table = MPIDI_OFI_ENABLE_AV_TABLE_RXM,
     .enable_scalable_endpoints = MPIDI_OFI_ENABLE_SCALABLE_ENDPOINTS_RXM,
     .enable_shared_contexts = MPIDI_OFI_ENABLE_SHARED_CONTEXTS_RXM,
     .enable_mr_virt_address = MPIDI_OFI_ENABLE_MR_VIRT_ADDRESS_RXM,
     .enable_mr_allocated = MPIDI_OFI_ENABLE_MR_ALLOCATED_RXM,
     .enable_mr_prov_key = MPIDI_OFI_ENABLE_MR_PROV_KEY_RXM,
     .enable_tagged = MPIDI_OFI_ENABLE_TAGGED_RXM,
     .enable_am = MPIDI_OFI_ENABLE_AM_RXM,
     .enable_rma = MPIDI_OFI_ENABLE_RMA_RXM,
     .enable_atomics = MPIDI_OFI_ENABLE_ATOMICS_RXM,
     .enable_data_auto_progress = MPIDI_OFI_ENABLE_DATA_AUTO_PROGRESS_RXM,
     .enable_control_auto_progress = MPIDI_OFI_ENABLE_CONTROL_AUTO_PROGRESS_RXM,
     .enable_pt2pt_nopack = MPIDI_OFI_ENABLE_PT2PT_NOPACK_RXM,
     .enable_triggered = MPIDI_OFI_ENABLE_TRIGGERED_RXM,
     .num_am_buffers = MPIDI_OFI_NUM_AM_BUFFERS_RXM,
     .max_endpoints = MPIDI_OFI_MAX_ENDPOINTS_RXM,
     .max_endpoints_bits = MPIDI_OFI_MAX_ENDPOINTS_BITS_RXM,
     .fetch_atomic_iovecs = MPIDI_OFI_FETCH_ATOMIC_IOVECS_RXM,
     .context_bits = MPIDI_OFI_CONTEXT_BITS_RXM,
     .source_bits = MPIDI_OFI_SOURCE_BITS_RXM,
     .tag_bits = MPIDI_OFI_TAG_BITS_RXM,
     .major_version = MPIDI_OFI_MAJOR_VERSION_RXM,
     .minor_version = MPIDI_OFI_MINOR_VERSION_RXM}
    ,
    {   /* GNI */
     .enable_av_table = MPIDI_OFI_ENABLE_AV_TABLE_GNI,
     .enable_scalable_endpoints = MPIDI_OFI_ENABLE_SCALABLE_ENDPOINTS_GNI,
     .enable_shared_contexts = MPIDI_OFI_ENABLE_SHARED_CONTEXTS_GNI,
     .enable_mr_virt_address = MPIDI_OFI_ENABLE_MR_VIRT_ADDRESS_GNI,
     .enable_mr_allocated = MPIDI_OFI_ENABLE_MR_ALLOCATED_GNI,
     .enable_mr_prov_key = MPIDI_OFI_ENABLE_MR_PROV_KEY_GNI,
     .enable_tagged = MPIDI_OFI_ENABLE_TAGGED_GNI,
     .enable_am = MPIDI_OFI_ENABLE_AM_GNI,
     .enable_rma = MPIDI_OFI_ENABLE_RMA_GNI,
     .enable_atomics = MPIDI_OFI_ENABLE_ATOMICS_GNI,
     .enable_data_auto_progress = MPIDI_OFI_ENABLE_DATA_AUTO_PROGRESS_GNI,
     .enable_control_auto_progress = MPIDI_OFI_ENABLE_CONTROL_AUTO_PROGRESS_GNI,
     .enable_pt2pt_nopack = MPIDI_OFI_ENABLE_PT2PT_NOPACK_GNI,
     .enable_triggered = MPIDI_OFI_ENABLE_TRIGGERED_GNI,
     .num_am_buffers = MPIDI_OFI_NUM_AM_BUFFERS_GNI,
     .max_endpoints = MPIDI_OFI_MAX_ENDPOINTS_GNI,
     .max_endpoints_bits = MPIDI_OFI_MAX_ENDPOINTS_BITS_GNI,
     .fetch_atomic_iovecs = MPIDI_OFI_FETCH_ATOMIC_IOVECS_GNI,
     .context_bits = MPIDI_OFI_CONTEXT_BITS_GNI,
     .source_bits = MPIDI_OFI_SOURCE_BITS_GNI,
     .tag_bits = MPIDI_OFI_TAG_BITS_GNI,
     .major_version = MPIDI_OFI_MAJOR_VERSION_GNI,
     .minor_version = MPIDI_OFI_MINOR_VERSION_GNI}
};
