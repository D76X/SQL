-- M2 - Database-level Configuration Queries ***********************************************************************
-- Glenn Berry


/*

Intorduction
https://app.pluralsight.com/ilx/video-courses/clips/734d08f0-adec-4f78-977e-2fde5d6de34c

Database Properties:
-1 Recovery model: full / simple
-2 Log resuse wait description
-3 Statistic Properties: 
-4 Delayed durability:
-5 Query store status: enabled / disabled

- database owner should be SA and not an individual login
- [log reuse wait description]
  and 
  [log used %] 
  are important to regularly monitor whether there are RUNAWAY TRANSACTIONS!

- Moreover [log reuse wait description] (LRWD) tells you WHY the log does not clear
- the [Compatibility Level] (CL) is important due to the New [Cardinality Estimator] (CARDE)
- [Statistics Properties] (STATP) are very important for [Query Performance] (QPERF)
- [Isolation Level Propertis] paly an important role in CUNCURRENCY+LOCKING+BLOCKING issues > (CLB) issues

The following should be checked as a standard and those with asterisks are very important:
Recovery Model 
State 
LRWD* (Log Reuse Wait Description)
DB CL (Compatibility Level)
Page Verify Option
IS AUTO UDATE STATS ASYNC ON
IS PARAMETERIZATION FORCE
SNAPSHOT ISOLATION STATE
READ COMMITED SNAPSHOT ISOLATION
AUTO CLOSE
AUTO SHRINK
TARGET RECOVERY TIME
CDC ENABLED
DELAYED DURABILITY
IS QUERY STORE ENABLED
RESULT SET CACHING
ACCELLERATED DB RECOVERY
TEMP DB SPILL TO REMOTE STORE
*/
-- Important database properties for current database   (Query 1) (Database Properties)
SELECT db.[name] AS [Database Name], db.recovery_model_desc AS [Recovery Model], 
db.state_desc, db.containment_desc, db.log_reuse_wait_desc AS [Log Reuse Wait Description], 
db.[compatibility_level] AS [DB Compatibility Level], 
db.is_mixed_page_allocation_on, db.page_verify_option_desc AS [Page Verify Option], 
db.is_auto_create_stats_on, db.is_auto_update_stats_on, db.is_auto_update_stats_async_on, 
db.is_parameterization_forced, db.snapshot_isolation_state_desc, db.is_read_committed_snapshot_on, 
db.is_auto_close_on, db.is_auto_shrink_on, 
db.target_recovery_time_in_seconds, db.is_cdc_enabled, db.is_memory_optimized_elevate_to_snapshot_on, 
db.delayed_durability_desc, db.is_auto_create_stats_incremental_on,
db.is_query_store_on, db.is_sync_with_backup, db.is_temporal_history_retention_enabled,
db.is_encrypted, is_result_set_caching_on, is_accelerated_database_recovery_on, is_tempdb_spill_to_remote_store  
FROM sys.databases AS db WITH (NOLOCK)
WHERE db.[name] <> N'master'
ORDER BY db.[name] OPTION (RECOMPILE);
------

/*
File Sizes and Space
https://app.pluralsight.com/ilx/video-courses/97737eb6-d4fe-4add-bf29-5c5c528ef0c3/8a4b1502-91c6-4c6f-8d24-80bf78bff8ba/8002a406-7480-42d0-9b3f-0de295fd21fa

- find the DB filenames and location
- find the total size of the DB files
- find the available space in each DB file
- filegroup & auto growth
- are all the files in the filegroup of the same size? > best practice
-----------------------------------------
- **SPOT RUNAWAY TRANSACTION LOGS** <<

if the log file is not cleared then it is 
likely there is a pending transaction that 
prevents it.
-----------------------------------------

*/
-- Things to look at:
-- What recovery model are you using?
-- What is the log reuse wait description?
-- What compatibility level is the database on? 
-- What is the Page Verify Option? (should be CHECKSUM)
-- Is Auto Update Statistics Asynchronously enabled?
-- Is Delayed Durability enabled?



-- Individual File Sizes and space available for current database  (Query 2) (File Sizes and Space)
SELECT f.name AS [File Name] , f.physical_name AS [Physical Name], 
CAST((f.size/128.0) AS DECIMAL(15,2)) AS [Total Size in MB],
CAST(f.size/128.0 - CAST(FILEPROPERTY(f.name, 'SpaceUsed') AS int)/128.0 AS DECIMAL(15,2)) 
AS [Available Space In MB], f.[file_id], fg.name AS [Filegroup Name],
f.is_percent_growth, f.growth, fg.is_default, fg.is_read_only, 
fg.is_autogrow_all_files
FROM sys.database_files AS f WITH (NOLOCK) 
LEFT OUTER JOIN sys.filegroups AS fg WITH (NOLOCK)
ON f.data_space_id = fg.data_space_id
ORDER BY f.[file_id] OPTION (RECOMPILE);
------

