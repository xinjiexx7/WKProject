USE [master] -- change database name 
GO

/****** Object:  StoredProcedure [dbo].[usp_SQLhealthcheck_report]    Script Date: 02/02/2024 11:23:53 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE PROCEDURE [dbo].[usp_SQLhealthcheck_report] (  
  @MailProfile NVARCHAR(200),   
  @MailID NVARCHAR(2000),  
  @Server VARCHAR(100) = NULL)  
AS  
BEGIN  
SET NOCOUNT ON;  
SET ARITHABORT ON;  
  
DECLARE @ServerName VARCHAR(100);  
--SET @ServerName = ISNULL(@Server,@@SERVERNAME); 
SET @ServerName = ISNULL(@Server,CAST(SERVERPROPERTY('MACHINENAME') AS VARCHAR(MAX)));  

  
/*************************************************************/  
/****************** Server Reboot Details ********************/  
/*************************************************************/  
  
CREATE TABLE #RebootDetails                                
(                                
 LastRecycle datetime,                                
 CurrentDate datetime,                                
 UpTimeInDays varchar(100)                          
)                        
Insert into #RebootDetails          
SELECT sqlserver_start_time 'Last Recycle',GetDate() 'Current Date', DATEDIFF(DD, sqlserver_start_time,GETDATE())'Up Time in Days'  
FROM sys.dm_os_sys_info;  
  
/*************************************************************/  
/****************** Current Blocking Details *****************/  
/*************************************************************/  
CREATE TABLE #BlkProcesses                                
(                                
 spid  varchar(5),                                
 Blkspid  varchar(5),                                
 PrgName  varchar(100),          
 LoginName varchar(100),                                
 ObjName  varchar(100),                                
 Query  varchar(255)                                 
)    
insert into #BlkProcesses  
SELECT s.spid, BlockingSPID = s.blocked, substring(s.program_name,1,99), SUBSTRING(s.loginame,1,99),           
   ObjectName = substring( OBJECT_NAME(objectid, s.dbid),1,99), Definition = CAST(text AS VARCHAR(255))          
FROM  sys.sysprocesses s          
CROSS APPLY sys.dm_exec_sql_text (sql_handle)          
WHERE        s.spid > 50  AND s.blocked > 0   
  
  
/*************************************************************/  
/****************** Errors audit for last 4 Days *************/  
/*************************************************************/  
  
CREATE TABLE #ErrorLogInfo                                
(                                
 LogDate  datetime,  
 processinfo varchar(max),                                
 LogInfo  varchar(max)                                 
)      
  
DECLARE @A VARCHAR(10), @B VARCHAR(10);  
SELECT @A = CONVERT(VARCHAR(20),GETDATE()-4,112);  
SELECT @B = CONVERT(VARCHAR(20),GETDATE()+1,112);  
Insert into #ErrorLogInfo  
EXEC xp_ReadErrorLog 0, 1,N'Login', N'Failed', @A,@B,'DESC';  


  
/***********************************************************/  
/************* Windows Disk Space Details ******************/  
/***********************************************************/  

CREATE TABLE #FreeSpace (volume_mount_point CHAR(20), file_system_type char(20),logical_volume_name char(20),
 [Total Size (GB)] DECIMAL(16,2), [Available Size (GB)] DECIMAL(16,2), [Space Free %] DECIMAL(16,2) )
--INSERT INTO #FreeSpace (DName,Free_MB) EXEC XP_FIXEDDRIVES;
--UPDATE #FreeSpace SET Free_GB = CAST(Free_MB / 1024.00 AS DECIMAL(16,2));  
  INSERT INTO #FreeSpace 
-----Checks only drive space for drives that hold datafiles
           ----Only works in Slq Server 2008 R2 and up
            SELECT DISTINCT vs.volume_mount_point,vs.file_system_type,
vs.logical_volume_name,CONVERT(DECIMAL(18,2),vs.total_bytes/1073741824.0)AS [Total Size (GB)],
CONVERT(DECIMAL(18,2),vs.available_bytes/1073741824.0)AS [Available Size (GB)],
CONVERT(DECIMAL(18,2),vs.available_bytes* 1. /vs.total_bytes* 100.)AS [Space Free %]
FROM sys.master_files AS f WITH (NOLOCK)
CROSS  APPLY sys.dm_os_volume_stats(f.database_id, f.[file_id]) AS vs 
ORDER BY vs.volume_mount_point OPTION (RECOMPILE);

/*************************************************************/  
/************* SQL Server CPU Pressure******************/  
/*************************************************************/  


Create table #CPUPre
(
[%signal (cpu) waits] VARCHAR(100) ,
[%signal (cpu) waits Optimal Value] VARCHAR(100),
[%resource waits] VARCHAR(100)
)
insert into #CPUPre 

SELECT convert(VARCHAR(100),100.0 * SUM(signal_wait_time_ms) / SUM(wait_time_ms) ) AS [%signal (cpu) waits],
 'If % Signal Wait > 25% then we have some CPU Pressure' as [%signal (cpu) waits Optimal Value],
convert (VARCHAR(100),100.0 * SUM(wait_time_ms - signal_wait_time_ms) / SUM(wait_time_ms))
AS [%resource waits]
FROM sys.dm_os_wait_stats OPTION (RECOMPILE);


/*************************************************************/  
/************* SQL Server CPU Usage Details ******************/  
/*************************************************************/  
SET ansi_warnings ON
Create table #CPU(               
servername varchar(100),                           
EventTime2 datetime,                            
SQLProcessUtilization varchar(50),                           
SystemIdle varchar(50),  
OtherProcessUtilization varchar(50),  
load_date datetime                            
)      
DECLARE @ts BIGINT;  DECLARE @lastNmin TINYINT;  
SET @lastNmin = 240;  
SELECT @ts =(SELECT cpu_ticks/(cpu_ticks/ms_ticks) FROM sys.dm_os_sys_info);   
insert into #CPU  
SELECT TOP 20 * FROM (  
SELECT TOP(@lastNmin)  
  @ServerName AS 'ServerName',  
  DATEADD(ms,-1 *(@ts - [timestamp]),GETDATE())AS [Event_Time],   
  SQLProcessUtilization AS [SQLServer_CPU_Utilization],   
  SystemIdle AS [System_Idle_Process],   
  100 - SystemIdle - SQLProcessUtilization AS [Other_Process_CPU_Utilization],  
  GETDATE() AS 'LoadDate'  
FROM (SELECT record.value('(./Record/@id)[1]','int')AS record_id,   
record.value('(./Record/SchedulerMonitorEvent/SystemHealth/SystemIdle)[1]','int')AS [SystemIdle],   
record.value('(./Record/SchedulerMonitorEvent/SystemHealth/ProcessUtilization)[1]','int')AS [SQLProcessUtilization],   
[timestamp]        
FROM (SELECT[timestamp], convert(xml, record) AS [record]               
FROM sys.dm_os_ring_buffers               
WHERE ring_buffer_type =N'RING_BUFFER_SCHEDULER_MONITOR'AND record LIKE'%%')AS x )AS y   
ORDER BY SystemIdle ASC) d  
OPTION (RECOMPILE)
  
/*************************************************************/  
/************* SQL Server Memory Usage Details ***************/  
/*************************************************************/  
  
--CREATE TABLE #Memory_BPool (  
--BPool_Committed_MB VARCHAR(50),  
--BPool_Commit_Tgt_MB VARCHAR(50),  
--BPool_Visible_MB VARCHAR(50));  
  
---- SQL server 2008 / 2008 R2  
--INSERT INTO #Memory_BPool    
--SELECT  
--     (bpool_committed*8)/1024.0 as BPool_Committed_MB,  
--     (bpool_commit_target*8)/1024.0 as BPool_Commit_Tgt_MB,  
--     (bpool_visible*8)/1024.0 as BPool_Visible_MB  
--FROM sys.dm_os_sys_info;  
/****  
-- SQL server 2012 / 2014 / 2016  
INSERT INTO #Memory_BPool   
SELECT  
      (committed_kb)/1024.0 as BPool_Committed_MB,  
      (committed_target_kb)/1024.0 as BPool_Commit_Tgt_MB,  
      (visible_target_kb)/1024.0 as BPool_Visible_MB  
FROM  sys.dm_os_sys_info;  
****/  
CREATE TABLE #Memory_sys (  
total_physical_memory_mb VARCHAR(50),  
available_physical_memory_mb VARCHAR(50),  
total_page_file_mb VARCHAR(50),  
available_page_file_mb VARCHAR(50),  
Percentage_Used VARCHAR(50),  
system_memory_state_desc VARCHAR(50));  
  
INSERT INTO #Memory_sys  
select  
      total_physical_memory_kb/1024 AS total_physical_memory_mb,  
      available_physical_memory_kb/1024 AS available_physical_memory_mb,  
      total_page_file_kb/1024 AS total_page_file_mb,  
      available_page_file_kb/1024 AS available_page_file_mb,  
      100 - (100 * CAST(available_physical_memory_kb AS DECIMAL(18,3))/CAST(total_physical_memory_kb AS DECIMAL(18,3)))   
      AS 'Percentage_Used',  
      system_memory_state_desc  
