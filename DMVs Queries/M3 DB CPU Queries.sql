/*
***********************************************************************
M3 - CPU-related Queries 
***********************************************************************
*/

-- some queries are DB-specific
USE AxDB 
GO

/*

CPU Utilization by DB
https://app.pluralsight.com/ilx/video-courses/97737eb6-d4fe-4add-bf29-5c5c528ef0c3/3c000b9e-3ab1-4aae-b186-14e76ee78d9e/c38737cf-edc0-445b-ad11-ee7bafd4bfca

-1 help focus analysis if server is under CPU pressure
-2 find out shich DB on the server uses the most CPU
-3 more detailed analysis by top CPU queries and store procedures
-4 query and index tuning can be used to reduce CPU untilization 

The CPU% are the values of CPU utilization calculated on the basis of 
the query that are currently in the Query Plan Cache (QPC).
--------------------------------------------------------------------------
Therefore, if the QPC is cleared then thses figures will be lost!
--------------------------------------------------------------------------
*/

-- Get CPU utilization by database (Query 1) (CPU Usage by Database)

WITH DB_CPU_Stats
AS
(SELECT pa.DatabaseID, DB_Name(pa.DatabaseID) AS [Database Name], 
 SUM(qs.total_worker_time/1000) AS [CPU_Time_Ms]
 FROM sys.dm_exec_query_stats AS qs WITH (NOLOCK)
 CROSS APPLY (SELECT CONVERT(int, value) AS [DatabaseID] 
              FROM sys.dm_exec_plan_attributes(qs.plan_handle)
              WHERE attribute = N'dbid') AS pa
 GROUP BY DatabaseID)
SELECT ROW_NUMBER() OVER(ORDER BY [CPU_Time_Ms] DESC) AS [CPU Rank],
       [Database Name], [CPU_Time_Ms] AS [CPU Time (ms)], 
       CAST([CPU_Time_Ms] * 1.0 / SUM([CPU_Time_Ms]) OVER() * 100.0 AS DECIMAL(5, 2)) AS [CPU Percent]
FROM DB_CPU_Stats
WHERE DatabaseID <> 32767 -- ResourceDB
AND NOT [Database Name] IS NULL 
ORDER BY [CPU Rank] OPTION (RECOMPILE);

------

/*

TOP WORKER TIME QUERIES
https://app.pluralsight.com/ilx/video-courses/97737eb6-d4fe-4add-bf29-5c5c528ef0c3/3c000b9e-3ab1-4aae-b186-14e76ee78d9e/df6d6ea6-2dbe-4194-b13c-756eef215d01

-1 it showas all the Queries including SP ordered by WORKER TIME (WT)
-2 WORKER TIME (WT) is linked to CPU Utilization
-------------------------------------------------
-3 The typical workflow: 
- use the CPUU% query to find which DB has the largest value
- in the DB under that largest CPUU% use the WT query to find the query or queries that causes the largest share of the CPU Pressure
- in all normal cases the WT falls off quickly that is ony the TOP-N queries will be responsible for the high CPUU% on the DB
-------------------------------------------------

***************************
-4 **Has Missing Index**
***************************
The queries that have a value = 1 in this column refer to query that cannot be optimized as they lack an Index!

-5 examine the WT TOP-N Queries and determine what you cabn do to improve thier perfomrance by tuning them
-6 nomrallu **Query & Index Tuning** are the most effective way to improve the Performance of a Query

-7 all the columns with **Elapsed Time** are in Micorseconds!
*/

-- Helps determine which database is using the most CPU resources on the instance
-- Note: This only reflects CPU usage from the currently cached query plans

-- Get top total worker time queries for this database (Query 2) (Top Worker Time Queries)		
SELECT TOP(50) DB_NAME(t.[dbid]) AS [Database Name], 
REPLACE(REPLACE(LEFT(t.[text], 50), CHAR(10),''), CHAR(13),'') AS [Short Query Text],  
qs.total_worker_time AS [Total Worker Time], qs.min_worker_time AS [Min Worker Time],
qs.total_worker_time/qs.execution_count AS [Avg Worker Time], 
qs.max_worker_time AS [Max Worker Time], 
qs.min_elapsed_time AS [Min Elapsed Time], 
qs.total_elapsed_time/qs.execution_count AS [Avg Elapsed Time], 
qs.max_elapsed_time AS [Max Elapsed Time],
qs.min_logical_reads AS [Min Logical Reads],
qs.total_logical_reads/qs.execution_count AS [Avg Logical Reads],
qs.max_logical_reads AS [Max Logical Reads], 
qs.execution_count AS [Execution Count],
CASE WHEN CONVERT(nvarchar(max), qp.query_plan) LIKE N'%<MissingIndexes>%' 
THEN 1 ELSE 0 END AS [Has Missing Index],  
qs.creation_time AS [Creation Time]
,t.[text] AS [Query Text], qp.query_plan AS [Query Plan] 
FROM sys.dm_exec_query_stats AS qs WITH (NOLOCK)
CROSS APPLY sys.dm_exec_sql_text(plan_handle) AS t 
CROSS APPLY sys.dm_exec_query_plan(plan_handle) AS qp
WHERE t.dbid = DB_ID() 
ORDER BY qs.total_worker_time DESC OPTION (RECOMPILE);

