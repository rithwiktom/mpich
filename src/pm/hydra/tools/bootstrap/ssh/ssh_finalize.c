/* -*- Mode: C; c-basic-offset:4 ; -*- */
/*
 *  (C) 2008 by Argonne National Laboratory.
 *      See COPYRIGHT in top-level directory.
 */

#include "hydra_utils.h"
#include "bsci.h"
#include "ssh.h"

HYD_status HYDT_bscd_ssh_finalize(void)
{
    struct HYDT_bscd_ssh_time *e, *tmp;
    HYD_status status = HYD_SUCCESS;

    HYDU_FUNC_ENTER();

    for (e = HYDT_bscd_ssh_time; e;) {
        HYDU_FREE(e->hostname);
        tmp = e->next;
        HYDU_FREE(e);
        e = tmp;
    }

    HYDU_FUNC_EXIT();

    return status;
}