from  sys.dm_os_sys_memory
OPTION (RECOMPILE);  
  
  
CREATE TABLE #Memory_process(  
physical_memory_in_use_GB VARCHAR(50),  
locked_page_allocations_GB VARCHAR(50),  
virtual_address_space_committed_GB VARCHAR(50),  
available_commit_limit_GB VARCHAR(50),  
page_fault_count VARCHAR(50))  
  
INSERT INTO #Memory_process  
select  
      physical_memory_in_use_kb/1048576.0 AS 'physical_memory_in_use(GB)',  
      locked_page_allocations_kb/1048576.0 AS 'locked_page_allocations(GB)',  
      virtual_address_space_committed_kb/1048576.0 AS 'virtual_address_space_committed(GB)',  
      available_commit_limit_kb/1048576.0 AS 'available_commit_limit(GB)',  
      page_fault_count as 'page_fault_count'  
from  sys.dm_os_process_memory
OPTION (RECOMPILE);  
  
  
CREATE TABLE #Memory(  
Parameter VARCHAR(200),  
Value VARCHAR(100));  
  
INSERT INTO #Memory   
--SELECT 'BPool_Committed_MB',BPool_Committed_MB FROM #Memory_BPool  
--UNION  
--SELECT 'BPool_Commit_Tgt_MB', BPool_Commit_Tgt_MB FROM #Memory_BPool  
--UNION   
--SELECT 'BPool_Visible_MB', BPool_Visible_MB FROM #Memory_BPool  
--UNION  
SELECT 'total_physical_memory_mb',total_physical_memory_mb FROM #Memory_sys  
UNION  
SELECT 'available_physical_memory_mb',available_physical_memory_mb FROM #Memory_sys  
UNION  
SELECT 'total_page_file_mb',total_page_file_mb FROM #Memory_sys  
UNION  
SELECT 'available_page_file_mb',available_page_file_mb FROM #Memory_sys  
UNION  
SELECT 'Percentage_Used',Percentage_Used FROM #Memory_sys  
UNION  
SELECT 'system_memory_state_desc',system_memory_state_desc FROM #Memory_sys  
UNION  
SELECT 'physical_memory_in_use_GB',physical_memory_in_use_GB FROM #Memory_process  
UNION  
SELECT 'locked_page_allocations_GB',locked_page_allocations_GB FROM #Memory_process  
UNION  
SELECT 'virtual_address_space_committed_GB',virtual_address_space_committed_GB FROM #Memory_process  
UNION  
SELECT 'available_commit_limit_GB',available_commit_limit_GB FROM #Memory_process  
UNION  
SELECT 'page_fault_count',page_fault_count FROM #Memory_process;  
  
  
/******************************************************************/  
/*************** Performance Counter Details **********************/  
/******************************************************************/  
  
CREATE TABLE #PerfCntr_Data(  
Parameter VARCHAR(300),  
Value VARCHAR(100));  
  
-- Get size of SQL Server Page in bytes  
DECLARE @pg_size INT, @Instancename varchar(50)  
SELECT @pg_size = low from master..spt_values where number = 1 and type = 'E'  
  
-- Extract perfmon counters to a temporary table  
IF OBJECT_ID('tempdb..#perfmon_counters') is not null DROP TABLE #perfmon_counters  
SELECT * INTO #perfmon_counters FROM sys.dm_os_performance_counters;  
  
-- Get SQL Server instance name as it require for capturing Buffer Cache hit Ratio  
SELECT  @Instancename = LEFT([object_name], (CHARINDEX(':',[object_name])))   
FROM    #perfmon_counters   
WHERE   counter_name = 'Buffer cache hit ratio';  
  
INSERT INTO #PerfCntr_Data  
SELECT CONVERT(VARCHAR(300),Cntr) AS Parameter, CONVERT(VARCHAR(100),Value) AS Value  
FROM  
(  
SELECT  'Total Server Memory (GB)' as Cntr,  
        (cntr_value/1048576.0) AS Value   
FROM    #perfmon_counters   
WHERE   counter_name = 'Total Server Memory (KB)'  
UNION ALL  
SELECT  'Target Server Memory (GB)',   
        (cntr_value/1048576.0)   
FROM    #perfmon_counters   
WHERE   counter_name = 'Target Server Memory (KB)'  
UNION ALL  
SELECT  'Connection Memory (MB)',   
        (cntr_value/1024.0)   
FROM    #perfmon_counters   
WHERE   counter_name = 'Connection Memory (KB)'  
UNION ALL  
SELECT  'Lock Memory (MB)',   
        (cntr_value/1024.0)   
FROM    #perfmon_counters   
WHERE   counter_name = 'Lock Memory (KB)'  
UNION ALL  
SELECT  'SQL Cache Memory (MB)',   
        (cntr_value/1024.0)   
FROM    #perfmon_counters   
WHERE   counter_name = 'SQL Cache Memory (KB)'  
UNION ALL  
SELECT  'Optimizer Memory (MB)',   
        (cntr_value/1024.0)   
FROM    #perfmon_counters   
WHERE   counter_name = 'Optimizer Memory (KB) '  
UNION ALL  
SELECT  'Granted Workspace Memory (MB)',   
        (cntr_value/1024.0)   
FROM    #perfmon_counters   
WHERE   counter_name = 'Granted Workspace Memory (KB) '  
UNION ALL  
SELECT  'Cursor memory usage (MB)',   
        (cntr_value/1024.0)   
FROM    #perfmon_counters   
WHERE   counter_name = 'Cursor memory usage' and instance_name = '_Total'  
UNION ALL  
SELECT  'Total pages Size (MB)',   
        (cntr_value*@pg_size)/1048576.0   
FROM    #perfmon_counters   
WHERE   object_name= @Instancename+'Buffer Manager'   
        and counter_name = 'Total pages'  
UNION ALL  
SELECT  'Database pages (MB)',   
        (cntr_value*@pg_size)/1048576.0   
FROM    #perfmon_counters   
WHERE   object_name = @Instancename+'Buffer Manager' and counter_name = 'Database pages'  
UNION ALL  
SELECT  'Free pages (MB)',   
        (cntr_value*@pg_size)/1048576.0   
FROM    #perfmon_counters   
WHERE   object_name = @Instancename+'Buffer Manager'   
        and counter_name = 'Free pages'  
UNION ALL  
SELECT  'Reserved pages (MB)',   
        (cntr_value*@pg_size)/1048576.0   
FROM    #perfmon_counters   
WHERE   object_name=@Instancename+'Buffer Manager'   
        and counter_name = 'Reserved pages'  
UNION ALL  
SELECT  'Stolen pages (MB)',   
        (cntr_value*@pg_size)/1048576.0   
FROM    #perfmon_counters   
WHERE   object_name=@Instancename+'Buffer Manager'   
        and counter_name = 'Stolen pages'  
UNION ALL  
SELECT  'Cache Pages (MB)',   
        (cntr_value*@pg_size)/1048576.0   
FROM    #perfmon_counters   
WHERE   object_name=@Instancename+'Plan Cache'   
        and counter_name = 'Cache Pages' and instance_name = '_Total'  
UNION ALL  
SELECT  'Page Life Expectency in seconds',  
        cntr_value   
FROM    #perfmon_counters   
WHERE   object_name=@Instancename+'Buffer Manager'   
        and counter_name = 'Page life expectancy'  
UNION ALL  
SELECT  'Free list stalls/sec',  
        cntr_value   
FROM    #perfmon_counters   
WHERE   object_name=@Instancename+'Buffer Manager'   
        and counter_name = 'Free list stalls/sec'  
UNION ALL  
SELECT  'Checkpoint pages/sec',  
        cntr_value   
FROM    #perfmon_counters   
WHERE   object_name=@Instancename+'Buffer Manager'   
        and counter_name = 'Checkpoint pages/sec'  
UNION ALL  
SELECT  'Lazy writes/sec',  
        cntr_value   
FROM    #perfmon_counters   
WHERE   object_name=@Instancename+'Buffer Manager'   
        and counter_name = 'Lazy writes/sec'  
UNION ALL  
SELECT  'Memory Grants Pending',  
        cntr_value   
FROM    #perfmon_counters   
WHERE   object_name=@Instancename+'Memory Manager'   
        and counter_name = 'Memory Grants Pending'  
UNION ALL  
SELECT  'Memory Grants Outstanding',  
        cntr_value   
FROM    #perfmon_counters   
WHERE   object_name=@Instancename+'Memory Manager'   
        and counter_name = 'Memory Grants Outstanding'  
UNION ALL  
SELECT  'process_physical_memory_low',  
        process_physical_memory_low   
FROM    sys.dm_os_process_memory WITH (NOLOCK)  
UNION ALL  
SELECT  'process_virtual_memory_low',  
        process_virtual_memory_low   
FROM    sys.dm_os_process_memory WITH (NOLOCK)  
UNION ALL  
SELECT  'Max_Server_Memory (MB)' ,  
        [value_in_use]   
FROM    sys.configurations   
WHERE   [name] = 'max server memory (MB)'  
UNION ALL  
SELECT  'Min_Server_Memory (MB)' ,  
        [value_in_use]   
FROM    sys.configurations   
WHERE   [name] = 'min server memory (MB)'  
UNION ALL  
SELECT  'BufferCacheHitRatio',  
        (a.cntr_value * 1.0 / b.cntr_value) * 100.0   
FROM    sys.dm_os_performance_counters a  
        JOIN (SELECT cntr_value,OBJECT_NAME FROM sys.dm_os_performance_counters  
              WHERE counter_name = 'Buffer cache hit ratio base' AND   
                    OBJECT_NAME = @Instancename+'Buffer Manager') b ON   
                    a.OBJECT_NAME = b.OBJECT_NAME WHERE a.counter_name = 'Buffer cache hit ratio'   
                    AND a.OBJECT_NAME = @Instancename+'Buffer Manager') AS P;  
  
