/*
 * Copyright (C) by Argonne National Laboratory
 *     See COPYRIGHT in top-level directory
 */

#include "mpiimpl.h"
#include "datatype.h"

#define COPY_BUFFER_SZ 16384

static int do_localcopy(const void *sendbuf, MPI_Aint sendcount, MPI_Datatype sendtype,
                        void *recvbuf, MPI_Aint recvcount, MPI_Datatype recvtype,
                        MPIR_Typerep_req * typereq_req)
{
    int mpi_errno = MPI_SUCCESS;
    int sendtype_iscontig, recvtype_iscontig;
    MPI_Aint sendsize, recvsize, sdata_sz, rdata_sz, copy_sz;
    MPI_Aint true_extent, sendtype_true_lb, recvtype_true_lb;
    char *buf = NULL;
    MPL_pointer_attr_t send_attr, recv_attr;
    MPIR_CHKLMEM_DECL(1);

    MPIR_FUNC_ENTER;

    if (typereq_req)
        *typereq_req = MPIR_TYPEREP_REQ_NULL;

    MPIR_Datatype_get_size_macro(sendtype, sendsize);
    MPIR_Datatype_get_size_macro(recvtype, recvsize);

    sdata_sz = sendsize * sendcount;
    rdata_sz = recvsize * recvcount;

    send_attr.type = recv_attr.type = MPL_GPU_POINTER_UNREGISTERED_HOST;

    /* if there is no data to copy, bail out */
    if (!sdata_sz || !rdata_sz)
        goto fn_exit;

#if defined(HAVE_ERROR_CHECKING)
    if (sdata_sz > rdata_sz) {
        MPIR_ERR_SET2(mpi_errno, MPI_ERR_TRUNCATE, "**truncate", "**truncate %d %d", sdata_sz,
                      rdata_sz);
        copy_sz = rdata_sz;
    } else
#endif /* HAVE_ERROR_CHECKING */
        copy_sz = sdata_sz;

    /* Builtin types is the common case; optimize for it */
    MPIR_Datatype_iscontig(sendtype, &sendtype_iscontig);
    MPIR_Datatype_iscontig(recvtype, &recvtype_iscontig);

    MPIR_Type_get_true_extent_impl(sendtype, &sendtype_true_lb, &true_extent);
    MPIR_Type_get_true_extent_impl(recvtype, &recvtype_true_lb, &true_extent);

    /* For single pack/unpack cases, using nonblocking version for better throughput
     * when typereq_req is expected; otherwise using blocking version to minimize latency */
    if (sendtype_iscontig) {
        MPI_Aint actual_unpack_bytes;
        if (typereq_req) {
            MPIR_Typerep_iunpack(MPIR_get_contig_ptr(sendbuf, sendtype_true_lb), copy_sz, recvbuf,
                                 recvcount, recvtype, 0, &actual_unpack_bytes, typereq_req,
                                 MPIR_TYPEREP_FLAG_NONE);
        } else {
            MPIR_Typerep_unpack(MPIR_get_contig_ptr(sendbuf, sendtype_true_lb), copy_sz, recvbuf,
                                recvcount, recvtype, 0, &actual_unpack_bytes,
                                MPIR_TYPEREP_FLAG_NONE);
        }
        MPIR_ERR_CHKANDJUMP(actual_unpack_bytes != copy_sz, mpi_errno, MPI_ERR_TYPE,
                            "**dtypemismatch");
    } else if (recvtype_iscontig) {
        MPI_Aint actual_pack_bytes;
        if (typereq_req) {
            MPIR_Typerep_ipack(sendbuf, sendcount, sendtype, 0,
                               MPIR_get_contig_ptr(recvbuf, recvtype_true_lb), copy_sz,
                               &actual_pack_bytes, typereq_req, MPIR_TYPEREP_FLAG_NONE);
        } else {
            MPIR_Typerep_pack(sendbuf, sendcount, sendtype, 0,
                              MPIR_get_contig_ptr(recvbuf, recvtype_true_lb), copy_sz,
                              &actual_pack_bytes, MPIR_TYPEREP_FLAG_NONE);
        }
        MPIR_ERR_CHKANDJUMP(actual_pack_bytes != copy_sz, mpi_errno, MPI_ERR_TYPE,
                            "**dtypemismatch");
    } else {
        /* For multi-step pack/unpack, using only blocking version for simplicity. */

        intptr_t sfirst;
        intptr_t rfirst;

        MPIR_GPU_query_pointer_attr(sendbuf, &send_attr);
        MPIR_GPU_query_pointer_attr(recvbuf, &recv_attr);

        if (send_attr.type == MPL_GPU_POINTER_DEV && recv_attr.type == MPL_GPU_POINTER_DEV) {
            MPL_gpu_malloc((void **) &buf, COPY_BUFFER_SZ, recv_attr.device);
        } else if (send_attr.type == MPL_GPU_POINTER_DEV || recv_attr.type == MPL_GPU_POINTER_DEV) {
            MPL_gpu_malloc_host((void **) &buf, COPY_BUFFER_SZ);
        } else {
            MPIR_CHKLMEM_MALLOC(buf, char *, COPY_BUFFER_SZ, mpi_errno, "buf", MPL_MEM_BUFFER);
        }

        sfirst = 0;
        rfirst = 0;

        while (1) {
            MPI_Aint max_pack_bytes;
            if (copy_sz - sfirst > COPY_BUFFER_SZ) {
                max_pack_bytes = COPY_BUFFER_SZ;
            } else {
                max_pack_bytes = copy_sz - sfirst;
            }

            MPI_Aint actual_pack_bytes;
            MPIR_Typerep_pack(sendbuf, sendcount, sendtype, sfirst, buf,
                              max_pack_bytes, &actual_pack_bytes, MPIR_TYPEREP_FLAG_NONE);
            MPIR_Assert(actual_pack_bytes > 0);

            sfirst += actual_pack_bytes;

            MPI_Aint actual_unpack_bytes;
            MPIR_Typerep_unpack(buf, actual_pack_bytes, recvbuf, recvcount, recvtype,
                                rfirst, &actual_unpack_bytes, MPIR_TYPEREP_FLAG_NONE);
            MPIR_Assert(actual_unpack_bytes > 0);

            rfirst += actual_unpack_bytes;

            /* everything that was packed from the source type must be
             * unpacked; otherwise we will lose the remaining data in
             * buf in the next iteration. */
            MPIR_ERR_CHKANDJUMP(actual_pack_bytes != actual_unpack_bytes, mpi_errno,
                                MPI_ERR_TYPE, "**dtypemismatch");

            if (rfirst == copy_sz) {
                /* successful completion */
                break;
            }
        }

        if (send_attr.type == MPL_GPU_POINTER_DEV && recv_attr.type == MPL_GPU_POINTER_DEV) {
            MPL_gpu_free(buf);
        } else if (send_attr.type == MPL_GPU_POINTER_DEV || recv_attr.type == MPL_GPU_POINTER_DEV) {
            MPL_gpu_free_host(buf);
        }
    }

  fn_exit:
    MPIR_CHKLMEM_FREEALL();
    MPIR_FUNC_EXIT;
    return mpi_errno;
  fn_fail:
    if (buf) {
        if (send_attr.type == MPL_GPU_POINTER_DEV && recv_attr.type == MPL_GPU_POINTER_DEV) {
            MPL_gpu_free(buf);
        } else if (send_attr.type == MPL_GPU_POINTER_DEV || recv_attr.type == MPL_GPU_POINTER_DEV) {
            MPL_gpu_free_host(buf);
        }
    }
    goto fn_exit;
}

