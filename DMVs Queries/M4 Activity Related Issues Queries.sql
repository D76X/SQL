/*
***********************************************************************
M4 - Activity-related Queries
***********************************************************************
*/

------------------------------------------------------------------------------------------------
/*
Lock Waits

-1 show all the Tables and Indexes that have Lock Waites (LW) on them
-2 LWs are useful in scenario in conjuction with very high Average Task Counts ([A]TCs)
-3 the [A]TCs on Azure DBs can be very differnt from that of on-prem and it depends strogly on the Service Tier (DB-ST)
-4 show Page Lock Waits (PLWs)
-5 show Row Lock Waits  (RLWs)
-6 show the Cumulative Waits **since the last restart** (CWs)
-7 the technical improvement technique in these cases ins Index Tuning (IdxTun) which is effective in reducing LWs

-8 look for Tables &/or Rows that have **very high LWs**
---------------------------------------------------------------
-9 focus on HLWs on the **Cluster Index** of any table!

COUNTERMEASURE-1

when a HLW is detected on the CI of a table one way to reduce the LW
is to add useful Non-Clustered Indexes (NCIs) to the same table.
This works because any additional useful NCI can AVOID a CI scan in 
the query plans!

COUNTERMEASURE-2

DROP any unused Indexes on any Table because unused Indexes are scanned
by the DB engine and can cause HLWs.

COUNTERMEASURE-3

Set the proper ISOLATION LEVEL PROPERTIES on the DB to reduce concurrency i.e.
use READ COMMIT SNAPSHOT ISOLATION

Azure SQL Database – The Default Isolation Is?
https://blobeater.blog/2018/05/30/azure-sql-database-the-default-isolation-is/ 

Azure SQL Database: Non-blocking transactions
https://learn.microsoft.com/en-us/shows/azure-friday/azure-sql-database-non-blocking-transactions

---------------------------------------------------------------

*/


-- Get lock waits for current database (Query 1) (Lock Waits)
SELECT o.name AS [table_name], i.name AS [index_name], ios.index_id, ios.partition_number,
		SUM(ios.row_lock_wait_count) AS [total_row_lock_waits], 
		SUM(ios.row_lock_wait_in_ms) AS [total_row_lock_wait_in_ms],
		SUM(ios.page_lock_wait_count) AS [total_page_lock_waits],
		SUM(ios.page_lock_wait_in_ms) AS [total_page_lock_wait_in_ms],
		SUM(ios.page_lock_wait_in_ms)+ SUM(row_lock_wait_in_ms) AS [total_lock_wait_in_ms]
FROM sys.dm_db_index_operational_stats(DB_ID(), NULL, NULL, NULL) AS ios
INNER JOIN sys.objects AS o WITH (NOLOCK)
ON ios.[object_id] = o.[object_id]
INNER JOIN sys.indexes AS i WITH (NOLOCK)
ON ios.[object_id] = i.[object_id] 
AND ios.index_id = i.index_id
WHERE o.[object_id] > 100
GROUP BY o.name, i.name, ios.index_id, ios.partition_number
HAVING SUM(ios.page_lock_wait_in_ms)+ SUM(row_lock_wait_in_ms) > 0
ORDER BY total_lock_wait_in_ms DESC OPTION (RECOMPILE);
------

/*
SCALER UDF STATS
https://app.pluralsight.com/ilx/video-courses/97737eb6-d4fe-4add-bf29-5c5c528ef0c3/55f67122-5d83-4211-ad8d-aeb0256831a5/6ff91716-89f2-4f84-8b81-d543dd63c4cb

- Scaler UDF are known to cause performance problems for SQL Server ( especially SQL Server 2017 and eralier!)
- SUDF often prevent queries to be executed in parallel!
- for the current DB show the most CPU intensive Scaler User Defined Functions
------------------------------
- IMPROVEMENT-STRATEGY-1: 
one way to improve the performance cause by Scaler UDF is to try to INLINE the code of the SUDF in the query, if possible
------------------------------
- SQL Server 2019 AUTOMATICALLY inlines SUDF code to address the known problem (in compatibility level 150)
- Azure SQL Server may do the same but I am not sure
------------------------------
- IMPROVEMENT-STRATEGY-2:
Convert the SUDF to a Table-Valued UDF (TV-UDF) that returns a 1-row-1col table!
------------------------------
- IMPROVEMENT-STRATEGY-3:
Convert the SUDF to an equivalent T-SQL SP
------------------------------
*/