/******************************************************************/  
/*************** Job Failure Report ***************************/  
/******************************************************************/  
  
  create table #jobfail
([Job Name] nvarchar(250),
step_id int,
[step Name] nvarchar (250),
[Error Message] nvarchar(max))
insert into #jobfail
SELECT 
SUBSTRING(T2.name,1,40) AS 'Job Name',
T1.step_id AS 'Step_id',
T1.step_name  AS 'Step Name',
LEFT(T1.[message],500) AS 'Error Message'
FROM msdb..sysjobhistory T1
JOIN msdb..sysjobs  T2
ON T1.job_id = T2.job_id
WHERE  T1.run_status NOT IN (1,4)
AND T1.step_id != 0
AND run_date >= CONVERT(char(8), (select dateadd (day,(-1), getdate())), 112) OPTION (RECOMPILE)

/******************************************************************/  
/*************** SQL Server Agent Status ***************************/  
/******************************************************************/  
Create table #AgentStatus
([Service Name] varchar(max),
[Start Mode] varchar(100),
[Status] varchar(100),
[Straing Since] datetimeoffset(7),
[Account] varchar(200),
[Location] varchar(256)
,[ID] int
)

insert into #AgentStatus
SELECT  DSS.servicename,
        DSS.startup_type_desc as [Start Mode],
        DSS.status_desc as [Status],
         DSS.last_startup_time as [Straing Since],
        DSS.service_account as [Account],
        --DSS.is_clustered,
        --DSS.cluster_nodename,
        DSS.filename as [Location],
        --DSS.startup_type,
        --DSS.status,
        DSS.process_id [ID]
FROM    sys.dm_server_services AS DSS
OPTION (RECOMPILE);

/******************************************************************/  
/*************** Database Backup Report ***************************/  
/******************************************************************/  
  
CREATE TABLE #Backup_Report(  
[DB Name] varchar(100),
[Recovery Model] varchar(20),
[Online/Offline] varchar(20),
[Log Use Description] varchar(40),
[Last Full Backup] datetime,
[Last Log Backup] datetime);  
  
INSERT INTO #Backup_Report  
--Databases with data backup over 48 hours old   
SELECT  name as 'DB Name',
        Recovery_model_desc as  'Recovery Model',
		state_desc as 'Online/Offline',
		log_reuse_wait_desc AS 'Log Use Description',
              d AS 'Last Full Backup',
              --i AS 'Last Differential Backup',
              l AS 'Last Log Backup'
FROM  ( SELECT db.name,
                                   Db.recovery_model_desc,
                                   type, state_desc,
                                    backup_finish_date,
									db.log_reuse_wait_desc
                          FROM master.sys.databases db
                                         LEFT OUTER JOIN msdb.dbo.backupset a 
                                         ON a.database_name =db.name
                                         ) AS Sourcetable 
PIVOT
      (MAX( backup_finish_date) For type IN (D,I,L)) AS MostRecentBackup
WHERE Name not in ('tempdb')
Order BY D,I,L
 OPTION (RECOMPILE);
  
  
  
       
/*************************************************************/  
/****************** Connection Details ***********************/  
/*************************************************************/  
  
-- Number of connection on the instance grouped by hostnames  
Create table #ConnInfo(               
Hostname varchar(100),                           
NumberOfconn varchar(10)                          
)    
insert into #ConnInfo  
SELECT  Case when len(hostname)=0 Then 'Internal Process' Else hostname END,count(*)NumberOfconnections   
FROM sys.sysprocesses  
GROUP BY hostname  
  
  
/*************************************************************/  
/************** Currently Running Jobs Info ******************/  
/*************************************************************/  
Create table #JobInfo(               
spid varchar(10),                           
lastwaittype varchar(100),                           
dbname varchar(100),                           
login_time varchar(100),                           
status varchar(100),                           
opentran varchar(100),                           
hostname varchar(100),                          
JobName varchar(100),                          
command nvarchar(2000),  
domain varchar(100),   
loginname varchar(100)     
)   
insert into #JobInfo  
SELECT  distinct p.spid,p.lastwaittype,DB_NAME(p.dbid),p.login_time,p.status,p.open_tran,p.hostname,J.name,  
p.cmd,p.nt_domain,p.loginame  
FROM master..sysprocesses p  
INNER JOIN msdb..sysjobs j ON   
substring(left(j.job_id,8),7,2) + substring(left(j.job_id,8),5,2) + substring(left(j.job_id,8),3,2) + substring(left(j.job_id,8),1,2) = substring(p.program_name, 32, 8)   
Inner join msdb..sysjobactivity sj on j.job_id=sj.job_id  
WHERE program_name like'SQLAgent - TSQL JobStep (Job %' and sj.stop_execution_date is null  OPTION (RECOMPILE)
  
/*************************************************************/  
/****************** Tempdb File Info *************************/  
/*************************************************************/  
-- tempdb file usage  
Create table #tempdbfileusage(               
servername varchar(100),                           
databasename varchar(100),                           
filename varchar(100),                           
physicalName varchar(100),                           
filesizeMB varchar(100),                           
availableSpaceMB varchar(100),                           
percentfull varchar(100)   
)   
  
DECLARE @TEMPDBSQL NVARCHAR(4000);  
SET @TEMPDBSQL = ' USE Tempdb;  
SELECT  CONVERT(VARCHAR(100), @@SERVERNAME) AS [server_name]  
                ,db.name AS [database_name]  
                ,mf.[name] AS [file_logical_name]  
                ,mf.[filename] AS[file_physical_name]  
                ,convert(FLOAT, mf.[size]/128) AS [file_size_mb]               
                ,convert(FLOAT, (mf.[size]/128 - (CAST(FILEPROPERTY(mf.[name], ''SpaceUsed'') AS int)/128))) as [available_space_mb]  
                ,convert(DECIMAL(38,2), (CAST(FILEPROPERTY(mf.[name], ''SpaceUsed'') AS int)/128.0)/(mf.[size]/128.0))*100 as [percent_full]      
FROM   tempdb.dbo.sysfiles mf  
JOIN      master..sysdatabases db  
ON         db.dbid = db_id()';  
--PRINT @TEMPDBSQL;  
insert into #tempdbfileusage  
EXEC SP_EXECUTESQL @TEMPDBSQL;  
  
  
/*************************************************************/  
/****************** Database Log Usage ***********************/  
/*************************************************************/  
CREATE TABLE #LogSpace(  
DBName VARCHAR(100),  
LogSize VARCHAR(50),  
LogSpaceUsed_Percent VARCHAR(100),   
LStatus CHAR(1));  
  
INSERT INTO #LogSpace  
EXEC ('DBCC SQLPERF(LOGSPACE) WITH NO_INFOMSGS;');  
  
/********************************************************************/  
/****************** Long Running Transactions ***********************/  
/********************************************************************/  
  
CREATE TABLE #OpenTran_Detail(  
 [SPID] [varchar](20) NULL,  
 [TranID] [varchar](50) NULL,  
 [User_Tran] [varchar](5) NOT NULL,  
 [DBName] [nvarchar](250) NULL,  
 [Login_Time] [varchar](60) NULL,  
 [Duration] [varchar](20) NULL,  
 [Last_Batch] [varchar](200) NULL,  
 [Status] [nvarchar](50) NULL,  
 [LoginName] [nvarchar](250) NULL,  
 [HostName] [nvarchar](250) NULL,  
 [ProgramName] [nvarchar](250) NULL,  
 [CMD] [nvarchar](50) NULL,  
 [SQL] [nvarchar](max) NULL,  
 [Blocked] [varchar](6) NULL  
);  
  
  
  
