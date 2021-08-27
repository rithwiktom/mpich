#ifndef OFI_CSEL_CONTAINER_H_INCLUDED
#define OFI_CSEL_CONTAINER_H_INCLUDED

typedef enum {
    MPIDI_OFI_CSEL_CONTAINER_TYPE__ALGORITHM__MPIDI_OFI_Bcast_intra_triggered_tagged,
    MPIDI_OFI_CSEL_CONTAINER_TYPE__ALGORITHM__MPIDI_OFI_Bcast_intra_triggered_rma,
    MPIDI_OFI_CSEL_CONTAINER_TYPE__ALGORITHM__MPIDI_OFI_Bcast_intra_triggered_pipelined,
    MPIDI_OFI_CSEL_CONTAINER_TYPE__ALGORITHM__MPIDI_OFI_Bcast_intra_triggered_small_blocking,
    MPIDI_OFI_CSEL_CONTAINER_TYPE__ALGORITHM__MPIR_Bcast_impl,
    MPIDI_OFI_CSEL_CONTAINER_TYPE__ALGORITHM__MPIDI_OFI_Allreduce_intra_triggered_tagged,
    MPIDI_OFI_CSEL_CONTAINER_TYPE__ALGORITHM__MPIDI_OFI_Allreduce_intra_triggered_rma,
    MPIDI_OFI_CSEL_CONTAINER_TYPE__ALGORITHM__MPIDI_OFI_Allreduce_intra_triggered_pipelined,
    MPIDI_OFI_CSEL_CONTAINER_TYPE__ALGORITHM__MPIDI_OFI_Allreduce_intra_triggered_tree_small_message,
    MPIDI_OFI_CSEL_CONTAINER_TYPE__ALGORITHM__MPIR_Allreduce_impl,
    MPIDI_OFI_Algorithm_count,
} MPIDI_OFI_Csel_container_type_e;

typedef struct {
    MPIDI_OFI_Csel_container_type_e id;

    union {
        struct {
            struct {
                int k;
                int tree_type;
            } triggered_tagged;
            struct {
                int k;
                int tree_type;
            } triggered_rma;
            struct {
                int k;
                int tree_type;
                int chunk_size;
            } triggered_pipelined;
            struct {
                int k;
            } triggered_small_blocking;
        } bcast;
        struct {
            struct {
                int k;
                int tree_type;
            } triggered_tagged;
            struct {
                int k;
                int tree_type;
            } triggered_rma;
            struct {
                int k;
                int chunk_size;
            } triggered_pipelined;
            struct {
                int k;
            } triggered_tree_small_message;
        } allreduce;
    } u;
} MPIDI_OFI_csel_container_s;

#endif /* OFI_CSEL_CONTAINER_H_INCLUDED */