-------------------------------------
-- UDF Statistics for the current DB
-- Helps you investigate scalar UDF performance issues
-- sys.dm_exec_function_stats (Transact-SQL)
-- https://bit.ly/2q1Q6BM
-------------------------------------
-- This query is helpful for troubleshooting blocking and deadlocking issues
-- Look at UDF execution statistics (Query 2) (UDF Statistics)
SELECT OBJECT_NAME(object_id) AS [Function Name], total_worker_time,
       execution_count, total_elapsed_time,  
       total_elapsed_time/execution_count AS [avg_elapsed_time],  
       last_elapsed_time, last_execution_time, cached_time 
FROM sys.dm_exec_function_stats WITH (NOLOCK) 
WHERE database_id = DB_ID()
ORDER BY total_worker_time DESC OPTION (RECOMPILE); 
------

/*
INPUT BUFFER
https://app.pluralsight.com/ilx/video-courses/97737eb6-d4fe-4add-bf29-5c5c528ef0c3/55f67122-5d83-4211-ad8d-aeb0256831a5/bc7f2ae6-b31f-45f7-9c4a-18f83ec16d7d

- show the last query for each SPID that is connected to the DB
- provides useful performance metrics for each SPID
- it is useful to get a QUICK OVERVIEW of THE CURRENT WORKLOAD on the DB
- use ORDER BY clause to focus on a specific area
- use WHERE clause to filter the rsults
- help identify resources of LONG RUNNING QUERIES that are still executing

-- Gives you input buffer information from all non-system sessions for the current database
-- Replaces DBCC INPUTBUFFER
-- New DMF for retrieving input buffer in SQL Server
-- https://bit.ly/2uHKMbz 

*/

-- Get input buffer information for the current database (Query 3) (Input Buffer)
SELECT es.session_id, DB_NAME(es.database_id) AS [Database Name],
       es.login_time, es.cpu_time, es.logical_reads,
       es.[status], ib.event_info AS [Input Buffer]
FROM sys.dm_exec_sessions AS es WITH (NOLOCK)
CROSS APPLY sys.dm_exec_input_buffer(es.session_id, NULL) AS ib
WHERE es.database_id = DB_ID()
AND es.session_id > 50
AND es.session_id <> @@SPID OPTION (RECOMPILE);
------

/*
QUERY EXECUTION COUNTS (QEC)
https://app.pluralsight.com/ilx/video-courses/97737eb6-d4fe-4add-bf29-5c5c528ef0c3/55f67122-5d83-4211-ad8d-aeb0256831a5/815cda7a-52e4-406b-851b-b0aadaef268e

------------------------------------------------------------------------------
- QEC helps to undestand which queries are the most often executed queries!

A common performance scenario is whennew queries are available that were not
run in the past and the overall performance has been inpacted by these newly
deplyed queries.

This means that the DB BASELINE HAS CHANGED!
------------------------------------------------------------------------------
- all frequently executed queries SHOULD BE OPTIMIZED FIRST!
- all frequently executed queries ARE GOOD CANDIDATEs for CACHING either in teh middle-tier or in the client
- if a query is executed too often it may be an indication of a logic mistake in one of the application layers 
i.e. the query is invoked multiple times when a view is open in the client.


- most currently executed queries for the current DB this includes ALL uqeries that is SP, etc.
- LOOK FOR the **Has Index Missing** column that signals that there is a MISSING INDEX WARNING in the Query Plan Cache for that query
- LOOK AT the Graphical Execution Plan (GEP) for Insights 

*/

-- Get most frequently executed queries for this database (Query 4) (Query Execution Counts)
SELECT TOP(50) LEFT(t.[text], 50) AS [Short Query Text], qs.execution_count AS [Execution Count],
qs.total_logical_reads AS [Total Logical Reads],
qs.total_logical_reads/qs.execution_count AS [Avg Logical Reads],
qs.total_worker_time AS [Total Worker Time],
qs.total_worker_time/qs.execution_count AS [Avg Worker Time], 
qs.total_elapsed_time AS [Total Elapsed Time],
qs.total_elapsed_time/qs.execution_count AS [Avg Elapsed Time],
CASE WHEN CONVERT(nvarchar(max), qp.query_plan) LIKE N'%<MissingIndexes>%' THEN 1 ELSE 0 END AS [Has Missing Index], 
qs.creation_time AS [Creation Time]
,t.[text] AS [Complete Query Text], qp.query_plan AS [Query Plan] 
FROM sys.dm_exec_query_stats AS qs WITH (NOLOCK)
CROSS APPLY sys.dm_exec_sql_text(plan_handle) AS t 
CROSS APPLY sys.dm_exec_query_plan(plan_handle) AS qp 
WHERE t.dbid = DB_ID()
ORDER BY qs.execution_count DESC OPTION (RECOMPILE);