#ifdef MPL_HAVE_GPU
static int do_localcopy_gpu(const void *sendbuf, MPI_Aint sendcount, MPI_Datatype sendtype,
                            MPL_pointer_attr_t * send_attr, void *recvbuf, MPI_Aint recvcount,
                            MPI_Datatype recvtype, MPL_pointer_attr_t * recv_attr,
                            MPL_gpu_engine_type_t enginetype, bool commit,
                            MPIR_Typerep_req * typerep_req)
{
    int mpi_errno = MPI_SUCCESS;
    int mpl_errno = MPL_SUCCESS;
    int sendtype_iscontig, recvtype_iscontig;
    MPI_Aint sendsize, recvsize, sdata_sz, rdata_sz, copy_sz;
    MPI_Aint true_extent, sendtype_true_lb, recvtype_true_lb;
    MPL_gpu_request gpu_req;
    int completed = 0;
    int dev_id = -1;

    MPIR_FUNC_ENTER;

    if (typerep_req)
        *typerep_req = MPIR_TYPEREP_REQ_NULL;

    MPIR_Datatype_get_size_macro(sendtype, sendsize);
    MPIR_Datatype_get_size_macro(recvtype, recvsize);

    sdata_sz = sendsize * sendcount;
    rdata_sz = recvsize * recvcount;

    /* if there is no data to copy, bail out */
    if (!sdata_sz || !rdata_sz)
        goto fn_exit;

#if defined(HAVE_ERROR_CHECKING)
    if (sdata_sz > rdata_sz) {
        MPIR_ERR_SET2(mpi_errno, MPI_ERR_TRUNCATE, "**truncate", "**truncate %d %d", sdata_sz,
                      rdata_sz);
        copy_sz = rdata_sz;
    } else
#endif /* HAVE_ERROR_CHECKING */
        copy_sz = sdata_sz;

    /* This case is specific for contig datatypes */
    MPIR_Datatype_iscontig(sendtype, &sendtype_iscontig);
    MPIR_Datatype_iscontig(recvtype, &recvtype_iscontig);

    MPIR_Type_get_true_extent_impl(sendtype, &sendtype_true_lb, &true_extent);
    MPIR_Type_get_true_extent_impl(recvtype, &recvtype_true_lb, &true_extent);

    if (sendtype_iscontig && recvtype_iscontig) {
        if (copy_sz <= MPIR_CVAR_CH4_IPC_GPU_FAST_COPY_MAX_SIZE) {
            mpl_errno = MPL_gpu_fast_memcpy(MPIR_get_contig_ptr(sendbuf, sendtype_true_lb),
                                            send_attr, MPIR_get_contig_ptr(recvbuf,
                                                                           recvtype_true_lb),
                                            recv_attr, copy_sz);
            MPIR_ERR_CHKANDJUMP(mpl_errno != MPL_SUCCESS, mpi_errno, MPI_ERR_OTHER,
                                "**mpl_gpu_fast_memcpy");
        } else {
            if (send_attr == NULL) {
                MPL_pointer_attr_t sendattr;
                MPIR_GPU_query_pointer_attr(sendbuf, &sendattr);
                if (sendattr.type == MPL_GPU_POINTER_DEV) {
                    dev_id = MPL_gpu_get_dev_id_from_attr(&sendattr);
                }
            } else if (send_attr->type == MPL_GPU_POINTER_DEV) {
                dev_id = MPL_gpu_get_dev_id_from_attr(send_attr);
            }

            if (dev_id == -1) {
                if (recv_attr == NULL) {
                    MPL_pointer_attr_t recvattr;
                    MPIR_GPU_query_pointer_attr(recvbuf, &recvattr);
                    if (recvattr.type == MPL_GPU_POINTER_DEV) {
                        dev_id = MPL_gpu_get_dev_id_from_attr(&recvattr);
                    } else {
                        goto fn_fallback;
                    }
                } else if (recv_attr->type == MPL_GPU_POINTER_DEV) {
                    dev_id = MPL_gpu_get_dev_id_from_attr(recv_attr);
                } else {
                    /* fallback to do_localcopy */
                    goto fn_fallback;
                }
            }
            MPIR_ERR_CHKANDJUMP(dev_id == -1, mpi_errno, MPI_ERR_OTHER,
                                "**mpl_gpu_get_dev_id_from_attr");

            mpl_errno = MPL_gpu_imemcpy(MPIR_get_contig_ptr(recvbuf, recvtype_true_lb),
                                        MPIR_get_contig_ptr(sendbuf, sendtype_true_lb), copy_sz,
                                        dev_id, enginetype, &gpu_req, commit);
            MPIR_ERR_CHKANDJUMP(mpl_errno != MPL_SUCCESS, mpi_errno, MPI_ERR_OTHER,
                                "**mpl_gpu_imemcpy");

            while (!completed) {
                mpl_errno = MPL_gpu_test(&gpu_req, &completed);
                MPIR_ERR_CHKANDJUMP(mpl_errno != MPL_SUCCESS, mpi_errno, MPI_ERR_OTHER,
                                    "**mpl_gpu_test");
            }
        }
    } else {
        /* fallback to do_localcopy */
        goto fn_fallback;
    }

  fn_exit:
    MPIR_FUNC_EXIT;
    return mpi_errno;
  fn_fail:
    goto fn_exit;
  fn_fallback:
    mpi_errno =
        do_localcopy(sendbuf, sendcount, sendtype, recvbuf, recvcount, recvtype, typerep_req);
    MPIR_ERR_CHECK(mpi_errno);
    goto fn_exit;
}
#endif

