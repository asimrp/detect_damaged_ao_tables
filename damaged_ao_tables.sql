--
-- This SQL script determines damaged append-optimized tables.  The
-- damage is defined as discrepancy in segment file information
-- between persistent table and aoseg auxiliary table.  The script
-- outputs names of damaged append-optimized table and its aoseg
-- table.  The user is expected to manually fix the problem by first
-- executing a "select count(*) <tablename>" on each damaged
-- append-optimized table.  The select should fail with an error
-- claiming discrepancy between gp_relation_node and aoseg table.
-- Next step is to check if the aoseg relation can be fixed by
-- bringing a copy of its relfilenode from the affected segment's
-- mirror.
--
-- Assumption: "gpcheckcat" has passed all the checks on this
-- database.

begin;

-- Use the same snapshot to scan persistent table and auxiliary tables
-- so that concurrent DDL operations do not affect the results.
set transaction isolation level serializable;

\timing on

-- Create a table with one row for each column oriented table
-- containing unique segment numbers recorded in persistent table.
drop table if exists pt_ao_segfile_count;
create table pt_ao_segfile_count as
  (select
       g.gp_segment_id as segid,
       a.relid,
       a.segrelid,
       count(g.segment_file_num) as pt_count
   from
       gp_dist_random('gp_relation_node') g,
       gp_dist_random('pg_class') c,
       pg_appendonly a
   where
       g.gp_segment_id = c.gp_segment_id
       and g.relfilenode_oid = c.relfilenode
       and c.oid = a.relid and a.columnstore = true
       and g.segment_file_num >=0 and g.segment_file_num < 128
   group by g.gp_segment_id, a.relid, a.segrelid, c.relname)
  distributed by (segid);

-- Create a table with one row for each aocsseg auxiliary table
-- containing the count of segment numbers.
drop table if exists aux_ao_segfile_count;
create table aux_ao_segfile_count as
  (select
       a.gp_segment_id as segid,
       a.relid,
       a.segrelid,
       (select
            count(segno)
        from
	    gp_toolkit.__gp_aocsseg(a.relid)
	where
	    physical_segno >= 0
	    and physical_segno < 128)
       as aoseg_count
   from gp_dist_random('pg_appendonly') a
   where columnstore=true)
  distributed by (segid);

-- Populate the same information for row-oriented append-optimized
-- tables.
insert into pt_ao_segfile_count
  (select
       g.gp_segment_id as segid,
       a.relid,
       a.segrelid,
       count(g.segment_file_num) as pt_count
   from
       gp_dist_random('gp_relation_node') g,
       gp_dist_random('pg_class') c,
       pg_appendonly a
   where
       g.gp_segment_id = c.gp_segment_id
       and g.relfilenode_oid = c.relfilenode
       and c.oid = a.relid
       and a.columnstore = false
   group by
       g.gp_segment_id,
       a.relid,
       a.segrelid,
       c.relname);

insert into aux_ao_segfile_count
  (select
       a.gp_segment_id as segid,
       a.relid,
       a.segrelid,
       (select
            count(segno)
        from
	    gp_toolkit.__gp_aoseg_name(a.relid::regclass::text))
       as aoseg_count
   from gp_dist_random('pg_appendonly') a
   where columnstore=false);

-- Information between gp_relation_node and aoseg auxiliary can differ
-- at the most by 1.  This is because an empty table, right after
-- creation, contains one entry in gp_relation_node but its aoseg
-- table is empty.  The following query identifies tables having
-- discrepancy between segment file counts recorded in aoseg vs
-- persistent table.
drop table if exists damaged_ao_tables;
create table damaged_ao_tables as
  (select
       p.segid as gpsegid,
       a.relid as ao_oid,
       a.segrelid as aoseg_oid,
       a.aoseg_count,
       p.pt_count
   from
       aux_ao_segfile_count a
       full outer join
       pt_ao_segfile_count p
       on a.segid = p.segid
       and a.relid = p.relid
   where
       p.pt_count is null
       or a.aoseg_count is null
       or p.pt_count - a.aoseg_count > 1)
  distributed by(gpsegid);

end;

--
-- Final output: damaged table names and their aoseg table OIDs
--
select
    gpsegid,
    ao_oid::regclass,
    aoseg_oid,
    aoseg_count,
    pt_count
from
    damaged_ao_tables;