;WITH OpenTRAN AS  
(SELECT session_id,transaction_id,is_user_transaction   
FROM sys.dm_tran_session_transactions)   
INSERT INTO #OpenTran_Detail  
SELECT        
 LTRIM(RTRIM(OT.session_id)) AS 'SPID',  
 LTRIM(RTRIM(OT.transaction_id)) AS 'TranID',  
 CASE WHEN OT.is_user_transaction = '1' THEN 'Yes' ELSE 'No' END AS 'User_Tran',  
    db_name(LTRIM(RTRIM(s.dbid)))DBName,  
    LTRIM(RTRIM(login_time)) AS 'Login_Time',   
 DATEDIFF(MINUTE,login_time,GETDATE()) AS 'Duration',  
 LTRIM(RTRIM(last_batch)) AS 'Last_Batch',  
    LTRIM(RTRIM(status)) AS 'Status',  
 LTRIM(RTRIM(loginame)) AS 'LoginName',   
    LTRIM(RTRIM(hostname)) AS 'HostName',   
    LTRIM(RTRIM(program_name)) AS 'ProgramName',  
    LTRIM(RTRIM(cmd)) AS 'CMD',  
 LTRIM(RTRIM(a.text)) AS 'SQL',  
    LTRIM(RTRIM(blocked)) AS 'Blocked'  
FROM sys.sysprocesses AS s  
CROSS APPLY sys.dm_exec_sql_text(s.sql_handle)a  
INNER JOIN OpenTRAN AS OT ON OT.session_id = s.spid   
WHERE s.spid <> @@spid AND s.dbid>4 OPTION (RECOMPILE);  
  
/*************************************************************/  
/****************** HTML Preparation *************************/  
/*************************************************************/  
  
DECLARE @TableHTML  VARCHAR(MAX),                                    
  @StrSubject VARCHAR(100),                                    
  @Oriserver VARCHAR(100),                                
  @Version VARCHAR(250),                                
  @Edition VARCHAR(100),                                
  @ISClustered VARCHAR(100),                                
  @SP VARCHAR(100),                                
  @ServerCollation VARCHAR(100),                                
  @SingleUser VARCHAR(5),                                
  @LicenseType VARCHAR(100),                                
  @Cnt int,           
  @URL varchar(1000),                                
  @Str varchar(1000),                                
  @NoofCriErrors varchar(3)       
  
-- Variable Assignment              
  
SELECT @Version = @@version                                
SELECT @Edition = CONVERT(VARCHAR(100), serverproperty('Edition'))                                
SET @Cnt = 0                                
IF serverproperty('IsClustered') = 0                                 
BEGIN                                
 SELECT @ISClustered = 'No'                                
END                                
ELSE        
BEGIN                                
 SELECT @ISClustered = 'YES'                                
END                                
SELECT @SP = CONVERT(VARCHAR(100), SERVERPROPERTY ('productlevel'))                                
SELECT @ServerCollation = CONVERT(VARCHAR(100), SERVERPROPERTY ('Collation'))                                 
SELECT @LicenseType = CONVERT(VARCHAR(100), SERVERPROPERTY ('LicenseType'))                                 
SELECT @SingleUser = CASE SERVERPROPERTY ('IsSingleUser')                                
      WHEN 1 THEN 'Yes'                                
      WHEN 0 THEN 'No'                                
      ELSE                                
      'null' END                                
SELECT @OriServer = CONVERT(VARCHAR(50), SERVERPROPERTY('MachineName'))                                  
SELECT @strSubject = 'Database Server Health Check ('+ ISNULL(CAST(SERVERPROPERTY('MACHINENAME') AS VARCHAR(MAX)),@@SERVERNAME )+ ')'                                    
   
  
  
SET @TableHTML =                                    
 '<font face="Verdana" size="4">Health Check</font>                                  
 <table border="1" cellpadding="0" cellspacing="0" style="border-collapse: collapse" bordercolor="#111111" width="47%" id="AutoNumber1" height="50">                                  
 <tr>                                  
 <td width="39%" height="22" bgcolor="#000080"><b>                           
 <font face="Verdana" size="2" color="#FFFFFF">Server Name</font></b></td>                                  
 </tr>                                  
 <tr>                                  
 <td width="39%" height="27"><font face="Verdana" size="2">' + @ServerName +'</font></td>                                  
 </tr>                                  
 </table>                                 
 <table id="AutoNumber1" style="BORDER-COLLAPSE: collapse" borderColor="#111111" height="40" cellSpacing="0" cellPadding="0" width="933" border="1">                                
 <tr>                                
 <td align="Center" width="50%" bgColor="#000080" height="15"><b>                                
 <font face="Verdana" color="#ffffff" size="1">Version</font></b></td>                                
 <td align="Center" width="17%" bgColor="#000080" height="15"><b>                                
 <font face="Verdana" color="#ffffff" size="1">Edition</font></b></td>                                
 <td align="Center" width="35%" bgColor="#000080" height="15"><b>                                
 <font face="Verdana" color="#ffffff" size="1">Service Pack</font></b></td>                                
 <td align="Center" width="60%" bgColor="#000080" height="15"><b>                                
 <font face="Verdana" color="#ffffff" size="1">Collation</font></b></td>                                
 <td align="Center" width="93%" bgColor="#000080" height="15"><b>                                
 <font face="Verdana" color="#ffffff" size="1">LicenseType</font></b></td>                                
 <td align="Center" width="40%" bgColor="#000080" height="15"><b>                                
<font face="Verdana" color="#ffffff" size="1">SingleUser</font></b></td>                                
 <td align="Center" width="93%" bgColor="#000080" height="15"><b>                                
 <font face="Verdana" color="#ffffff" size="1">Clustered</font></b></td>                                
 </tr>                                
 <tr>                                
 <td align="Center" width="50%" height="27"><font face="Verdana" size="1">'+@version +'</font></td>                                
 <td align="Center" width="17%" height="27"><font face="Verdana" size="1">'+@edition+'</font></td>                                
 <td align="Center" width="18%" height="27"><font face="Verdana" size="1">'+@SP+'</font></td>                                
 <td align="Center" width="17%" height="27"><font face="Verdana" size="1">'+@ServerCollation+'</font></td>                                
 <td align="Center" width="25%" height="27"><font face="Verdana" size="1">'+@LicenseType+'</font></td>                                
 <td align="Center" width="25%" height="27"><font face="Verdana" size="1">'+@SingleUser+'</font></td>                                
 <td align="Center" width="93%" height="27"><font face="Verdana" size="1">'+@isclustered+'</font></td>                                
 </tr>                                
 </table>                   
     
 <p style="margin-top: 0; margin-bottom: 0">&nbsp;</p>                                
 <font face="Verdana" size="4">SQL ErrorLog Summary in Last 4 Days</font>' +                                    
 '<table style="BORDER-COLLAPSE: collapse" borderColor="#111111" cellPadding="0" width="933" bgColor="#ffffff" borderColorLight="#000000" border="1">                                  
 <tr>                                
 <td width="20%" bgColor="#000080" height="15"><b>                        
 <font face="Verdana" color="#ffffff" size="1">Number of Critical Errors</font></b></td>                                
 </tr>                                
 </table>                                
 <table style="BORDER-COLLAPSE: collapse" borderColor="#111111" cellPadding="0" width="933" bgColor="#ffffff" borderColorLight="#000000" border="1">                                  
 <tr>                                
 <td width="15%" bgColor="#000080" height="15"><b>                                
 <font face="Verdana" color="#ffffff" size="1">Error Log DateTime</font></b></td>  
  <td width="15%" bgColor="#000080" height="15"><b>                                
 <font face="Verdana" color="#ffffff" size="1">Error processinfo</font></b></td>                     
 <td width="70%" bgColor="#000080" height="15"><b>                                
 <font face="Verdana" color="#ffffff" size="1">Error Message</font></b></td>                                
 </tr>'                                
                
  
SELECT                                 
 @TableHTML = @TableHTML + '<tr>                                
 <td width="10%" height="27"><font face="Verdana" size="1">'+ ISNULL(CONVERT(VARCHAR(50),LogDate ),'') +'</font></td> 
 <td width="10%" height="27"><font face="Verdana" size="1">'+ ISNULL(CONVERT(VARCHAR(max),processinfo ),'') +'</font></td>                              
 <td width="80%" height="27"><font face="Verdana" size="1">'+ISNULL(CONVERT(VARCHAR(max),LogInfo ),'')+'</font></td>                                
 </tr>'                                
FROM  #ErrorLogInfo   ORDER BY      LogDate DESC   
  
  
 SELECT                                   
 @TableHTML = @TableHTML +                                     
 '</table>                                  
 <p style="margin-top: 1; margin-bottom: 0">&nbsp;</p>                                  
 <font face="Verdana" size="4">Instance last Recycled</font>                                  
 <table style="BORDER-COLLAPSE: collapse" borderColor="#111111" cellPadding="0" width="933" bgColor="#ffffff" borderColorLight="#000000" border="1">                                      
 <tr>                                      
 <th align="Center" width="50" bgColor="#000080">                                      
  <font face="Verdana" size="1" color="#FFFFFF">Last Recycle</font></th>                                      
 <th align="Center" width="50" bgColor="#000080">                                      
  <font face="Verdana" size="1" color="#FFFFFF">Current DateTime</font></th>                                      
 <th align="Center" width="50" bgColor="#000080">                                   
 <font face="Verdana" size="1" color="#FFFFFF">UpTimeInDays</font></th>                                      
  </tr>'                                  
                                  
