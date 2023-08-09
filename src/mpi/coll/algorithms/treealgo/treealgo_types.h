/*
 * Copyright (C) by Argonne National Laboratory
 *     See COPYRIGHT in top-level directory
 */

#ifndef TREEALGO_TYPES_H_INCLUDED
#define TREEALGO_TYPES_H_INCLUDED

#include <utarray.h>

typedef struct {
    int rank;
    int nranks;
    int parent;
    int num_children;
    UT_array *children;
} MPIR_Treealgo_tree_t;

typedef struct {
    int rank;
    int nranks;
    int k;
    int tree_type;
    int subtree_type;
    int root;
    bool enable_reorder;
    int overhead;
    int lat_diff_groups;
    int lat_diff_switches;
    int lat_same_switches;
} MPIR_Treealgo_params_t;

#endif /* TREEALGO_TYPES_H_INCLUDED */