----------------------------------------------------------------------------------------------------

/*

SP Worker Time
https://app.pluralsight.com/ilx/video-courses/97737eb6-d4fe-4add-bf29-5c5c528ef0c3/3c000b9e-3ab1-4aae-b186-14e76ee78d9e/bff24f25-8709-4f07-9b3e-d23b70f8445c

-1 This is the same as above for the SPs on a specific DB
-2 all that was said earlier holds valid also in this case
-3 in this case use **AvgWoerkerTime** to identify the SPs that may require some Index & Performance Tuning
-4 Look at the Graphical Execition Plan (GEP) to understand which parts of the SP should be optimized first
*/

-- Helps you find the most expensive queries from a CPU perspective for this database
-- Can also help track down parameter sniffing issues

-- Top Cached SPs By Total Worker time. Worker time relates to CPU cost  (Query 3) (SP Worker Time)
SELECT TOP(25) p.name AS [SP Name], qs.total_worker_time AS [TotalWorkerTime], 
qs.total_worker_time/qs.execution_count AS [AvgWorkerTime], qs.execution_count, 
ISNULL(qs.execution_count/DATEDIFF(Minute, qs.cached_time, GETDATE()), 0) AS [Calls/Minute],
qs.total_elapsed_time, qs.total_elapsed_time/qs.execution_count AS [avg_elapsed_time],
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
ORDER BY qs.total_worker_time DESC OPTION (RECOMPILE);

---------------------------------------------------------------------------------------------------------------

/*
HIGH AGGREAGTE CPU QUERIES
https://app.pluralsight.com/ilx/video-courses/97737eb6-d4fe-4add-bf29-5c5c528ef0c3/3c000b9e-3ab1-4aae-b186-14e76ee78d9e/fca557f6-7327-43ce-a5d0-0aca0ae8b081

-1 these queries are DB-specific  
-2 rely on QS being enabled!
-3 make sure that the QS is not in a READ-ONLY state because these queries will not provide accurate results in this case!
-4 show the HIGHEST AGGREAGET CPU Queries OVER THE LAST HOUR
-5 this is useful to diagnose the situations when the re is CPU Pressure and there has been a recent development on teh DB that amy have caused it
-6 IT IS POSSIBLE TO ALTER THE TIME RANGE from 1h to whatever makes sense in your user case
-7 it shows the queries SQL
-8 it shows the queries plans
------------------------------------------------------------------------------------------------------
-9 it shows the queries plans counts => if the counts is HIGH THERE MIGHT BE A QP STABILITY ISSUE!
------------------------------------------------------------------------------------------------------
-10  it shows whether particular queries or SPs have a FORCED PLAN!
------------------------------------------------------------------------------------------------------
*/

-- This helps you find the most expensive cached stored procedures from a CPU perspective
-- You should look at this if you see signs of CPU pressure



-- Get highest aggregate duration queries over last hour (Query 4) (High Aggregate Duration Queries)
WITH AggregatedDurationLastHour
AS
(SELECT q.query_id, SUM(count_executions * avg_duration) AS total_duration,
   COUNT (distinct p.plan_id) AS number_of_plans
   FROM sys.query_store_query_text AS qt WITH (NOLOCK)
   INNER JOIN sys.query_store_query AS q WITH (NOLOCK)
   ON qt.query_text_id = q.query_text_id
   INNER JOIN sys.query_store_plan AS p WITH (NOLOCK)
   ON q.query_id = p.query_id
   INNER JOIN sys.query_store_runtime_stats AS rs WITH (NOLOCK)
   ON rs.plan_id = p.plan_id
   INNER JOIN sys.query_store_runtime_stats_interval AS rsi WITH (NOLOCK)
   ON rsi.runtime_stats_interval_id = rs.runtime_stats_interval_id
   WHERE rsi.start_time >= DATEADD(hour, -1, GETUTCDATE()) 
   AND rs.execution_type_desc = N'Regular'
   GROUP BY q.query_id),
OrderedDuration AS
(SELECT query_id, total_duration, number_of_plans, 
 ROW_NUMBER () OVER (ORDER BY total_duration DESC, query_id) AS RN
 FROM AggregatedDurationLastHour)
SELECT OBJECT_NAME(q.object_id) AS [Containing Object], qt.query_sql_text, 
od.total_duration AS [Total Duration (microsecs)], 
od.number_of_plans AS [Plan Count],
p.is_forced_plan, p.is_parallel_plan, p.is_trivial_plan,
q.query_parameterization_type_desc, p.[compatibility_level],
p.last_compile_start_time, q.last_execution_time,
CONVERT(xml, p.query_plan) AS query_plan_xml 
FROM OrderedDuration AS od 
INNER JOIN sys.query_store_query AS q WITH (NOLOCK)
ON q.query_id  = od.query_id
INNER JOIN sys.query_store_query_text AS qt WITH (NOLOCK)
ON q.query_text_id = qt.query_text_id
INNER JOIN sys.query_store_plan AS p WITH (NOLOCK)
ON q.query_id = p.query_id
WHERE od.RN <= 50 
ORDER BY total_duration DESC OPTION (RECOMPILE);
------

-- New for SQL Server 2016
-- Requires that QueryStore is enabled for this database