SELECT                                   
 @TableHTML =  @TableHTML +                                       
 '<tr>                                    
 <td align="Center"><font face="Verdana" size="1">' + ISNULL(CONVERT(VARCHAR(100), LastRecycle ), '')  +'</font></td>' +                                        
 '<td align="Center"><font face="Verdana" size="1">' + ISNULL(CONVERT(VARCHAR(100),  CurrentDate ), '')  +'</font></td>' +                                   
 '<td align="Center"><font face="Verdana" size="1">' + ISNULL(CONVERT(VARCHAR(100),  UpTimeInDays ), '')  +'</font></td>' +                                        
  '</tr>'                                  
FROM                                   
 #RebootDetails   
  

/***** Free Disk Space Report ****/  
SELECT                                   
 @TableHTML =  @TableHTML +                              
 '</table>                                  
 <p style="margin-top: 1; margin-bottom: 0">&nbsp;</p>                                  
 <font face="Verdana" size="4">Disk Space Report</font>                                  
 <table id="AutoNumber1" style="BORDER-COLLAPSE: collapse" borderColor="#111111" height="40" cellSpacing="0" cellPadding="0" width="933" border="1">                                  
   <tr>                
 <th align="Center" width="136" bgColor="#000080">                                    
 <font face="Verdana" size="1" color="#FFFFFF">volume_mount_point</font></th>                              
  <th align="Center" width="200" bgColor="#000080"> 
 <font face="Verdana" size="1" color="#FFFFFF">file_system_type </font></th> 
 <th align="Center" width="200" bgColor="#000080"> 
 <font face="Verdana" size="1" color="#FFFFFF">logical_volume_name</font></th> 
  <th align="Center" width="200" bgColor="#000080"> 
 <font face="Verdana" size="1" color="#FFFFFF">Total Size (GB)</font></th>  
 <th align="Center" width="200" bgColor="#000080">             
 <font face="Verdana" size="1" color="#FFFFFF">Available Size (GB)</font></th>
  <th align="Center" width="200" bgColor="#000080">             
 <font face="Verdana" size="1" color="#FFFFFF">Space Free %</font></th>              
   </tr>'                                  
SELECT      
 @TableHTML =  @TableHTML +                                       
 '<tr>                                    
 <td align="Center"><font face="Verdana" size="1">' + ISNULL(CONVERT(VARCHAR(100),  volume_mount_point ), '')  +'</font></td>' +
'<td align="Center"><font face="Verdana" size="1">' + ISNULL(CONVERT(VARCHAR(100),  file_system_type ), '')  +'</font></td>' +
'<td align="Center"><font face="Verdana" size="1">' + ISNULL(CONVERT(VARCHAR(100),  logical_volume_name ), '')  +'</font></td>' +
'<td align="Center"><font face="Verdana" size="1">' + ISNULL(CONVERT(VARCHAR(100),  [Total Size (GB)] ), '')  +'</font></td>' +
'<td align="Center"><font face="Verdana" size="1">' + ISNULL(CONVERT(VARCHAR(100),  [Available Size (GB)] ), '')  +'</font></td>' +
CASE WHEN [Space Free %] < 10 THEN 
  '<td align="Center"><font face="Verdana" size="1" color="#FF0000"><b>' + ISNULL(CONVERT(VARCHAR(100),  [Space Free %]), '')  +'</font></td>' 
ELSE 
  '<td align="Center"><font face="Verdana" size="1" color="#40C211"><b>' + ISNULL(CONVERT(VARCHAR(100),  [Space Free %]), '')  +'</font></td>'  
END +
  '</tr>'                                  
FROM             
#FreeSpace

  
/**** Tempdb File Usage *****/  
SELECT                                   
 @TableHTML =  @TableHTML +                              
 '</table>                                  
 <p style="margin-top: 1; margin-bottom: 0">&nbsp;</p>                                  
 <font face="Verdana" size="4">Tempdb File Usage</font>                                  
 <table id="AutoNumber1" style="BORDER-COLLAPSE: collapse" borderColor="#111111" height="40" cellSpacing="0" cellPadding="0" width="933" border="1">                                  
   <tr>                
 <th align="Center" width="300" bgColor="#000080">                                    
 <font face="Verdana" size="1" color="#FFFFFF">Database Name</font></th>               
 <th align="Center" width="300" bgColor="#000080">                                    
 <font face="Verdana" size="1" color="#FFFFFF">File Name</font></th>               
 <th align="Center" width="250" bgColor="#000080">                                    
 <font face="Verdana" size="1" color="#FFFFFF">Physical Name</font></th>               
 <th align="Center" width="250" bgColor="#000080">                                
 <font face="Verdana" size="1" color="#FFFFFF">FileSize MB</font></th>               
 <th align="Center" width="200" bgColor="#000080">               
 <font face="Verdana" size="1" color="#FFFFFF">Available MB</font></th>               
 <th align="Center" width="200" bgColor="#000080">                                    
 <font face="Verdana" size="1" color="#FFFFFF">Percent_full </font></th>               
   </tr>'                                  
select                                   
@TableHTML =  @TableHTML +                                     
 '<tr>' +                                      
 '<td align="Center"><font face="Verdana" size="1">' + ISNULL(databasename, '') + '</font></td>' +                                      
 '<td align="Center"><font face="Verdana" size="1">' + ISNULL(FileName, '') +'</font></td>' +                                      
 '<td align="Center"><font face="Verdana" size="1">' + ISNULL(physicalName, '') +'</font></td>' +                                      
 '<td align="Center"><font face="Verdana" size="1">' + ISNULL(filesizeMB, '') +'</font></td>' +                                  
 '<td align="Center"><font face="Verdana" size="1">' + ISNULL(availableSpaceMB, '') +'</font></td>' +  
 CASE WHEN CONVERT(DECIMAL(10,3),percentfull) >80.00 THEN    
'<td align="Center"><font face="Verdana" size="1" color="#FF0000"><b>' + ISNULL(percentfull, '') +'</b></font></td></tr>'                                               
 ELSE  
 '<td align="Center"><font face="Verdana" size="1">' + ISNULL(percentfull, '') +'</font></td></tr>' END                                
from                                   
 #tempdbfileusage       
  
/************* SQL Server CPU Pressure******************/  
SELECT                                   
 @TableHTML =  @TableHTML +                              
 '</table>                                  
 <p style="margin-top: 1; margin-bottom: 0">&nbsp;</p>                                  
 <font face="Verdana" size="4">CPU Pressure</font>                                  
 <table id="AutoNumber1" style="BORDER-COLLAPSE: collapse" borderColor="#111111" height="40" cellSpacing="0" cellPadding="0" width="933" border="1">                                  
   <tr>                
  <th align="Center" width="300" bgColor="#000080">                                    
 <font face="Verdana" size="1" color="#FFFFFF">%signal (cpu) waits</font></th>               
 <th align="Center" width="350" bgColor="#000080">                                    
 <font face="Verdana" size="1" color="#FFFFFF">%signal (cpu) waits Optimal Value</font></th>               
 <th align="Center" width="200" bgColor="#000080">                                    
 <font face="Verdana" size="1" color="#FFFFFF">%resource waits</font></th>                           
   </tr>'                                  
SELECT                                   
 @TableHTML =  @TableHTML +                                     
 '<tr>' + 
 '<td align="Center"><font face="Verdana" size="1">' + ISNULL(CONVERT(VARCHAR(100),[%signal (cpu) waits] ), '')  +'</font></td>' +    
 '<td align="Center"><font face="Verdana" size="1">' + ISNULL(CONVERT(VARCHAR(100), [%signal (cpu) waits Optimal Value] ), '')  +'</font></td>' +    
   '<td align="Center"><font face="Verdana" size="1">' + ISNULL(CONVERT(VARCHAR(100), [%resource waits] ), '')  +'</font></td>'      
  
FROM                                   
#CPUPre   

/**** CPU Usage *****/  
SELECT                                   
 @TableHTML =  @TableHTML +                              
 '</table>                                  
 <p style="margin-top: 1; margin-bottom: 0">&nbsp;</p>                                  
 <font face="Verdana" size="4">CPU Usage Currently</font>                                  
 <table id="AutoNumber1" style="BORDER-COLLAPSE: collapse" borderColor="#111111" height="40" cellSpacing="0" cellPadding="0" width="933" border="1">                                  
   <tr>                
 <th align="Center" width="300" bgColor="#000080">                                    
 <font face="Verdana" size="1" color="#FFFFFF">System Time</font></th>               
 <th align="Center" width="300" bgColor="#000080">                                    
 <font face="Verdana" size="1" color="#FFFFFF">SQLProcessUtilization</font></th>               
 <th align="Center" width="250" bgColor="#000080">                                    
 <font face="Verdana" size="1" color="#FFFFFF">SystemIdle</font></th>               
 <th align="Center" width="250" bgColor="#000080">                                    
 <font face="Verdana" size="1" color="#FFFFFF">OtherProcessUtilization</font></th>               
 <th align="Center" width="200" bgColor="#000080">               
 <font face="Verdana" size="1" color="#FFFFFF">load DateTime</font></th>               
   </tr>'                                  