--------------------------------------------------------------------------------------------------------------
/*
SP Execution Count (SPEC)
https://app.pluralsight.com/ilx/video-courses/97737eb6-d4fe-4add-bf29-5c5c528ef0c3/55f67122-5d83-4211-ad8d-aeb0256831a5/006a5cf5-8d2e-4471-b1c5-59d1c707203c
Similar to the QUERY EXECUTION COUNTS (QEC)
*/
-- Top Cached SPs By Execution Count (Query 5) (SP Execution Counts)
SELECT TOP(100) p.name AS [SP Name], qs.execution_count AS [Execution Count],
ISNULL(qs.execution_count/DATEDIFF(Minute, qs.cached_time, GETDATE()), 0) AS [Calls/Minute],
qs.total_elapsed_time/qs.execution_count AS [Avg Elapsed Time],
qs.total_worker_time/qs.execution_count AS [Avg Worker Time],    
qs.total_logical_reads/qs.execution_count AS [Avg Logical Reads],
CASE WHEN CONVERT(nvarchar(max), qp.query_plan) LIKE N'%<MissingIndexes>%' THEN 1 ELSE 0 END AS [Has Missing Index],
FORMAT(qs.last_execution_time, 'yyyy-MM-dd HH:mm:ss', 'en-US') AS [Last Execution Time], 
FORMAT(qs.cached_time, 'yyyy-MM-dd HH:mm:ss', 'en-US') AS [Plan Cached Time]
,qp.query_plan AS [Query Plan] 
FROM sys.procedures AS p WITH (NOLOCK)
INNER JOIN sys.dm_exec_procedure_stats AS qs WITH (NOLOCK)
ON p.[object_id] = qs.[object_id]
CROSS APPLY sys.dm_exec_query_plan(qs.plan_handle) AS qp
WHERE qs.database_id = DB_ID()
AND DATEDIFF(Minute, qs.cached_time, GETDATE()) > 0
ORDER BY qs.execution_count DESC OPTION (RECOMPILE);

---------------------------------------------------------------------------------------

/*
SP Avg Elapsed Time
https://app.pluralsight.com/ilx/video-courses/97737eb6-d4fe-4add-bf29-5c5c528ef0c3/55f67122-5d83-4211-ad8d-aeb0256831a5/3ecc003b-efe5-4438-b5df-ff4eea5874c4

-1 shows the Cached SP ordered by the Avg Execyution Time (AET) in microseconds
-2 look for large differences between the min AET and the max AET

----------------------------
dAET = (maxAET - minAET)
----------------------------

When dAET is large it may indicate one of the following 

*****************************************************************************************
-3: <HAS MISSING INDEX> warning
that the SP may have <HAS MISSING INDEX> warning in its Cached Plan!
*****************************************************************************************
-4 : Bad CQP tsability

there is a PROBLEM WITH THE Cached Query Plan CQP stability that is it may be succeptible 
to large varuiance because of one or more of its parameters.
This could mean that for some sets of Params there are good CQPs but for some other sets
of Params there may be inefficient CQPs.
*****************************************************************************************

-5 inspect the Graphical Execution Plan (GEP) to understand the cost factors for the SP
*/


-- Tells you which cached stored procedures are called the most often
-- This helps you characterize and baseline your workload

