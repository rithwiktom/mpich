/*
 * Copyright (C) by Argonne National Laboratory
 *     See COPYRIGHT in top-level directory
 */

#ifndef TREEUTIL_H_INCLUDED
#define TREEUTIL_H_INCLUDED


/* Specific data types for treealgo API */
struct coord_t {
    int id;
    int parent_idx;
};

struct hierarchy_t {
    struct coord_t coord;
    int relative_idx;
    int child_idx;
    int root_idx, myrank_idx;
    UT_array ranks;
};

typedef struct {
    int num_rank;
    int reach_time;
} pair;

typedef struct minHeap {
    int size;
    pair *elem;
} minHeap;

typedef struct {
    minHeap *heap;
    int capacity;
    int total;
} heap_vector;


/* Common tree building content*/
/* tree_ut_int_init must go BEFORE tree_ut_hierarchy_init() */
#define tree_ut_int_init(a) utarray_init((a), &ut_int_icd)


/* Specific tree_ut_hierarchy_* static functions */
static void tree_ut_hierarchy_init(void *elt)
{
    ((struct hierarchy_t *) elt)->coord.id = -1;
    ((struct hierarchy_t *) elt)->coord.parent_idx = -1;
    ((struct hierarchy_t *) elt)->child_idx = -1;
    ((struct hierarchy_t *) elt)->relative_idx = -1;
    ((struct hierarchy_t *) elt)->root_idx = -1;
    ((struct hierarchy_t *) elt)->myrank_idx = -1;
    tree_ut_int_init(&((struct hierarchy_t *) elt)->ranks);
}

static void tree_ut_hierarchy_dtor(void *elt)
{
    utarray_done(&((struct hierarchy_t *) elt)->ranks);
}

static const UT_icd tree_ut_hierarchy_icd =
    { sizeof(struct hierarchy_t), tree_ut_hierarchy_init, NULL, tree_ut_hierarchy_dtor };


/* Specific defines for treealgo API of utarray_* content */
#define MAX_HIERARCHY_DEPTH 4

/* Common defines */
#define tree_ut_int_elt(a, i) (*(int *)(utarray_eltptr((a), (i))))

/* For coordinates operations maintenance */
#define tree_ut_coord_init(a) utarray_init((a), &tree_ut_coord_icd)
#define tree_ut_coord_elt(a, i) ((struct coord_t *)(utarray_eltptr((a), (i))))

/* For hierarchy operations maintenance */
#define tree_ut_hierarchy_back(a) ((struct hierarchy_t *)(utarray_back((a))))
#define tree_ut_hierarchy_eltptr(a, i) ((struct hierarchy_t *)(utarray_eltptr((a), (i))))
#define tree_ut_hierarchy_init(a) utarray_init((a), &tree_ut_hierarchy_icd)

/* For pair operations maintenance */
#define pair_elt(a, i) ((pair *)(utarray_eltptr((a), (i))))

/* For MIN-HEAP operations maintenance */
#define LCHILD(x) 2 * x + 1
#define RCHILD(x) 2 * x + 2
#define PARENT(x) (x - 1) / 2
#define VECTOR_INIT_CAPACITY 4

/* Declarations for functions which provide the base implementations of tree buildings */
/* Generate kary tree information for rank 'rank' */
int MPII_Treeutil_tree_kary_init(int rank, int nranks, int k, int root, MPIR_Treealgo_tree_t * ct);

/* Generate knomial_1 tree information for rank 'rank' */
int MPII_Treeutil_tree_knomial_1_init(int rank, int nranks, int k, int root,
                                      MPIR_Treealgo_tree_t * ct);

/* Generate knomial_2 tree information for rank 'rank' */
int MPII_Treeutil_tree_knomial_2_init(int rank, int nranks, int k, int root,
                                      MPIR_Treealgo_tree_t * ct);

/* Generate topology_aware tree information */
int MPII_Treeutil_tree_topology_aware_init(MPIR_Comm * comm, MPIR_Treealgo_params_t * params,
                                           MPIR_Treealgo_tree_t * ct);

/* Generate topology_wave tree information */
int MPII_Treeutil_tree_topology_wave_init(MPIR_Comm * comm, MPIR_Treealgo_params_t * params,
                                          MPIR_Treealgo_tree_t * ct);

#endif /* TREEUTIL_H_INCLUDED */