SELECT                                   
 @TableHTML =  @TableHTML +                                     
 '<tr>' +                                      
 '<td align="Center"><font face="Verdana" size="1">' + ISNULL(CONVERT(VARCHAR(100), EventTime2 ), '')  +'</font></td>' +    
  '<td align="Center"><font face="Verdana" size="1">' + ISNULL(CONVERT(VARCHAR(100), SQLProcessUtilization ), '')  +'</font></td>' +    
   '<td align="Center"><font face="Verdana" size="1">' + ISNULL(CONVERT(VARCHAR(100), SystemIdle ), '')  +'</font></td>' +                              
   '<td align="Center"><font face="Verdana" size="1">' + ISNULL(CONVERT(VARCHAR(100), OtherProcessUtilization ), '')  +'</font></td>' +                              
  '<td align="Center"><font face="Verdana" size="1">' + ISNULL(CONVERT(VARCHAR(100), load_date ), '')  +'</font></td> </tr>'                                  
FROM                                   
 #CPU   
  
/***** Memory Usage ****/  
SELECT                                   
 @TableHTML =  @TableHTML +                              
 '</table>                                  
 <p style="margin-top: 1; margin-bottom: 0">&nbsp;</p>                                  
 <font face="Verdana" size="4">Memory Usage </font>                                  
 <table id="AutoNumber1" style="BORDER-COLLAPSE: collapse" borderColor="#111111" height="40" cellSpacing="0" cellPadding="0" width="933" border="1">                                  
   <tr>                
 <th align="left" width="136" bgColor="#000080">                                    
 <font face="Verdana" size="1" color="#FFFFFF">Parameter</font></th>                              
  <th align="left" width="200" bgColor="#000080">               
 <font face="Verdana" size="1" color="#FFFFFF">Value</font></th>              
   </tr>'                                  
SELECT                                   
 @TableHTML =  @TableHTML +                                       
 '<tr>                                    
 <td><font face="Verdana" size="1">' + ISNULL(CONVERT(VARCHAR(200),  Parameter ), '')  +'</font></td>' +                                        
 '<td><font face="Verdana" size="1">' + ISNULL(CONVERT(VARCHAR(100),  Value ), '')  +'</font></td>' +                                     
  '</tr>'                                  
FROM                                   
 #Memory;   
  
/***** Performance Counter Values ****/  
SELECT                                   
 @TableHTML =  @TableHTML +                              
 '</table>                                  
 <p style="margin-top: 1; margin-bottom: 0">&nbsp;</p>                                  
 <font face="Verdana" size="4">Performance Counter Data</font>                                  
 <table id="AutoNumber1" style="BORDER-COLLAPSE: collapse" borderColor="#111111" height="40" cellSpacing="0" cellPadding="0" width="933" border="1">                                  
   <tr>                
 <th align="left" width="136" bgColor="#000080">                                    
 <font face="Verdana" size="1" color="#FFFFFF">Performance_Counter</font></th>                              
  <th align="left" width="200" bgColor="#000080">               
 <font face="Verdana" size="1" color="#FFFFFF">Value</font></th>              
   </tr>'                                  
SELECT                                   
 @TableHTML =  @TableHTML +                                       
 '<tr>                                    
 <td><font face="Verdana" size="1">' + ISNULL(CONVERT(VARCHAR(300),  Parameter ), '')  +'</font></td>' +                                        
 '<td><font face="Verdana" size="1">' + ISNULL(CONVERT(VARCHAR(100),  Value ), '')  +'</font></td>' +                                     
  '</tr>'                                  
FROM                                   
 #PerfCntr_Data;   

/**** Job failed *****/  
SELECT                                   
 @TableHTML =  @TableHTML +                              
 '</table>                                  
 <p style="margin-top: 1; margin-bottom: 0">&nbsp;</p>                                  
 <font face="Verdana" size="4">Job Failed Report</font>                                  
 <table id="AutoNumber1" style="BORDER-COLLAPSE: collapse" borderColor="#111111" height="40" cellSpacing="0" cellPadding="0" width="933" border="1">                                  
   <tr>                
 <th align="Center" width="300" bgColor="#000080">                                    
 <font face="Verdana" size="1" color="#FFFFFF">Job Name</font></th>
 <th align="Center" width="300" bgColor="#000080">                                    
 <font face="Verdana" size="1" color="#FFFFFF">step_id</font></th>               
 <th align="Center" width="300" bgColor="#000080">                                    
 <font face="Verdana" size="1" color="#FFFFFF">Step Name</font></th>               
 <th align="Center" width="250" bgColor="#000080">                                    
 <font face="Verdana" size="1" color="#FFFFFF">Error Message</font></th>                         
   </tr>'                                  
SELECT      
 @TableHTML =  @TableHTML +                                       
 '<tr>                                    
 <td><font face="Verdana" size="1">' + ISNULL(CONVERT(VARCHAR(100),  [Job Name] ), '')  +'</font></td>' +                                        
 '<td><font face="Verdana" size="1">' + ISNULL(CONVERT(VARCHAR(100),  [step_id]), '')  +'</font></td>' + 
 '<td><font face="Verdana" size="1">' + ISNULL(CONVERT(VARCHAR(100),  [Step Name]), '')  +'</font></td>' + 
 '<td><font face="Verdana" size="1">' + ISNULL(CONVERT(VARCHAR(100),  [Error Message]), '')  +'</font></td>' + 
  ' <tr>'                              
FROM #Jobfail   

/***** Database Backup Report ****/  
SELECT                                   
 @TableHTML =  @TableHTML +                              
 '</table>                                  
 <p style="margin-top: 1; margin-bottom: 0">&nbsp;</p>                                  
 <font face="Verdana" size="4">Database Backup Report</font>                                  
 <table id="AutoNumber1" style="BORDER-COLLAPSE: collapse" borderColor="#111111" height="40" cellSpacing="0" cellPadding="0" width="933" border="1">                                  
   <tr>                
 <th align="left" width="136" bgColor="#000080">                                    
 <font face="Verdana" size="1" color="#FFFFFF">DB Namee</font></th>                              
  <th align="left" width="200" bgColor="#000080">               
 <font face="Verdana" size="1" color="#FFFFFF">Recovery Model</font></th> 
 <th align="left" width="200" bgColor="#000080">               
 <font face="Verdana" size="1" color="#FFFFFF">Online/Offline</font></th> 
 <th align="left" width="200" bgColor="#000080">               
 <font face="Verdana" size="1" color="#FFFFFF">Log Use Description</font></th> 
 <th align="left" width="200" bgColor="#000080">               
 <font face="Verdana" size="1" color="#FFFFFF">Last Full Backup</font></th> 
 <th align="left" width="200" bgColor="#000080">               
 <font face="Verdana" size="1" color="#FFFFFF">Last Log Backup</font></th>              
   </tr>'                                  
SELECT      
 @TableHTML =  @TableHTML +                                       
 '<tr>                                    
 <td><font face="Verdana" size="1">' + ISNULL(CONVERT(VARCHAR(100),  [DB Name] ), '')  +'</font></td>' +                                        
 '<td><font face="Verdana" size="1">' + ISNULL(CONVERT(VARCHAR(100),  [Recovery Model]), '')  +'</font></td>' + 
 '<td><font face="Verdana" size="1">' + ISNULL(CONVERT(VARCHAR(100),  [Online/Offline]), '')  +'</font></td>' + 
 '<td><font face="Verdana" size="1">' + ISNULL(CONVERT(VARCHAR(100),  [Log Use Description]), '')  +'</font></td>' + 
 '<td><font face="Verdana" size="1">' + ISNULL(CONVERT(VARCHAR(100),  [Last Full Backup]), '')  +'</font></td>' + 
 '<td><font face="Verdana" size="1">' + ISNULL(CONVERT(VARCHAR(100),  [Last Log Backup]), '')  +'</font></td>' +                                     
  '</tr>'                                  
FROM             
 #Backup_Report  
  
 /****** Connection Information *****/  
  
 SELECT                                   
 @TableHTML = @TableHTML +                                     
 '</table>                                  
 <p style="margin-top: 1; margin-bottom: 0">&nbsp;</p>                                  
 <font face="Verdana" size="4">Total Number of Connection Currently </font>                                  
 <table style="BORDER-COLLAPSE: collapse" borderColor="#111111" cellPadding="0" width="933" bgColor="#ffffff" borderColorLight="#000000" border="1">                                      
 <tr>                                      
 <th align="Center" width="50" bgColor="#000080">                                      
  <font face="Verdana" size="1" color="#FFFFFF">Host Names</font></th>                                      
 <th align="Center" width="50" bgColor="#000080">                                      
  <font face="Verdana" size="1" color="#FFFFFF">Number Of Connection</font></th>                                      
  </tr>'                                  
                         
