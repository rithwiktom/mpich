/*
 * Copyright (C) by Argonne National Laboratory
 *     See COPYRIGHT in top-level directory
 */

#include "mpiimpl.h"
#include "utarray.h"
#include "treealgo_types.h"
#include "treeutil.h"
#include "mpiimpl.h"

/* Required declaration*/
static void tree_topology_print_hierarchy(UT_array hierarchy[], int myrank);

static int tree_add_child(MPIR_Treealgo_tree_t * t, int rank)
{
    int mpi_errno = MPI_SUCCESS;

    utarray_push_back(t->children, &rank, MPL_MEM_COLL);
    t->num_children++;

    return mpi_errno;
}

/* Routine to calculate log_k of an integer. Specific to tree based calculations */
static int tree_ilog(int k, int number)
{
    int i = 1, p = k - 1;

    for (; p - 1 < number; i++)
        p *= k;

    return i;
}

int MPII_Treeutil_tree_kary_init(int rank, int nranks, int k, int root, MPIR_Treealgo_tree_t * ct)
{
    int lrank, child;
    int mpi_errno = MPI_SUCCESS;

    ct->rank = rank;
    ct->nranks = nranks;
    ct->parent = -1;
    utarray_new(ct->children, &ut_int_icd, MPL_MEM_COLL);
    ct->num_children = 0;

    MPIR_Assert(nranks >= 0);

    if (nranks == 0)
        goto fn_exit;

    lrank = (rank + (nranks - root)) % nranks;

    ct->parent = (lrank == 0) ? -1 : (((lrank - 1) / k) + root) % nranks;

    for (child = 1; child <= k; child++) {
        int val = lrank * k + child;

        if (val >= nranks)
            break;

        val = (val + root) % nranks;
        mpi_errno = tree_add_child(ct, val);
        MPIR_ERR_CHECK(mpi_errno);
    }

  fn_exit:
    return mpi_errno;

  fn_fail:
    goto fn_exit;
}

/* Some examples of knomial_1 tree */
/*     4 ranks                8 ranks
 *       0                      0
 *     /  \                 /   |   \
 *    1   3               1     5    7
 *    |                 /   \   |
 *    2                2     4  6
 *                     |
 *                     3
 */
int MPII_Treeutil_tree_knomial_1_init(int rank, int nranks, int k, int root,
                                      MPIR_Treealgo_tree_t * ct)
{
    int lrank, i, j, maxstep, tmp, step, parent, current_rank, running_rank, crank;
    int mpi_errno = MPI_SUCCESS;

    ct->rank = rank;
    ct->nranks = nranks;
    ct->parent = -1;

    MPIR_Assert(nranks >= 0);

    if (nranks == 0)
        goto fn_exit;

    lrank = (rank + (nranks - root)) % nranks;
    MPIR_Assert(k >= 2);

    /* maximum number of steps while generating the knomial tree */
    maxstep = 0;
    for (tmp = nranks - 1; tmp; tmp /= k)
        maxstep++;

    utarray_new(ct->children, &ut_int_icd, MPL_MEM_COLL);
    ct->num_children = 0;
    step = 0;
    parent = -1;        /* root has no parent */
    current_rank = 0;   /* start at root of the tree */
    running_rank = current_rank + 1;    /* used for calculation below
                                         * start with first child of the current_rank */

    for (step = 0;; step++) {
        MPIR_Assert(step <= nranks);    /* actually, should not need more steps than log_k(nranks) */

        /* desired rank found */
        if (lrank == current_rank)
            break;

        /* check if rank lies in this range */
        for (j = 1; j < k; j++) {
            if (lrank >= running_rank && lrank < running_rank + MPL_ipow(k, maxstep - step - 1)) {
                /* move to the corresponding subtree */
                parent = current_rank;
                current_rank = running_rank;
                running_rank = current_rank + 1;
                break;
            }

            running_rank += MPL_ipow(k, maxstep - step - 1);
        }
    }

    /* set the parent */
    if (parent == -1)
        ct->parent = -1;
    else
        ct->parent = (parent + root) % nranks;

    /* set the children */
    crank = lrank + 1;  /* crank stands for child rank */
    MPL_DBG_MSG_FMT(MPIR_DBG_COLL, VERBOSE,
                    (MPL_DBG_FDEST, "parent of rank %d is %d, total ranks = %d (root=%d)", rank,
                     ct->parent, nranks, root));
    for (i = step; i < maxstep; i++) {
        for (j = 1; j < k; j++) {
            if (crank < nranks) {
                MPL_DBG_MSG_FMT(MPIR_DBG_COLL, VERBOSE,
                                (MPL_DBG_FDEST, "adding child %d to rank %d",
                                 (crank + root) % nranks, rank));
                mpi_errno = tree_add_child(ct, (crank + root) % nranks);
                MPIR_ERR_CHECK(mpi_errno);
            }
            crank += MPL_ipow(k, maxstep - i - 1);
        }
    }

  fn_exit:
    return mpi_errno;

  fn_fail:
    goto fn_exit;
}