int MPIR_Localcopy(const void *sendbuf, MPI_Aint sendcount, MPI_Datatype sendtype,
                   void *recvbuf, MPI_Aint recvcount, MPI_Datatype recvtype)
{
    int mpi_errno = MPI_SUCCESS;

    MPIR_FUNC_ENTER;

    mpi_errno = do_localcopy(sendbuf, sendcount, sendtype, recvbuf, recvcount, recvtype, NULL);
    MPIR_ERR_CHECK(mpi_errno);

  fn_exit:
    MPIR_FUNC_EXIT;
    return mpi_errno;
  fn_fail:
    goto fn_exit;
}

int MPIR_Ilocalcopy(const void *sendbuf, MPI_Aint sendcount, MPI_Datatype sendtype,
                    void *recvbuf, MPI_Aint recvcount, MPI_Datatype recvtype,
                    MPIR_Typerep_req * typereq_req)
{
    int mpi_errno = MPI_SUCCESS;

    MPIR_FUNC_ENTER;

    mpi_errno = do_localcopy(sendbuf, sendcount, sendtype, recvbuf, recvcount,
                             recvtype, typereq_req);
    MPIR_ERR_CHECK(mpi_errno);

  fn_exit:
    MPIR_FUNC_EXIT;
    return mpi_errno;
  fn_fail:
    goto fn_exit;
}

int MPIR_Localcopy_gpu(const void *sendbuf, MPI_Aint sendcount, MPI_Datatype sendtype,
                       MPL_pointer_attr_t * sendattr, void *recvbuf, MPI_Aint recvcount,
                       MPI_Datatype recvtype, MPL_pointer_attr_t * recvattr,
                       MPL_gpu_engine_type_t enginetype, bool commit)
{
    int mpi_errno = MPI_SUCCESS;

    MPIR_FUNC_ENTER;

#ifdef MPL_HAVE_GPU
    mpi_errno = do_localcopy_gpu(sendbuf, sendcount, sendtype, sendattr, recvbuf, recvcount,
                                 recvtype, recvattr, enginetype, commit, NULL);
    MPIR_ERR_CHECK(mpi_errno);
#else
    mpi_errno = do_localcopy(sendbuf, sendcount, sendtype, recvbuf, recvcount, recvtype, NULL);
    MPIR_ERR_CHECK(mpi_errno);
#endif

  fn_exit:
    MPIR_FUNC_EXIT;
    return mpi_errno;
  fn_fail:
    goto fn_exit;
}
