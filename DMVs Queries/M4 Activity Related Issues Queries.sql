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
- 

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

-- Gives you input buffer information from all non-system sessions for the current database
-- Replaces DBCC INPUTBUFFER

-- New DMF for retrieving input buffer in SQL Server
-- https://bit.ly/2uHKMbz





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
------




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
------

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
------

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
------

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
ORDER BY s.user_updates DESC OPTION (RECOMPILE);						 -- Order by writes
------








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
------

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