-- Top Cached SPs By Avg Elapsed Time (Query 6) (SP Avg Elapsed Time)
SELECT TOP(25) p.name AS [SP Name], qs.min_elapsed_time, 
qs.total_elapsed_time/qs.execution_count AS [avg_elapsed_time], 
qs.max_elapsed_time, qs.last_elapsed_time, qs.total_elapsed_time, qs.execution_count, 
ISNULL(qs.execution_count/DATEDIFF(Minute, qs.cached_time, GETDATE()), 0) AS [Calls/Minute], 
qs.total_worker_time/qs.execution_count AS [AvgWorkerTime], 
qs.total_worker_time AS [TotalWorkerTime],
CASE WHEN CONVERT(nvarchar(max), qp.query_plan) LIKE N'%<MissingIndexes>%' THEN 1 ELSE 0 END AS [Has Missing Index],
FORMAT(qs.last_execution_time, 'yyyy-MM-dd HH:mm:ss', 'en-US') AS [Last Execution Time], 
FORMAT(qs.cached_time, 'yyyy-MM-dd HH:mm:ss', 'en-US') AS [Plan Cached Time]
,qp.query_plan AS [Query Plan] 
FROM sys.procedures AS p WITH (NOLOCK)
INNER JOIN sys.dm_exec_procedure_stats AS qs WITH (NOLOCK)
ON p.[object_id] = qs.[object_id]
CROSS APPLY sys.dm_exec_query_plan(qs.plan_handle) AS qp
WHERE qs.database_id = DB_ID()
AND DATEDIFF(Minute, qs.cached_time, GETDATE()) > 0
ORDER BY avg_elapsed_time DESC OPTION (RECOMPILE);

---------------------------------------------------------------------------------------------

/*
BAD NON-CLUSTERED INDEXES (BNC-IDX)
https://app.pluralsight.com/ilx/video-courses/97737eb6-d4fe-4add-bf29-5c5c528ef0c3/55f67122-5d83-4211-ad8d-aeb0256831a5/126d9197-d461-42ae-be72-d8e2c7cf4a40

The following is a summary of what defines a BAD NON-CLUSTERED INDEXES

-1 
has far more writes that reads: these are not very useful because you have the cost
of having to maintain the index which in turn is used only in a relatively few read
statements

-2 
has far more writes that reads: must be often updated by the server! 

-3 unused indexes increse the BD size thus the cost and the aintenance workflow

**************************************
-4 IMPORTANT:
**************************************
Do not remove indexes that are detected as BNC-IDX without scripting them out first
and storing the script in Source Control. 
It may happen that indeed these NC-IDX are legittimate in that they are used only
sparingly to create reports such as ANNUAL reports with heavy queries.
In this case these indexes may be required for the heavy query to succeed when they
are run.
*/

-- This helps you find high average elapsed time cached stored procedures that
-- may be easy to optimize with standard query tuning techniques
-- Possible Bad NC Indexes (writes > reads)  (Query 7) (Bad NC Indexes)
SELECT SCHEMA_NAME(o.[schema_id]) AS [Schema Name], 
OBJECT_NAME(s.[object_id]) AS [Table Name],
i.name AS [Index Name], i.index_id, 
i.is_disabled, i.is_hypothetical, i.has_filter, i.fill_factor,
s.user_updates AS [Total Writes], s.user_seeks + s.user_scans + s.user_lookups AS [Total Reads],
s.user_updates - (s.user_seeks + s.user_scans + s.user_lookups) AS [Difference]
FROM sys.dm_db_index_usage_stats AS s WITH (NOLOCK)
INNER JOIN sys.indexes AS i WITH (NOLOCK)
ON s.[object_id] = i.[object_id]
AND i.index_id = s.index_id
INNER JOIN sys.objects AS o WITH (NOLOCK)
ON i.[object_id] = o.[object_id]
WHERE OBJECTPROPERTY(s.[object_id],'IsUserTable') = 1
AND s.database_id = DB_ID()
AND s.user_updates > (s.user_seeks + s.user_scans + s.user_lookups)
AND i.index_id > 1 AND i.[type_desc] = N'NONCLUSTERED'
AND i.is_primary_key = 0 AND i.is_unique_constraint = 0 AND i.is_unique = 0
ORDER BY [Difference] DESC, [Total Writes] DESC, [Total Reads] ASC OPTION (RECOMPILE);


-----------------------------------------------------------------------------------------------------