SELECT                                   
 @TableHTML =  @TableHTML +                          
 '<tr>           
<td align="Center"><font face="Verdana" size="1">' + ISNULL(CONVERT(VARCHAR(100), Hostname ), '')  +'</font></td>' +                               
 '<td align="Center"><font face="Verdana" size="1">' + ISNULL(CONVERT(VARCHAR(100), NumberOfconn  ), '')  +'</font></td>' +                                   
  '</tr>'                                  
FROM                                   
 #ConnInfo                                  
      
/***** Log Space Usage ****/  
SELECT                                   
 @TableHTML =  @TableHTML +                              
 '</table>                                  
 <p style="margin-top: 1; margin-bottom: 0">&nbsp;</p>                                  
 <font face="Verdana" size="4">Log Space Usage </font>                                  
 <table id="AutoNumber1" style="BORDER-COLLAPSE: collapse" borderColor="#111111" height="40" cellSpacing="0" cellPadding="0" width="933" border="1">                                  
   <tr>                
 <th align="left" width="136" bgColor="#000080">                                    
 <font face="Verdana" size="1" color="#FFFFFF">DatabaseName</font></th>                              
  <th align="left" width="200" bgColor="#000080">               
 <font face="Verdana" size="1" color="#FFFFFF">Log_Space_Used</font></th>                              
  <th align="left" width="200" bgColor="#000080">               
 <font face="Verdana" size="1" color="#FFFFFF">Log_Usage_%</font></th>              
   </tr>'                                  
SELECT                                   
 @TableHTML =  @TableHTML +                                       
 '<tr>                                    
 <td><font face="Verdana" size="1">' + ISNULL(CONVERT(VARCHAR(100),  DBName ), '')  +'</font></td>' +                                        
 '<td><font face="Verdana" size="1">' + ISNULL(CONVERT(VARCHAR(100),  LogSize ), '')  +'</font></td>' +   
 CASE WHEN CONVERT(DECIMAL(10,3),LogSpaceUsed_Percent) >80.00 THEN  
  '<td><font face="Verdana" size="1" color="#FF0000"><b>' + ISNULL(CONVERT(VARCHAR(100),  LogSpaceUsed_Percent ), '')  +'</b></font></td>'  
 ELSE  
 '<td><font face="Verdana" size="1">' + ISNULL(CONVERT(VARCHAR(100),  LogSpaceUsed_Percent ), '')  +'</font></td>'   
 END +                                     
  '</tr>'                               
FROM                                   
 #LogSpace   
  
  
/******** Job Info *******/  
SELECT                                   
 @TableHTML = @TableHTML +                                   
 '</table>                          
 <p style="margin-top: 0; margin-bottom: 0">&nbsp;</p>                                  
 <font face="Verdana" size="4">Job Status</font>' +                                      
 '<table style="BORDER-COLLAPSE: collapse" borderColor="#111111" cellPadding="0" width="933" bgColor="#ffffff" borderColorLight="#000000" border="1">                                    
 <tr>                                    
 <th align="left" width="430" bgColor="#000080">                                    
 <font face="Verdana" size="1" color="#FFFFFF">spid</font></th>   
 <th align="left" width="70" bgColor="#000080">                                    
 <font face="Verdana" size="1" color="#FFFFFF">latwaittype</font></th>                                    
 <th align="left" width="85" bgColor="#000080">                                    
 <font face="Verdana" size="1" color="#FFFFFF">dbname</font></th>                                    
 <th align="left" width="183" bgColor="#000080">                                    
 <font face="Verdana" size="1" color="#FFFFFF">Process Login time</font></th>                                    
 <th align="left" width="136" bgColor="#000080">                                    
 <font face="Verdana" size="1" color="#FFFFFF">status</font></th>                                    
 <th align="left" width="136" bgColor="#000080">                                    
 <font face="Verdana" size="1" color="#FFFFFF">opentran</font></th>      
  <th align="left" width="136" bgColor="#000080">                                    
 <font face="Verdana" size="1" color="#FFFFFF">hostname</font></th>    
  <th align="left" width="146" bgColor="#000080">                                    
 <font face="Verdana" size="1" color="#FFFFFF">JobName</font></th>    
  <th align="left" width="136" bgColor="#000080">                                    
 <font face="Verdana" size="1" color="#FFFFFF">command</font></th>    
  <th align="left" width="136" bgColor="#000080">                                    
 <font face="Verdana" size="1" color="#FFFFFF">domain</font></th>     
   <th align="left" width="136" bgColor="#000080">                                    
 <font face="Verdana" size="1" color="#FFFFFF">LoginName</font></th>                                 
 </tr>'                                    
                                  
SELECT                                   
 @TableHTML = ISNULL(CONVERT(VARCHAR(MAX), @TableHTML), 'No Job Running') + '<tr><td><font face="Verdana" size="1">' + ISNULL(CONVERT(VARCHAR(100), spid), '') +'</font></td>' +                                      
'<td><font face="Verdana" size="1">' + ISNULL(CONVERT(VARCHAR(50), lastwaittype),'') + '</font></td>' +                       
 '<td><font face="Verdana" size="1">' + ISNULL(CONVERT(VARCHAR(50), dbname),'') + '</font></td>' +                                  
 '<td><font face="Verdana" size="1">' + ISNULL(CONVERT(VARCHAR(50), login_time),'') +'</font></td>' +     
  '<td><font face="Verdana" size="1">' + ISNULL(CONVERT(VARCHAR(50), status),'') +'</font></td>' +     
   '<td><font face="Verdana" size="1">' + ISNULL(CONVERT(VARCHAR(50), opentran),'') +'</font></td>' +     
    '<td><font face="Verdana" size="1">' + ISNULL(CONVERT(VARCHAR(50), hostname),'') +'</font></td>' +     
     '<td><font face="Verdana" size="1">' + ISNULL(CONVERT(VARCHAR(500), JobName),'') +'</font></td>' +     
      '<td><font face="Verdana" size="1">' + ISNULL(CONVERT(VARCHAR(200), command),'') +'</font></td>' +     
        '<td><font face="Verdana" size="1">' + ISNULL(CONVERT(VARCHAR(50), domain),'') +'</font></td>' +     
 '<td><font face="Verdana" size="1">' + ISNULL(CONVERT(VARCHAR(50),loginname ),'') + '</font></td></tr>'      
FROM                                   
 #JobInfo  
  
   
   
 /****** Blocking Information ****/  
  
 SELECT                                   
 @TableHTML = @TableHTML +                  
 '</table>                                  
 <p style="margin-top: 1; margin-bottom: 0">&nbsp;</p>                                  
 <font face="Verdana" size="4">Blocking Process Info (If Any)</font>                            
 <table style="BORDER-COLLAPSE: collapse" borderColor="#111111" cellPadding="0" width="933" bgColor="#ffffff" borderColorLight="#000000" border="1">                                      
 <tr>     
  <th align="Center" width="50" bgColor="#000080">                                      
  <font face="Verdana" size="1" color="#FFFFFF">ServerName</font></th>                                     
 <th align="Center" width="50" bgColor="#000080">                                      
  <font face="Verdana" size="1" color="#FFFFFF">SpID</font></th>                                      
 <th align="Center" width="50" bgColor="#000080">                                      
  <font face="Verdana" size="1" color="#FFFFFF">BlockingSPID</font></th>       <th align="Center" width="50" bgColor="#000080">                                   
 <font face="Verdana" size="1" color="#FFFFFF">ProgramName</font></th>                                      
 <th align="Center" width="50" bgColor="#000080">                                      
 <font face="Verdana" size="1" color="#FFFFFF">LoginName</font></th>                  
 <th align="Center" width="40" bgColor="#000080">                                      
 <font face="Verdana" size="1" color="#FFFFFF">ObjName</font></th>                        
 <th align="left" width="150" bgColor="#000080">                                      
 <font face="Verdana" size="1" color="#FFFFFF">Query</font></th>                                      
 </tr>'             
                                 
SELECT                                   
 @TableHTML =  @TableHTML +                                 
 '<tr>    
 <td><font face="Verdana" size="1">' + ISNULL(CONVERT(VARCHAR(100),  @SERVERNAME ), '')  +'</font></td>' +                                        
 '<td><font face="Verdana" size="1">' + ISNULL(CONVERT(VARCHAR(100),  spid ), '')  +'</font></td>' +                                        
 '<td><font face="Verdana" size="1">' + ISNULL(CONVERT(VARCHAR(100),  Blkspid ), '')  +'</font></td>' +                                   
 '<td><font face="Verdana" size="1">' + ISNULL(CONVERT(VARCHAR(100),  PrgName ), '')  +'</font></td>' +                                        
 '<td><font face="Verdana" size="1">' + ISNULL(CONVERT(VARCHAR(100),  LoginName ), '')  +'</font></td>' +                                     
 '<td><font face="Verdana" size="1">' + ISNULL(CONVERT(VARCHAR(100),  ObjName ), '')  +'</font></td>' +                                     
 '<td><font face="Verdana" size="1">' + ISNULL(CONVERT(VARCHAR(100),  Query ), '')  +'</font></td>' +                                     
  '</tr>'                       