/* Some examples of knomial_2 tree */
/*     4 ranks               8 ranks
 *       0                      0
 *     /  \                 /   |   \
 *    2    1              4     2    1
 *    |                  / \    |
 *    3                 6   5   3
 *                      |
 *                      7
 */
int MPII_Treeutil_tree_knomial_2_init(int rank, int nranks, int k, int root,
                                      MPIR_Treealgo_tree_t * ct)
{
    int mpi_errno = MPI_SUCCESS;
    int lrank, i, j, depth;
    int *flip_bit, child;

    ct->rank = rank;
    ct->nranks = nranks;
    ct->num_children = 0;
    ct->parent = -1;

    MPIR_Assert(nranks >= 0);
    if (nranks <= 0)
        return mpi_errno;

    lrank = (rank + (nranks - root)) % nranks;
    MPIR_Assert(k >= 2);

    utarray_new(ct->children, &ut_int_icd, MPL_MEM_COLL);
    ct->num_children = 0;

    /* Parent calculation */
    if (lrank <= 0)
        ct->parent = -1;
    else {
        depth = tree_ilog(k, nranks - 1);

        for (i = 0; i < depth; i++) {
            if (MPL_getdigit(k, lrank, i)) {
                ct->parent = (MPL_setdigit(k, lrank, i, 0) + root) % nranks;
                break;
            }
        }
    }

    /* Children calculation */
    depth = tree_ilog(k, nranks - 1);
    flip_bit = (int *) MPL_calloc(depth, sizeof(int), MPL_MEM_COLL);
    MPIR_ERR_CHKANDJUMP(!flip_bit, mpi_errno, MPI_ERR_OTHER, "**nomem");

    for (j = 0; j < depth; j++) {
        if (MPL_getdigit(k, lrank, j)) {
            break;
        }
        flip_bit[j] = 1;
    }

    for (j = depth - 1; j >= 0; j--) {
        if (flip_bit[j] == 1) {
            for (i = k - 1; i >= 1; i--) {
                child = MPL_setdigit(k, lrank, j, i);
                if (child < nranks)
                    tree_add_child(ct, (child + root) % nranks);
            }
        }
    }

    MPL_DBG_MSG_FMT(MPIR_DBG_COLL, VERBOSE,
                    (MPL_DBG_FDEST, "parent of rank %d is %d, total ranks = %d (root=%d)", rank,
                     ct->parent, nranks, root));
    MPL_free(flip_bit);

  fn_exit:
    return mpi_errno;

  fn_fail:
    goto fn_exit;
}

/* Topology aware */
/* Realizations of help functions for building topology aware */
static int *tree_ut_rank_ensure_fit(UT_array * a, int index)
{
    static const int defval = -1;
    while (index >= utarray_len(a)) {
        utarray_push_back_int(a, &defval, MPL_MEM_COLL);
    }
    return &ut_int_array(a)[index];
}

static int map_coord_to_index(const struct coord_t *coord, UT_array * level, int new_relative_idx)
{
    int i, len = utarray_len(level);
    const struct hierarchy_t *level_arr = ut_type_array(level, struct hierarchy_t *);
    for (i = 0; i < len; ++i) {
        if (memcmp(&level_arr[i].coord, coord, sizeof *coord) == 0)
            return i;
    }
    utarray_extend_back(level, MPL_MEM_COLL);
    memcpy(&tree_ut_hierarchy_back(level)->coord, coord, sizeof *coord);
    tree_ut_hierarchy_back(level)->relative_idx = new_relative_idx;
    return len;
}