/*
DATA-SCOPED CONFIGURATIONS
https://app.pluralsight.com/ilx/video-courses/97737eb6-d4fe-4add-bf29-5c5c528ef0c3/8a4b1502-91c6-4c6f-8d24-80bf78bff8ba/5467ffbd-411b-49d7-abaf-ec16381a068e 

---------------------------------------------------------------
In Azure SQL Server you should be able to change these even at 
DB level rather than at server level. 
These options allow you ** to control the behavior of the DB.**
---------------------------------------------------------------

---------------------------------------------------------------
MAXDOP = Maximum Degree of Parallelism at the DB level
LCE = Legacy Carinality Estimator ?
Parameter Sniffing ?
QE hotfixes (Query Optimizer Hotfixes) ?
Identity Cache for Identity Columns ?

*/


-- Look at how large and how full the files are and where they are located
-- is_autogrow_all_files was new for SQL Server 2016. Equivalent to TF 1117 for user databases

-- SQL Server 2016: Changes in default behavior for autogrow and allocations for tempdb and user databases
-- http://bit.ly/2evRZSR

-- Get database scoped configuration values for current database (Query 3) (Database-scoped Configurations)
SELECT configuration_id, [name], [value] AS [value_for_primary]
FROM sys.database_scoped_configurations WITH (NOLOCK) OPTION (RECOMPILE);

------

/*
TABLE PROPERTIES:
https://app.pluralsight.com/ilx/video-courses/97737eb6-d4fe-4add-bf29-5c5c528ef0c3/8a4b1502-91c6-4c6f-8d24-80bf78bff8ba/5fed929e-c3af-4a3e-a9ef-c45f67d28290

- show useful property for each table
- show useful property for the inde for each table
- show the creation date for each table
_ is a MEMORY OPTIMIZED TABLE or a TEMPORAL TABLE ?
- the compression status for the index: page compressed | row compressed | no compression
- ** FIND CANDIDATES FOR ROW COMPRESSION **

*/
-- This lets you see the value of these new properties for the current database

-- Clear plan cache for current database
-- ALTER DATABASE SCOPED CONFIGURATION CLEAR PROCEDURE_CACHE;

-- ALTER DATABASE SCOPED CONFIGURATION (Transact-SQL)
-- https://bit.ly/2sOH7nb

-- Get some key table properties (Query 4) (Table Properties)
SELECT OBJECT_NAME(t.[object_id]) AS [ObjectName], p.[rows] AS [Table Rows], p.index_id, 
       p.data_compression_desc AS [Index Data Compression],
       t.create_date, t.lock_on_bulk_load, t.lock_escalation_desc, 
	   t.is_memory_optimized, t.durability_desc, 
	   t.temporal_type_desc
FROM sys.tables AS t WITH (NOLOCK)
INNER JOIN sys.partitions AS p WITH (NOLOCK)
ON t.[object_id] = p.[object_id]
WHERE OBJECT_NAME(t.[object_id]) NOT LIKE N'sys%'
ORDER BY OBJECT_NAME(t.[object_id]), p.index_id OPTION (RECOMPILE);
------

/*

*/
-- Gives you some good information about your tables
-- is_memory_optimized and durability_desc were new in SQL Server 2014
-- temporal_type_desc, is_remote_data_archive_enabled, is_external are new in SQL Server 2016

-- sys.tables (Transact-SQL)
-- https://bit.ly/2Gk7998




-- Get QueryStore Options for this database (Query 5) (QueryStore Options)
SELECT actual_state_desc, desired_state_desc,
       current_storage_size_mb, [max_storage_size_mb], 
	   query_capture_mode_desc, size_based_cleanup_mode_desc, 
	   wait_stats_capture_mode_desc, [flush_interval_seconds]
FROM sys.database_query_store_options WITH (NOLOCK) OPTION (RECOMPILE);
------

-- Added in SQL Server 2016
-- Requires that QueryStore is enabled for this database

-- Tuning Workload Performance with Query Store
-- https://bit.ly/1kHSl7w









-- Get database automatic tuning options (Query 6) (Automatic Tuning Options)
SELECT [name], desired_state_desc, actual_state_desc, reason_desc
FROM sys.database_automatic_tuning_options WITH (NOLOCK)
OPTION (RECOMPILE);
------ 

-- sys.database_automatic_tuning_options (Transact-SQL)
-- https://bit.ly/2FHhLkL


-- Examples of automatic tuning commands

-- Enable FORCE_LAST_GOOD_PLAN
ALTER DATABASE CURRENT SET AUTOMATIC_TUNING (FORCE_LAST_GOOD_PLAN = ON); 

-- Disable FORCE_LAST_GOOD_PLAN
ALTER DATABASE CURRENT SET AUTOMATIC_TUNING (FORCE_LAST_GOOD_PLAN = OFF);


-- Enable CREATE_INDEX
ALTER DATABASE CURRENT SET AUTOMATIC_TUNING (CREATE_INDEX = ON); 

-- Disable CREATE_INDEX
ALTER DATABASE CURRENT SET AUTOMATIC_TUNING (CREATE_INDEX = OFF); 


-- Enable DROP_INDEX
ALTER DATABASE CURRENT SET AUTOMATIC_TUNING (DROP_INDEX = ON);

-- Disable DROP_INDEX
ALTER DATABASE CURRENT SET AUTOMATIC_TUNING (DROP_INDEX = OFF); 






-- Enable MAINTAIN_INDEX (does not work in SSMS 18.2)
ALTER DATABASE CURRENT SET AUTOMATIC_TUNING (MAINTAIN_INDEX = ON); 