/*

MISSING INDEXES (for the current DB)
https://app.pluralsight.com/ilx/video-courses/97737eb6-d4fe-4add-bf29-5c5c528ef0c3/55f67122-5d83-4211-ad8d-aeb0256831a5/02605ed9-aa61-4fde-ac65-fbd6486720b8

-1 WARNING: this query can be very easily misinterpreted 
-2 this looks at the output of the QUERY OPTIMIZER (QO) and see whether it advices to add indexes to improve a certain query
-3 be careful to add indexes just because the QO asks you to do so as this may leand to OVER INDEXING the DB which 
-4 pay particular attention to the following columns
----------------------------------------------------
last_user_seek: 
indicates the last time that the QO falgs this index as required, if it iupdates oftne this is a query part of your regular workload

user_seeks:
counts how may ttimes the QO has asked for this new index

avg_toltal_user_cost:
it computes the overall cost caused by the missing index on the table
----------------------------------------------------

-5 index_advantage + avg_user_inpact
avg_user_inpact 
avg_total_user_cost

the table is ordered by index_advantage but you ought to consider this together with the columns
that give the stats about the frequency with which the query is used including when it was last 
run.

avg_user_inpact 
expresses the % of performance improvment that could be achived by introducing the missing index.

avg_total_user_cost
expresses the RELATIVE cost of not having the suggested index.

-6 equality_colums , inequality_columns, included_columns

If you decide to indeed add the index add it based on the suggestion of the columns 
indicated by equality_colums first, then inequality_columns and finally included_columns.

The order in which the columns are provided by this DMV might not always be the best to 
attain the performance improvement and you would have to try to find the right order 
experimentally.
*/

-- Look for indexes with high numbers of writes and zero or very low numbers of reads
-- Consider your complete workload, and how long your instance has been running
-- Investigate further before dropping an index!
-- Missing Indexes for current database by Index Advantage  (Query 8) (Missing Indexes)
SELECT DISTINCT CONVERT(decimal(18,2), user_seeks * avg_total_user_cost * (avg_user_impact * 0.01)) 
AS [index_advantage], 
migs.last_user_seek, mid.[statement] AS [Database.Schema.Table],
mid.equality_columns, mid.inequality_columns, mid.included_columns,
migs.unique_compiles, migs.user_seeks, migs.avg_total_user_cost, migs.avg_user_impact,
OBJECT_NAME(mid.[object_id]) AS [Table Name], p.rows AS [Table Rows]
FROM sys.dm_db_missing_index_group_stats AS migs WITH (NOLOCK)
INNER JOIN sys.dm_db_missing_index_groups AS mig WITH (NOLOCK)
ON migs.group_handle = mig.index_group_handle
INNER JOIN sys.dm_db_missing_index_details AS mid WITH (NOLOCK)
ON mig.index_handle = mid.index_handle
INNER JOIN sys.partitions AS p WITH (NOLOCK)
ON p.[object_id] = mid.[object_id]
WHERE mid.database_id = DB_ID() 
ORDER BY index_advantage DESC OPTION (RECOMPILE);

------
/*
MIXED INDEX WARNINGS
https://app.pluralsight.com/ilx/video-courses/97737eb6-d4fe-4add-bf29-5c5c528ef0c3/55f67122-5d83-4211-ad8d-aeb0256831a5/9c261b0f-35f4-4292-b0da-924cf4e367f1

-1 finds the MISING INDEX WARNINGS LISTED IN THE QUERY CACHE

*****************************************************************************************
-2 WARNING!
this query may take a long time if you have a very active database with a long cache!

For example, it took ** 42 secs ** on dev701584772B-1 !

*****************************************************************************************

-3 it associates the MIWs with the corresponding offending SP & Query and provides 
details about the tables and columns on which the index is missing.
It also provides the corresponding EXECUTION PLAN that you may use to design the optimization.

-4 [Usecounts]
provides how often that SP/Query is used.

*/

-- Look at index advantage, last user seek time, number of user seeks to help determine source and importance
-- SQL Server is overly eager to add included columns, so beware
-- Do not just blindly add indexes that show up from this query!!!
-- Find missing index warnings for cached plans in the current database  (Query 9) (Missing Index Warnings)
-- Note: This query could take some time on a busy instance
SELECT TOP(25) OBJECT_NAME(objectid) AS [ObjectName], 
               cp.objtype, cp.usecounts, cp.size_in_bytes, query_plan
FROM sys.dm_exec_cached_plans AS cp WITH (NOLOCK)
CROSS APPLY sys.dm_exec_query_plan(cp.plan_handle) AS qp
WHERE CAST(query_plan AS NVARCHAR(MAX)) LIKE N'%MissingIndex%'
AND dbid = DB_ID()
ORDER BY cp.usecounts DESC OPTION (RECOMPILE);
------

