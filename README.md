# Detect damaged append-optimized tables

If an append-optimized is damaged so that select fails with an error:

```
   gp_relation_node (2) has more entries than pg_aocsseg (0) for relation ...
```

the table cannot be identified as damaged by `gpcheckcat`.  This
repository provides a mechanism to detect all such tables in a
Greenplum 5X deployment.  It is not tested against newer Greenplum
versions.

To obtain the list of such tables, run the SQL script against each
database:

```
   psql -d <database> -e -f damaged_ao_tables.sql
```

Sample output is as follows:

```
select
    d.ao_oid::regclass as ao_tablename,
    d.*,
    c.relfilenode as aoseg_relfilenode,
    dir.paramvalue as datadir
from
    damaged_ao_tables d,
    gp_dist_random('pg_class') c,
    gp_toolkit.__gp_param_local_setting('data_directory') dir
where
    c.gp_segment_id = d.gpsegid
    and d.gpsegid = dir.paramsegment
    and c.oid = d.aoseg_oid;

ao_tablename  | gpsegid | ao_oid | aoseg_oid | aoseg_count | pt_count | aoseg_relfilenode |                                  datadir                                   
---------------+---------+--------+-----------+-------------+----------+-------------------+----------------------------------------------------------------------------
 co_test       |       0 |  16539 |     16544 |           0 |        3 |             16472 | /Users/apraveen/workspace/gpdb5/gpAux/gpdemo/datadirs/dbfast1/demoDataDir0
 co_t1         |       0 |  16394 |     16399 |           0 |        3 |             16393 | /Users/apraveen/workspace/gpdb5/gpAux/gpdemo/datadirs/dbfast1/demoDataDir0
 ao_t1         |       0 |  16384 |     16389 |           0 |        3 |             16387 | /Users/apraveen/workspace/gpdb5/gpAux/gpdemo/datadirs/dbfast1/demoDataDir0
 foo_p_1_prt_8 |       2 |  16698 |     16701 |           0 |        2 |             16542 | /Users/apraveen/workspace/gpdb5/gpAux/gpdemo/datadirs/dbfast3/demoDataDir2
(4 rows)
```

Here we have three tables damaged on seg0 and foo_p_1_prt_8 table
damaged on seg2.  Running `select count(*)` against each of these
tables should fail.