static inline void set_level_rank_indices(struct hierarchy_t *level, int r, int myrank, int root,
                                          int idx)
{
    if (r == root) {
        level->root_idx = idx;
        if (level->myrank_idx == idx)
            level->myrank_idx = -1;
    }
    if (r == myrank)
        level->myrank_idx = idx;
}

/* Some examples of topology aware tree */
/*configure file content:
 *# rank:  switch_id group_id
 *  0          0        68
 *  1          0        68
 *  2          1        68
 *  3          0        69
 *  4          1        69
 *  5          1        69
 *  6          1        70
 *  7          0        70
 *
 * g.id|     68        69       70
 *          /  \      /  \      / \
 * s.id|    0   1    0    1    0   1
 *         / \  |    |   / \   |   |
 * r.id|  0   1 2    3  4   5  7   6
 *
 * [0]leaders: [0, 1, 2] [3, 4, 5] [7, 6] switch
 * [1]leaders:   [1, 2]   [3, 5]     [6]  group
 * [2]leaders:     [1]      [3]      [6]  world
 */

/* Implementation of 'Topology aware' algorithm */

/* Important: The initialization of Topology Aware breaks
 * and falls back on the Kary tree building.
 * (1)When it is the MPI_Spawn and (2)not being able to
 * build the hierarchy of the topology-aware tree.
 * For the mentioned cases  see tags 'goto fn_fallback;'. */