/*

OVERALL INDEX USAGE FOR READS
https://app.pluralsight.com/ilx/video-courses/97737eb6-d4fe-4add-bf29-5c5c528ef0c3/55f67122-5d83-4211-ad8d-aeb0256831a5/7a457e3f-8596-4a2e-8da0-19ef1a4cb5e9

-1 finds which indexes in the current DB have the most reads and therefore it helps understand your workload
-2 index reads are VERY beneficial for SELECT query performance i.e. reporting workloads
-------------------------------------------------------------------------------
-3 THE INDEX WITH THE HIGHER READS ARE GOOD CANDIDATES FOR DATA COMPRESSION!

DATA COMPRESSIONS
https://learn.microsoft.com/en-us/sql/relational-databases/data-compression/data-compression?view=sql-server-ver16

ROW COMPRESSION
https://learn.microsoft.com/en-us/sql/relational-databases/data-compression/row-compression-implementation?view=sql-server-ver16

PAGE COMPRESSION
https://learn.microsoft.com/en-us/sql/relational-databases/data-compression/page-compression-implementation?view=azuresqldb-current
-------------------------------------------------------------------------------

-4 COLUMNS with high reads can be COLUMNSTORE INDEX candidates
https://learn.microsoft.com/en-us/sql/relational-databases/indexes/columnstore-indexes-overview?view=sql-server-ver16

-5 
provides the CUMULATIVE METRICS for all row-store indexes in the current DB
that gives an idea of which tables & indexes see the highest reading activity

*/
-- Helps you connect missing indexes to specific stored procedures or queries
-- This can help you decide whether to add them or not

--- Index Read/Write stats (all tables in current DB) ordered by Reads  (Query 10) (Overall Index Usage - Reads)
SELECT OBJECT_NAME(i.[object_id]) AS [ObjectName], i.[name] AS [IndexName], i.index_id, 
       s.user_seeks, s.user_scans, s.user_lookups,
	   s.user_seeks + s.user_scans + s.user_lookups AS [Total Reads], 
	   s.user_updates AS [Writes],  
	   i.[type_desc] AS [Index Type], i.fill_factor AS [Fill Factor], i.has_filter, i.filter_definition, 
	   s.last_user_scan, s.last_user_lookup, s.last_user_seek
FROM sys.indexes AS i WITH (NOLOCK)
LEFT OUTER JOIN sys.dm_db_index_usage_stats AS s WITH (NOLOCK)
ON i.[object_id] = s.[object_id]
AND i.index_id = s.index_id
AND s.database_id = DB_ID()
WHERE OBJECTPROPERTY(i.[object_id],'IsUserTable') = 1
ORDER BY s.user_seeks + s.user_scans + s.user_lookups DESC OPTION (RECOMPILE); -- Order by reads
------

/*

OVERALL INDEX USAGE FOR WRITES
https://app.pluralsight.com/ilx/video-courses/97737eb6-d4fe-4add-bf29-5c5c528ef0c3/55f67122-5d83-4211-ad8d-aeb0256831a5/f6e91ee8-b23a-4efc-a611-0d4aa330bf49

-1 finds which indexes in the current DB have the most WRITES and therefore it helps understand your workload from an I/O perspective
-2 INDEX WRITES ARE BAD for UPDATE / INSERT query performance!
-3 for those workloads that have many more writes than reads you may decide to DROP the index
-4 
pay attention to the fact that often this kind of situation is for REPORTING workloads 
which may need the index even if they are only occasionally run i.e. quorterly, yearly, etc. 

-5 returns the **cumulative metrics for all row-store indexes** in the current DB

*/

-- Show which indexes in the current database are most active for Reads
--- Index Read/Write stats (all tables in current DB) ordered by Writes  (Query 11) (Overall Index Usage - Writes)
SELECT OBJECT_NAME(i.[object_id]) AS [ObjectName], i.[name] AS [IndexName], i.index_id,
	   s.user_updates AS [Writes], s.user_seeks + s.user_scans + s.user_lookups AS [Total Reads], 
	   i.[type_desc] AS [Index Type], i.fill_factor AS [Fill Factor], i.has_filter, i.filter_definition,
	   s.last_system_update, s.last_user_update
FROM sys.indexes AS i WITH (NOLOCK)
LEFT OUTER JOIN sys.dm_db_index_usage_stats AS s WITH (NOLOCK)
ON i.[object_id] = s.[object_id]
AND i.index_id = s.index_id
AND s.database_id = DB_ID()
WHERE OBJECTPROPERTY(i.[object_id],'IsUserTable') = 1
ORDER BY s.user_updates DESC OPTION (RECOMPILE); -- Order by writes