FROM                                   
 #BlkProcesses                 
ORDER BY     spid    
 /****** Agent Status ****/  
  
 SELECT                                   
 @TableHTML = @TableHTML +                  
 '</table>                                  
 <p style="margin-top: 1; margin-bottom: 0">&nbsp;</p>                                  
 <font face="Verdana" size="4">SQL Agent Information (If Any)</font>                            
 <table style="BORDER-COLLAPSE: collapse" borderColor="#111111" cellPadding="0" width="933" bgColor="#ffffff" borderColorLight="#000000" border="1">                                      
 <tr>     
  <th align="Center" width="50" bgColor="#000080">                                      
  <font face="Verdana" size="1" color="#FFFFFF">Service Name</font></th>                                     
 <th align="Center" width="50" bgColor="#000080">                                      
  <font face="Verdana" size="1" color="#FFFFFF">Start Mode</font></th>                                      
 <th align="Center" width="50" bgColor="#000080">                                      
  <font face="Verdana" size="1" color="#FFFFFF">Status</font></th>       
  <th align="Center" width="50" bgColor="#000080">                                   
 <font face="Verdana" size="1" color="#FFFFFF">Straing Since</font></th>                                      
 <th align="Center" width="50" bgColor="#000080">                                      
 <font face="Verdana" size="1" color="#FFFFFF">Account</font></th>                  
 <th align="Center" width="40" bgColor="#000080">                                      
 <font face="Verdana" size="1" color="#FFFFFF">Location</font></th>                        
 <th align="left" width="150" bgColor="#000080">                                      
 <font face="Verdana" size="1" color="#FFFFFF">ID</font></th>                                      
 </tr>'             
                                 
SELECT                                   
 @TableHTML =  @TableHTML +                                 
 '<tr>    
 <td><font face="Verdana" size="1">' + ISNULL(CONVERT(VARCHAR(256),  [Service Name] ), '')  +'</font></td>' +                                        
 '<td><font face="Verdana" size="1">' + ISNULL(CONVERT(VARCHAR(256),  [Start Mode] ), '')  +'</font></td>' +                                        
 '<td><font face="Verdana" size="1">' + ISNULL(CONVERT(VARCHAR(256),  [Status] ), '')  +'</font></td>' +                                   
 '<td><font face="Verdana" size="1">' + ISNULL(CONVERT(VARCHAR(256),  [Straing Since] ), '')  +'</font></td>' +                                        
 '<td><font face="Verdana" size="1">' + ISNULL(CONVERT(VARCHAR(256),  [Account] ), '')  +'</font></td>' +                                     
 '<td><font face="Verdana" size="1">' + ISNULL(CONVERT(VARCHAR(256),  [Location]  ), '')  +'</font></td>' +                                     
 '<td><font face="Verdana" size="1">' + ISNULL(CONVERT(VARCHAR(256),  [ID]  ), '')  +'</font></td>' +                                     
  '</tr>'                       
FROM                                   
 #agentstatus                 
  
  
/**** Long running Transactions*****/  
SELECT                                   
 @TableHTML =  @TableHTML +                              
 '</table>                                  
 <p style="margin-top: 1; margin-bottom: 0">&nbsp;</p>                                  
 <font face="Verdana" size="4">Long Running Transactions</font>                                  
 <table id="AutoNumber1" style="BORDER-COLLAPSE: collapse" borderColor="#111111" height="40" cellSpacing="0" cellPadding="0" width="933" border="1">                                  
   <tr>                
 <th align="Center" width="300" bgColor="#000080">                                    
 <font face="Verdana" size="1" color="#FFFFFF">SPID</font></th>               
 <th align="Center" width="300" bgColor="#000080">                                    
 <font face="Verdana" size="1" color="#FFFFFF">TranID</font></th>               
 <th align="Center" width="250" bgColor="#000080">                                    
 <font face="Verdana" size="1" color="#FFFFFF">User_Tran</font></th>               
<th align="Center" width="250" bgColor="#000080">                                    
 <font face="Verdana" size="1" color="#FFFFFF">DB_Name</font></th>               
<th align="Center" width="250" bgColor="#000080">                                    
 <font face="Verdana" size="1" color="#FFFFFF">Login_Time</font></th>               
<th align="Center" width="250" bgColor="#000080">                                    
 <font face="Verdana" size="1" color="#FFFFFF">Duration</font></th>               
<th align="Center" width="250" bgColor="#000080">                                    
 <font face="Verdana" size="1" color="#FFFFFF">Last_Batch</font></th>               
<th align="Center" width="250" bgColor="#000080">                                    
 <font face="Verdana" size="1" color="#FFFFFF">Status</font></th>               
<th align="Center" width="250" bgColor="#000080">                                    
 <font face="Verdana" size="1" color="#FFFFFF">LoginName</font></th>               
<th align="Center" width="250" bgColor="#000080">                                    
 <font face="Verdana" size="1" color="#FFFFFF">Host_Name</font></th>               
<th align="Center" width="250" bgColor="#000080">                                    
 <font face="Verdana" size="1" color="#FFFFFF">PrgName</font></th>               
<th align="Center" width="250" bgColor="#000080">                                    
 <font face="Verdana" size="1" color="#FFFFFF">CMD</font></th>               
 <th align="Center" width="200" bgColor="#000080">               
 <font face="Verdana" size="1" color="#FFFFFF">SQL</font></th>               
 <th align="Center" width="200" bgColor="#000080">                                    
 <font face="Verdana" size="1" color="#FFFFFF">Blocked </font></th>               
   </tr>'                                  
select                                   
@TableHTML =  @TableHTML +                                     
 '<tr>' +                                      
 '<td align="Center"><font face="Verdana" size="1">' + ISNULL(SPID, '') + '</font></td>' +                                      
 '<td align="Center"><font face="Verdana" size="1">' + ISNULL(TranID, '') +'</font></td>' +                                      
 '<td align="Center"><font face="Verdana" size="1">' + ISNULL(User_Tran, '') +'</font></td>' +                                      
  '<td align="Center"><font face="Verdana" size="1">' + ISNULL(DBName, '') +'</font></td>' +                   
 '<td align="Center"><font face="Verdana" size="1">' + ISNULL(Login_Time, '') +'</font></td>' +                   
 '<td align="Center"><font face="Verdana" size="1">' + ISNULL(Duration, '') +'</font></td>' +                   
 '<td align="Center"><font face="Verdana" size="1">' + ISNULL(Last_Batch, '') +'</font></td>' +                   
 '<td align="Center"><font face="Verdana" size="1">' + ISNULL([Status], '') +'</font></td>' +                   
 '<td align="Center"><font face="Verdana" size="1">' + ISNULL(LoginName, '') +'</font></td>' +                   
 '<td align="Center"><font face="Verdana" size="1">' + ISNULL(HostName, '') +'</font></td>' +                   
 '<td align="Center"><font face="Verdana" size="1">' + ISNULL(ProgramName, '') +'</font></td>' +                   
 '<td align="Center"><font face="Verdana" size="1">' + ISNULL(CMD, '') +'</font></td>' +                   
 '<td align="Center"><font face="Verdana" size="1">' + ISNULL([SQL], '') +'</font></td>' +                   
 '<td align="Center"><font face="Verdana" size="1">' + ISNULL(Blocked, '') +'</font></td></tr>'                                 
from                                   
 #OpenTran_Detail       
  
   
 /****** End to HTML Formatting  ***/    
SELECT                              
 @TableHTML =  @TableHTML +  '</table>' +                                  
 '<p style="margin-top: 0; margin-bottom: 0">&nbsp;</p>                                  
 <p>&nbsp;</p>'    
        
    
EXEC msdb.dbo.sp_send_dbmail                                    
 @profile_name = @MailProfile,--'Database Mail SMTP',                             
 @recipients=@MailID,  --'info@datantech.com',                                  
 @subject = @strSubject,                                   
 @body = @TableHTML,                                      
 @body_format = 'HTML' ;                               
  
  
DROP TABLE  #RebootDetails  
DROP TABLE	#FreeSpace;
DROP TABLE  #BlkProcesses  
DROP TABLE  #ErrorLogInfo  
DROP TABLE  #CPU  
--DROP TABLE  #Memory_BPool  
DROP TABLE  #Memory_sys
DROP TABLE  #Memory_process 
DROP TABLE  #Memory 
DROP TABLE  #perfmon_counters 
DROP TABLE  #PerfCntr_Data 
drop table #Jobfail
DROP TABLE  #Backup_Report 
DROP TABLE  #ConnInfo
DROP TABLE  #JobInfo  
DROP TABLE  #tempdbfileusage  
DROP TABLE  #LogSpace 
DROP TABLE  #OpenTran_Detail
DROP TABLE #CPUPre  
DROP TABLE #agentstatus
 
SET NOCOUNT OFF;  
SET ARITHABORT OFF;  
END  
  
  
  



GO