int MPII_Treeutil_tree_topology_aware_init(MPIR_Comm * comm,
                                           MPIR_Treealgo_params_t * params,
                                           MPIR_Treealgo_tree_t * ct)
{
    int mpi_errno = MPI_SUCCESS;
    int nranks = params->nranks;
    int root = params->root;
    int myrank = params->rank;
    int fallback_flag = 0;

    /* MPI_Spawn's fallback: If COMM_WORLD's new nranks number
     * is greater than it used to be, it falls back. */
    if (nranks > MPIR_Process.size) {
        fallback_flag = 1;
        goto fn_fallback;
    }

    /* One extra level 'world' is needed */
    MPIR_Assert(MPIR_Process.coords_dims < MAX_HIERARCHY_DEPTH);

    UT_array hierarchy[MAX_HIERARCHY_DEPTH];

    /* Initialization for world level */
    int lvl = MPIR_Process.coords_dims;
    tree_ut_hierarchy_init(&hierarchy[lvl]);
    utarray_extend_back(&hierarchy[lvl], MPL_MEM_COLL);

    /* Initialization for the rest levels */
    for (lvl = MPIR_Process.coords_dims - 1; lvl >= 0; --lvl)
        tree_ut_hierarchy_init(&hierarchy[lvl]);

    for (int r = 0; r < nranks; ++r) {
        struct hierarchy_t *upper_level =
            tree_ut_hierarchy_back(&hierarchy[MPIR_Process.coords_dims]);
        int lvl_idx = 0;
        int upper_level_root = params->root;
        int wrank = MPIDIU_rank_to_lpid(r, comm);
        if (wrank < 0)
            goto fn_fallback;

        MPIR_Assert(0 <= wrank && wrank < MPIR_Process.size);

        for (lvl = MPIR_Process.coords_dims - 1; lvl >= 0; --lvl) {
            struct coord_t lvl_coord =
                { MPIR_Process.coords[wrank * MPIR_Process.coords_dims + lvl], lvl_idx };

            if (lvl_coord.id < 0)
                goto fn_fallback;

            lvl_idx =
                map_coord_to_index(&lvl_coord, &hierarchy[lvl], utarray_len(&upper_level->ranks));
            struct hierarchy_t *cur_level = tree_ut_hierarchy_eltptr(&hierarchy[lvl], lvl_idx);

            int *root_ptr = tree_ut_rank_ensure_fit(&upper_level->ranks, cur_level->relative_idx);
            if (r == root || *root_ptr == -1) {
                *root_ptr = r;
                set_level_rank_indices(upper_level, r, myrank, upper_level_root,
                                       cur_level->relative_idx);
            }

            upper_level_root = *root_ptr;
            upper_level = cur_level;
        }

        set_level_rank_indices(upper_level, r, myrank, upper_level_root,
                               utarray_len(&upper_level->ranks));
        utarray_push_back_int(&upper_level->ranks, &r, MPL_MEM_COLL);
    }

    ct->rank = comm->rank;
    ct->nranks = comm->local_size;
    ct->parent = -1;
    ct->num_children = 0;
    utarray_new(ct->children, &ut_int_icd, MPL_MEM_COLL);

    for (lvl = MPIR_Process.coords_dims; lvl >= 0; --lvl) {
        int cur_level_count = utarray_len(&hierarchy[lvl]);

        for (int lvl_idx = 0; lvl_idx < cur_level_count; ++lvl_idx) {
            const struct hierarchy_t *level = tree_ut_hierarchy_eltptr(&hierarchy[lvl], lvl_idx);
            if (level->myrank_idx == -1)
                continue;
            MPIR_Assert(level->root_idx != -1);

            MPIR_Treealgo_tree_t tmp_tree;
            mpi_errno =
                MPII_Treeutil_tree_kary_init(level->myrank_idx, utarray_len(&level->ranks), 1,
                                             level->root_idx, &tmp_tree);
            MPIR_ERR_CHECK(mpi_errno);

            int children_number = utarray_len(tmp_tree.children);
            int *children = ut_int_array(tmp_tree.children);
            for (int i = 0; i < children_number; ++i) {
                int r = tree_ut_int_elt(&level->ranks, children[i]);
                mpi_errno = tree_add_child(ct, r);
                MPIR_ERR_CHECK(mpi_errno);
            }

            if (tmp_tree.parent != -1) {
                MPIR_Assert(ct->parent == -1);
                ct->parent = tree_ut_int_elt(&level->ranks, tmp_tree.parent);
            }

            MPIR_Treealgo_tree_free(&tmp_tree);
        }
    }

    /* free memory */
    for (dim = 0; dim <= MPIR_Process.coords_dims; ++dim)
        utarray_done(&hierarchy[dim]);

  fn_exit:
    if (!fallback_flag) {
        for (lvl = 0; lvl <= MPIR_Process.coords_dims; ++lvl)
            utarray_done(&hierarchy[lvl]);
    }
    return mpi_errno;

  fn_fail:
    goto fn_exit;

  fn_fallback:
    MPL_DBG_MSG_FMT(MPIR_DBG_COLL, VERBOSE,
                    (MPL_DBG_FDEST, "due to falling out of the topology-aware initialization, "
                     "it falls back on the kary tree building"));
    mpi_errno = MPII_Treeutil_tree_kary_init(myrank, nranks, 1, root, ct);
    MPIR_ERR_CHECK(mpi_errno);
    goto fn_exit;
}

int MPII_Treeutil_tree_topology_wave_init(MPIR_Comm * comm,
                                          MPIR_Treealgo_params_t * params,
                                          MPIR_Treealgo_tree_t * ct)
{
    int mpi_errno = MPI_SUCCESS;
    /* TODO: implementation of Topology Wave algorithm */

    return mpi_errno;
}

static void tree_topology_print_hierarchy(UT_array hierarchy[], int myrank)
{
    for (int lvl = MPIR_Process.coords_dims; lvl >= 0; --lvl) {
        printf("[%d] hierarchy[%d] = [", myrank, lvl);
        for (int lvl_idx = 0; lvl_idx < utarray_len(&hierarchy[lvl]); ++lvl_idx) {
            if (lvl_idx > 0)
                printf(",");
            struct hierarchy_t *cur_level = tree_ut_hierarchy_eltptr(&hierarchy[lvl], lvl_idx);
            printf("{{%d,%d}", cur_level->coord.id, cur_level->coord.parent_idx);
            printf(",%d,%d,%d,[", cur_level->relative_idx, cur_level->root_idx,
                   cur_level->myrank_idx);
            for (int i = 0; i < utarray_len(&cur_level->ranks); ++i) {
                if (i > 0)
                    printf(",");
                printf("%d", tree_ut_int_elt(&cur_level->ranks, i));
            }
            printf("]}");
        }
        printf("]\n");
        fflush(stdout);
    }
}