----------------------------------------------------------------------------------------------

/*
VOLATILE INDEXES
https://app.pluralsight.com/ilx/video-courses/97737eb6-d4fe-4add-bf29-5c5c528ef0c3/55f67122-5d83-4211-ad8d-aeb0256831a5/68d1a0b3-d8a0-443a-bba5-9a3cf267dda7

-1 shows which indezes and statistics for the current db have the most updates
-2 helps undestand the RIGHTS workload
-3 helps undestand which service level your Azure DB should be in order to handle the workload
-4 on all VOALTILE tables be cautious with: 
> creating indexes as it may slow down writes considerably
> data compression for the same reason

-5 ON-PREM use FLASH STORAGE or NON-PARITY RAID levels for volitile data
https://learn.microsoft.com/en-us/sharepoint/administration/storage-and-sql-server-capacity-planning-and-configuration

-6 in Azure it is the service tier that determines the underlying hardware!
if you have lots of volitile tables with writes then you might need to upgrade the 
service tier as more I/O power is required in these cases.

*/

-- Look at most frequently modified indexes and statistics (Query 12) (Volatile Indexes)
SELECT o.[name] AS [Object Name], o.[object_id], o.[type_desc], s.[name] AS [Statistics Name], 
       s.stats_id, s.no_recompute, s.auto_created, s.is_incremental, s.is_temporary,
	   sp.modification_counter, sp.[rows], sp.rows_sampled, sp.last_updated
FROM sys.objects AS o WITH (NOLOCK)
INNER JOIN sys.stats AS s WITH (NOLOCK)
ON s.object_id = o.object_id
CROSS APPLY sys.dm_db_stats_properties(s.object_id, s.stats_id) AS sp
WHERE o.[type_desc] NOT IN (N'SYSTEM_TABLE', N'INTERNAL_TABLE')
AND sp.modification_counter > 0
ORDER BY sp.modification_counter DESC, o.name OPTION (RECOMPILE);

----------------------------------------------------------------------------------------------

/*

RECENT RESOURCE USAGE
https://app.pluralsight.com/ilx/video-courses/97737eb6-d4fe-4add-bf29-5c5c528ef0c3/55f67122-5d83-4211-ad8d-aeb0256831a5/99d167ee-e83f-46a4-a6c4-b9fe8eb9b8cf 

**************************************
THIS IS A Azure SQL DB Specific Query
it does not apply to on-prem versions
https://app.pluralsight.com/ilx/video-courses/97737eb6-d4fe-4add-bf29-5c5c528ef0c3/55f67122-5d83-4211-ad8d-aeb0256831a5/28935242-ba02-449d-b9e9-3f679b988d5e
**************************************

********************************************************************************
-1 it shows a snapshot of DATA EVERY 15 SECONDS AND IT GOES BACK 64 MINUTES!
********************************************************************************
-2 it is ** very recent ** snapshot of what is going on the DB
***************************************************************************************************************************
-3 ALL its column report %USAGE i.e CPU, MEMORY, etc. these % values are AGAINST THE LIMITs offered by your service tier!
***************************************************************************************************************************

-4 it shows also the AGV_IO_% & AVG_LOG_WRITE_%


-5 it can be used to validate whether the DB is in the right service tier
if you max out on one or more of the columns then you need one of the following:
> some tuning 
> upgrade the service tier

*/

-- This helps you understand your workload and make better decisions about 
-- things like data compression and adding new indexes to a table

-- Get recent resource usage (Query 13) (Recent Resource Usage)
SELECT end_time, dtu_limit, cpu_limit, avg_cpu_percent, avg_memory_usage_percent, 
       avg_data_io_percent, avg_log_write_percent,  xtp_storage_percent,
       max_worker_percent, max_session_percent,  avg_login_rate_percent,  
	   avg_instance_cpu_percent, avg_instance_memory_percent
FROM sys.dm_db_resource_stats WITH (NOLOCK) 
ORDER BY end_time DESC OPTION (RECOMPILE);
------

-- Returns a row of usage metrics every 15 seconds, going back 64 minutes
-- The end_time column is UTC time

-- sys.dm_db_resource_stats (Azure SQL Database)
-- https://bit.ly/2HaSpKn

