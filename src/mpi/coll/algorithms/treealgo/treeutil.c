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
static void tree_topology_print_hierarchy(UT_array hierarchy[], int myrank) ATTRIBUTE((unused));
static void tree_topology_print_heaps_built(heap_vector * minHeaps) ATTRIBUTE((unused));

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

/*Toplogy tree helpers*/

/* tree init function is for building hierarchy of MPIR_Process::coords_dims */
static int MPII_Treeutil_tree_init(MPIR_Comm * comm, MPIR_Treealgo_params_t * params,
                                   UT_array * hierarchy)
{
    int mpi_errno = MPI_SUCCESS;
    int fallback_flag = 0;

    /* MPI_Spawn's fallback: If COMM_WORLD's new nranks number
     * is greater than it used to be, it falls back. */
    if (params->nranks > MPIR_Process.size) {
        fallback_flag = 1;
        goto fn_fail;
    }

    /* One extra level 'world' is needed */
    MPIR_Assert(MPIR_Process.coords_dims < MAX_HIERARCHY_DEPTH);

    /* Initialization for world level */
    int lvl = MPIR_Process.coords_dims;
    tree_ut_hierarchy_init(&hierarchy[lvl]);
    utarray_extend_back(&hierarchy[lvl], MPL_MEM_COLL);

    /* Initialization for the rest levels */
    for (lvl = MPIR_Process.coords_dims - 1; lvl >= 0; --lvl)
        tree_ut_hierarchy_init(&hierarchy[lvl]);

    for (int r = 0; r < params->nranks; ++r) {
        struct hierarchy_t *upper_level =
            tree_ut_hierarchy_back(&hierarchy[MPIR_Process.coords_dims]);
        int lvl_idx = 0;
        int upper_level_root = params->root;
        int wrank = MPIDIU_rank_to_lpid(r, comm);
        if (wrank < 0)
            goto fn_fail;

        MPIR_Assert(0 <= wrank && wrank < MPIR_Process.size);

        for (lvl = MPIR_Process.coords_dims - 1; lvl >= 0; --lvl) {
            struct coord_t lvl_coord =
                { MPIR_Process.coords[wrank * MPIR_Process.coords_dims + lvl], lvl_idx };

            if (lvl_coord.id < 0)
                goto fn_fail;

            lvl_idx =
                map_coord_to_index(&lvl_coord, &hierarchy[lvl], utarray_len(&upper_level->ranks));
            struct hierarchy_t *cur_level = tree_ut_hierarchy_eltptr(&hierarchy[lvl], lvl_idx);

            int *root_ptr = tree_ut_rank_ensure_fit(&upper_level->ranks, cur_level->relative_idx);
            if (r == params->root || *root_ptr == -1) {
                *root_ptr = r;
                set_level_rank_indices(upper_level, r, params->rank, upper_level_root,
                                       cur_level->relative_idx);
            }

            if (upper_level->child_idx == -1) {
                upper_level->child_idx = lvl_idx;
            }
            upper_level_root = *root_ptr;
            upper_level = cur_level;
        }

        set_level_rank_indices(upper_level, r, params->rank, upper_level_root,
                               utarray_len(&upper_level->ranks));
        utarray_push_back_int(&upper_level->ranks, &r, MPL_MEM_COLL);
    }

  fn_exit:
    if (!fallback_flag) {
        for (lvl = 0; lvl <= MPIR_Process.coords_dims; ++lvl)
            utarray_done(&hierarchy[lvl]);
    }
    return mpi_errno;

  fn_fail:
    mpi_errno = MPI_ERR_TOPOLOGY;
    goto fn_exit;
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

    UT_array hierarchy[MAX_HIERARCHY_DEPTH];
    int lvl = MPIR_Process.coords_dims;

    if (MPII_Treeutil_tree_init(comm, params, hierarchy))
        goto fn_fallback;

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

/* Implementation of 'Topology wave' algorithm */

/* Implementation of a min-heap */
static minHeap *initMinHeap(void)
{
    minHeap *hp = MPL_malloc(sizeof(minHeap) * 1, MPL_MEM_BUFFER);
    hp->size = 0;
    return hp;
}

static void swap(pair * n1, pair * n2)
{
    pair temp = *n1;
    *n1 = *n2;
    *n2 = temp;
}

static void heapify(minHeap * hp, int i)
{
    int smallest = (LCHILD(i) < hp->size &&
                    hp->elem[LCHILD(i)].reach_time < hp->elem[i].reach_time) ? LCHILD(i) : i;
    if (RCHILD(i) < hp->size && hp->elem[RCHILD(i)].reach_time < hp->elem[smallest].reach_time) {
        smallest = RCHILD(i);
    }
    if (smallest != i) {
        swap(&(hp->elem[i]), &(hp->elem[smallest]));
        heapify(hp, smallest);
    }
}

static void insertNode(minHeap * hp, pair * data)
{
    if (hp->size) {
        hp->elem = MPL_realloc(hp->elem, (hp->size + 1) * sizeof(pair), MPL_MEM_BUFFER);
    } else {
        hp->elem = MPL_malloc(sizeof(pair) * (hp->size + 1), MPL_MEM_BUFFER);
    }
    pair nd;
    nd.num_rank = data->num_rank;
    nd.reach_time = data->reach_time;

    int i = (hp->size)++;
    while (i && nd.reach_time < hp->elem[PARENT(i)].reach_time) {
        hp->elem[i] = hp->elem[PARENT(i)];
        i = PARENT(i);
    }
    hp->elem[i] = nd;
}

static void deleteMinHeap(minHeap * hp)
{
    MPL_free(hp->elem);
}

/* Implementation of a vector for min-heaps */
static void heap_vector_init(heap_vector * v)
{
    v->capacity = VECTOR_INIT_CAPACITY;
    v->total = 0;
    v->heap = MPL_malloc(sizeof(minHeap) * v->capacity, MPL_MEM_BUFFER);
}

static void heap_vector_resize(heap_vector * v, int capacity)
{
    minHeap *heap = MPL_realloc(v->heap, sizeof(minHeap) * capacity, MPL_MEM_BUFFER);
    if (heap) {
        v->heap = heap;
        v->capacity = capacity;
    }
}

static void heap_vector_add(heap_vector * v, minHeap * item)
{
    if (v->capacity == v->total)
        heap_vector_resize(v, v->capacity * 2);
    v->heap[v->total].elem = item->elem;
    v->heap[v->total].size = item->size;
    v->total++;
}

static void heap_vector_free(heap_vector * v)
{
    MPL_free(v->heap);
}

static int latency(int unv_rank, int v_rank)
{
    /* latency of but different groups */
    if (MPIR_Process.coords[unv_rank * MPIR_Process.coords_dims + 1] !=
        MPIR_Process.coords[v_rank * MPIR_Process.coords_dims + 1])
        return MPIR_CVAR_NETWORK_TOPO_DIFF_GROUPS;

    /* latency of the same groups, but different switch */
    if (MPIR_Process.coords[unv_rank * MPIR_Process.coords_dims + 0] !=
        MPIR_Process.coords[v_rank * MPIR_Process.coords_dims + 0])
        return MPIR_CVAR_NETWORK_TOPO_DIFF_SWITCHES;

    /* latency of the same switch */
    return MPIR_CVAR_NETWORK_TOPO_SAME_SWITCHES;
}

static inline void take_children(const UT_array * hierarchy, int lead, UT_array * unv_set)
{
    /* take_children() finds children of the leader in the switch */

    struct hierarchy_t *rank_level = tree_ut_hierarchy_eltptr(&hierarchy[0], lead);
    for (int r = 0; r < utarray_len(&rank_level->ranks); r++) {
        if (r == 0) {
            /* Skip the lead of the switch because
             * it's already found and added */
            continue;
        }
        pair p;
        p.num_rank = tree_ut_int_elt(&rank_level->ranks, r);
        p.reach_time = 0;
        utarray_push_back(unv_set, &p, MPL_MEM_COLL);
    }
}

static int find_leader(const UT_array * hierarchy, UT_array * unv_set, int *group_idx,
                       int *switch_idx, heap_vector * minHeaps)
{
    /* find_leader() finds a switch leader and its children, filling array of heaps
     * and unvisited set. Maintain two vars 'group_idx' and 'switch_idx', they saves
     * coordinates, where the search of a leader stops, and continue the next call of
     * find_leader() with the saved coordinates. */

    /* To reach world level use 0 for element ptr */
    struct hierarchy_t *wr_level = tree_ut_hierarchy_eltptr(&hierarchy[2], 0);
    for (int gr_r_idx = *group_idx; gr_r_idx < utarray_len(&wr_level->ranks); gr_r_idx++) {
        struct hierarchy_t *sw_level = tree_ut_hierarchy_eltptr(&hierarchy[1], gr_r_idx);
        int exp = 0;
        for (int r_idx = *switch_idx; r_idx < utarray_len(&sw_level->ranks); r_idx++) {
            if (r_idx == 0 && gr_r_idx == 0) {
                /* Skip the switch ROOT's leader int its group */
                exp++;
                continue;
            }
            pair p;
            p.num_rank = tree_ut_int_elt(&sw_level->ranks, r_idx);
            p.reach_time = 0;
            utarray_push_back(unv_set, &p, MPL_MEM_COLL);

            minHeap *heap = initMinHeap();
            heap_vector_add(minHeaps, heap);
            MPL_free(heap);

            /* Take children of the lead in the switch */
            take_children(hierarchy, sw_level->child_idx + r_idx, unv_set);

            /* When there is not any switch insdie the current group,
             * shift to the next group and start with the 1st switch */
            if (utarray_len(&sw_level->ranks) - exp == r_idx) {
                *group_idx = *group_idx + 1;
                *switch_idx = 0;
            } else {
                /* If there're more switches in the current group,
                 * shift to the next switch and keep the current group id */
                *group_idx = gr_r_idx;
                *switch_idx = r_idx + 1;
            }
            return 0;
        }
        *switch_idx = 0;
    }
    *group_idx = 0;
    return -1;
}

static inline void take_earliest_time(UT_array * unvisited_set, const heap_vector * minHeaps,
                                      int *glob_reach_time, const int overhead,
                                      const int unvisited_node_idx, const int visited_sw_idx,
                                      int *best_v, int *best_u)
{
    pair_elt(unvisited_set, unvisited_node_idx)->reach_time =
        MPL_MIN(pair_elt(unvisited_set, unvisited_node_idx)->reach_time,
                minHeaps->heap[visited_sw_idx].elem->reach_time +
                latency(pair_elt(unvisited_set, unvisited_node_idx)->num_rank,
                        minHeaps->heap[visited_sw_idx].elem->num_rank) + 2 * overhead);
    if (*glob_reach_time > pair_elt(unvisited_set, unvisited_node_idx)->reach_time) {
        /* Update global reach time by current reach time of node */
        *glob_reach_time = pair_elt(unvisited_set, unvisited_node_idx)->reach_time;
        /* This is best current time, save indices */
        *best_v = visited_sw_idx;
        *best_u = unvisited_node_idx;
    }
}

static int init_root_switch(const UT_array * hierarchy, heap_vector * minHeaps,
                            UT_array * unv_set, const int root)
{
    /* init_root_switch() adds the first switch in a heap vector (array of heaps).
     * Origionally, inserts ROOT in the first created heap, then looks for ROOT's
     * children and also inserts them into the heap, push its children into the
     * unvisited set. If there are not ROOT's children, it falls back. */

    int mpi_errno = MPI_SUCCESS;
    /* Create the first heap for ROOT */
    minHeap *init_heap = initMinHeap();
    struct hierarchy_t *sw_level = tree_ut_hierarchy_eltptr(&hierarchy[1], root);
    pair p;

    p.num_rank = tree_ut_int_elt(&sw_level->ranks, root);
    p.reach_time = 0;
    /*Insert the ROOT's pair into the first heap of switches */
    insertNode(init_heap, &p);
    /* Take ROOTS's children */
    struct hierarchy_t *rank_level =
        tree_ut_hierarchy_eltptr(&hierarchy[0], sw_level->child_idx + root);
    /* Check if there are children (except ROOT) */
    if (utarray_len(&rank_level->ranks) > 1) {
        /*If yes, fill the ROOT's heap by children and push them into unvisited set */
        for (int r = 0; r < utarray_len(&rank_level->ranks); r++) {
            if (r == 0)
                continue;
            pair p_ch;
            p_ch.num_rank = tree_ut_int_elt(&rank_level->ranks, r);
            p_ch.reach_time = 0;
            insertNode(init_heap, &p_ch);
            utarray_push_back(unv_set, &p_ch, MPL_MEM_COLL);
        }
        /* Add the ROOT's filled heap into vector of heaps */
        heap_vector_add(minHeaps, init_heap);
    } else {    /* If no, it falls back */
        deleteMinHeap(init_heap);
        goto fn_fail;
    }

  fn_exit:
    if (init_heap)
        MPL_free(init_heap);
    return mpi_errno;
  fn_fail:
    mpi_errno =
        MPIR_Err_create_code(MPI_SUCCESS, MPIR_ERR_RECOVERABLE, __func__,
                             __LINE__, MPI_ERR_TOPOLOGY, "**nomem", 0);
    goto fn_exit;
}

/* 'Topology Wave' implementation */
int MPII_Treeutil_tree_topology_wave_init(MPIR_Comm * comm,
                                          MPIR_Treealgo_params_t * params,
                                          MPIR_Treealgo_tree_t * ct)
{
    int mpi_errno = MPI_SUCCESS;
    int rank = params->rank;
    int nranks = params->nranks;
    int root = params->root;
    int overhead = MPIR_CVAR_NETWORK_TOPO_OVERHEAD;
    int group_idx = 0;
    int switch_idx = 0;
    int size_comm = 0;
    UT_array hierarchy[MAX_HIERARCHY_DEPTH];

    /* To build hierarchy of ranks, swiches and groups */
    if (MPII_Treeutil_tree_init(comm, params, hierarchy))
        goto fn_fallback;

    UT_icd intpair_icd = { sizeof(pair), NULL, NULL, NULL };
    UT_array *unv_set;
    utarray_new(unv_set, &intpair_icd, MPL_MEM_COLL);

    heap_vector minHeaps;
    heap_vector_init(&minHeaps);

    if (init_root_switch(hierarchy, &minHeaps, unv_set, root))
        goto fn_fallback;

    ct->rank = rank;
    ct->nranks = nranks;
    ct->parent = -1;
    utarray_new(ct->children, &ut_int_icd, MPL_MEM_COLL);
    ct->num_children = 0;

    MPIR_Assert(nranks >= 0);

    if (nranks == 0)
        goto fn_exit;

    while (size_comm != nranks) {
        size_comm++;
        /* Index of best unvisited node */
        int best_u = -1;
        /* Index of best visited node */
        int best_v = -1;
        /* Global reach time */
        int glob_reach_time = INT_MAX;
        /* For every node u in unvisited set */
        for (int i = 0; i < utarray_len(unv_set); i++) {
            pair_elt(unv_set, i)->reach_time = INT_MAX;
            if (minHeaps.total - 1 != 0) {
                for (int j = 0; j < minHeaps.total - 1; j++) {
                    take_earliest_time(unv_set, &minHeaps, &glob_reach_time, overhead,
                                       i, j, &best_v, &best_u);
                }
            } else
                take_earliest_time(unv_set, &minHeaps, &glob_reach_time, overhead, 0,
                                   0, &best_v, &best_u);
        }

        /* Connect best_v--->best_u */
        if (rank == pair_elt(unv_set, best_u)->num_rank) {
            MPIR_Assert(ct->parent == -1);
            ct->parent = minHeaps.heap[best_v].elem->num_rank;
        } else if (rank == minHeaps.heap[best_v].elem->num_rank) {
            mpi_errno = tree_add_child(ct, pair_elt(unv_set, best_u)->num_rank);
            MPIR_ERR_CHECK(mpi_errno);
        }

        /* Add overheads to best_u/v */
        pair_elt(unv_set, best_u)->reach_time = glob_reach_time;
        minHeaps.heap[best_v].elem->reach_time += overhead;

        /* Update reach_time of visited node, adding +overhead,
         * and heapify the main heap with the updated values */
        heapify(&minHeaps.heap[best_v], best_v);

        /* Insert the best visited node into the main heap and heapify it */
        if (minHeaps.total - 1 != 0)    /* skip the 1st switch */
            insertNode(&minHeaps.heap[minHeaps.total - 1], pair_elt(unv_set, best_u));

        /* Remove best_u from the list of unvisited list
         * and reduce size of Unvisited set */
        utarray_erase(unv_set, best_u, 1);

        if (utarray_len(unv_set) == 0) {
            /* Find switch leaders and keep updating coordinates of
             * group/switch idx'es for next search */
            int ret = find_leader(hierarchy, unv_set, &group_idx, &switch_idx, &minHeaps);
            if (ret == -1 && utarray_len(unv_set) == 0) {
                /* If there is not any element to be added break the main while () */
                break;
            }
        }
    }

  fn_exit:
    utarray_free(unv_set);
    for (int i = 0; i < minHeaps.total; i++)
        deleteMinHeap(&minHeaps.heap[i]);
    heap_vector_free(&minHeaps);
    return mpi_errno;

  fn_fail:
    goto fn_exit;

  fn_fallback:
    MPL_DBG_MSG_FMT(MPIR_DBG_COLL, VERBOSE,
                    (MPL_DBG_FDEST, "due to falling out of the topology-aware initialization, "
                     "it falls back on the kary tree building"));
    mpi_errno = MPII_Treeutil_tree_kary_init(rank, nranks, 1, root, ct);
    MPIR_ERR_CHECK(mpi_errno);
    goto fn_exit;

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
            printf(",%d,%d,%d,%d,[", cur_level->child_idx, cur_level->relative_idx,
                   cur_level->root_idx, cur_level->myrank_idx);
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

static void tree_topology_print_heaps_built(heap_vector * minHeaps)
{
    fprintf(stderr, "total of array heap: %d\n", minHeaps->total);
    for (int i = 0; i < minHeaps->total; i++) {
        for (int j = 0; j < minHeaps->heap[i].size; j++) {
            fprintf(stderr, "heap[%d]: %d %d\n", i, minHeaps->heap[i].elem[j].num_rank,
                    minHeaps->heap[i].elem[j].reach_time);
        }
        fprintf(stderr, "\n");
    }
}
