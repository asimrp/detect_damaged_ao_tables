# Detect damaged append-optimized tables

If an append-optimized is damaged so that select  fails with an error:

```
   gp_relation_node (2) has more entries than pg_aocsseg (0) for relation ...
```

such table cannot be detected by `gpcheckcat`.  This repository
provides a mechanism to detect all such tables in a Greenplum 5X
deployment.  It is not tested against newer Greenplum versions.
