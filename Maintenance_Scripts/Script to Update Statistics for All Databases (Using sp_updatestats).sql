DECLARE @SQL NVARCHAR(1000);
DECLARE @DB sysname;

DECLARE curDB CURSOR FORWARD_ONLY STATIC FOR 
   SELECT [name] 
   FROM sys.databases
   WHERE [name] NOT IN ('master', 'model', 'msdb', 'tempdb')
   ORDER BY [name];

OPEN curDB;
FETCH NEXT FROM curDB INTO @DB;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @SQL = N'USE [' + QUOTENAME(@DB) + ']; EXEC sp_updatestats;';
    EXEC sp_executesql @SQL;
    FETCH NEXT FROM curDB INTO @DB;
END;

CLOSE curDB;
DEALLOCATE curDB;
