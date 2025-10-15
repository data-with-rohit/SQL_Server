SET NOCOUNT ON;
--------------------------------------------------------------------------------
-- Parameters: pass comma-separated lists or leave NULL/empty for “all”
--------------------------------------------------------------------------------
DECLARE @IncludeDBs       NVARCHAR(MAX) = NULL;  -- e.g. N'DB1,DB2'
DECLARE @ExcludeDBs       NVARCHAR(MAX) = NULL;  -- e.g. N'master,msdb'
DECLARE @IncludeSchemas   NVARCHAR(MAX) = NULL;  -- e.g. N'dbo,Reporting'
DECLARE @ExcludeSchemas   NVARCHAR(MAX) = NULL;  -- e.g. N'Temp,Staging'
DECLARE @CutoffDate       DATE          = '2025-10-15'; -- stats older than this date
--------------------------------------------------------------------------------
-- Normalize DB and Schema lists into temp tables
--------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#IncludeDBs') IS NOT NULL DROP TABLE #IncludeDBs;
IF OBJECT_ID('tempdb..#ExcludeDBs') IS NOT NULL DROP TABLE #ExcludeDBs;
IF OBJECT_ID('tempdb..#IncludeSchemas') IS NOT NULL DROP TABLE #IncludeSchemas;
IF OBJECT_ID('tempdb..#ExcludeSchemas') IS NOT NULL DROP TABLE #ExcludeSchemas;

CREATE TABLE #IncludeDBs     (Name SYSNAME);
CREATE TABLE #ExcludeDBs     (Name SYSNAME);
CREATE TABLE #IncludeSchemas (Name SYSNAME);
CREATE TABLE #ExcludeSchemas (Name SYSNAME);
 
IF COALESCE(LTRIM(RTRIM(@IncludeDBs)), '') <> ''
    INSERT INTO #IncludeDBs(Name)
    SELECT DISTINCT LTRIM(RTRIM(value)) FROM STRING_SPLIT(@IncludeDBs, ',') WHERE LTRIM(RTRIM(value)) <> '';

IF COALESCE(LTRIM(RTRIM(@ExcludeDBs)), '') <> ''
    INSERT INTO #ExcludeDBs(Name)
    SELECT DISTINCT LTRIM(RTRIM(value)) FROM STRING_SPLIT(@ExcludeDBs, ',') WHERE LTRIM(RTRIM(value)) <> '';

IF COALESCE(LTRIM(RTRIM(@IncludeSchemas)), '') <> ''
    INSERT INTO #IncludeSchemas(Name)
    SELECT DISTINCT LTRIM(RTRIM(value)) FROM STRING_SPLIT(@IncludeSchemas, ',') WHERE LTRIM(RTRIM(value)) <> '';

IF COALESCE(LTRIM(RTRIM(@ExcludeSchemas)), '') <> ''
    INSERT INTO #ExcludeSchemas(Name)
    SELECT DISTINCT LTRIM(RTRIM(value)) FROM STRING_SPLIT(@ExcludeSchemas, ',') WHERE LTRIM(RTRIM(value)) <> '';

--------------------------------------------------------------------------------
-- Target databases list (apply include/exclude logic)
--------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#TargetDBs') IS NOT NULL DROP TABLE #TargetDBs;
	CREATE TABLE #TargetDBs (Name SYSNAME PRIMARY KEY);

INSERT INTO #TargetDBs(Name)
SELECT d.name FROM sys.databases AS d WHERE d.state_desc = 'ONLINE'
  AND d.database_id > 4  -- skip master, tempdb, model, msdb
  AND (
        (NOT EXISTS (SELECT 1 FROM #IncludeDBs) AND d.name NOT IN (SELECT Name FROM #ExcludeDBs))
		OR (EXISTS (SELECT 1 FROM #IncludeDBs) AND d.name IN (SELECT Name FROM #IncludeDBs))
  );

--------------------------------------------------------------------------------
-- Final Output table
--------------------------------------------------------------------------------

IF OBJECT_ID('tempdb..#TempIndex', 'U') IS NOT NULL
  DROP TABLE #TempIndex;

CREATE TABLE #TempIndex
(
  DBID                    INT,
  OBJECTID                BIGINT,
  STATSID                 BIGINT,
  DBNAME                  VARCHAR(128),
  SCHEMANAME              VARCHAR(128),
  TABLENAME               VARCHAR(256),
  STATNAME                VARCHAR(512),
  Stat_Column_name        VARCHAR(512),
  No_of_Rows              BIGINT NULL,
  Rows_Sampled            BIGINT NULL,
  Modification_Counter    BIGINT NULL,
  Steps_in_histogramme    INT,
  Stat_Filter             VARCHAR(1000) NULL,
  Stats_Last_Update_Date  DATETIME
);

--------------------------------------------------------------------------------
-- Loop through target DBs and collect stats which taking care of exclusion and inclusion of schemas
--------------------------------------------------------------------------------
DECLARE @DBName SYSNAME;
DECLARE @sqlcmd NVARCHAR(MAX);

DECLARE db_cur CURSOR LOCAL FAST_FORWARD FOR
	SELECT Name FROM #TargetDBs;
		OPEN db_cur;
			FETCH NEXT FROM db_cur INTO @DBName;

	WHILE @@FETCH_STATUS = 0
		BEGIN
				BEGIN TRY
							SET @sqlcmd = N'
							USE ' + QUOTENAME(@DBName) + N';
									SELECT DISTINCT
										CAST(DB_ID() AS INT) 	AS [databaseID],
										mst.object_id                                     AS objectID,
										ss.stats_id                                       AS [stats_id],
										DB_NAME()                                         AS [DatabaseName],
										sch.name                                          AS schemaName,
										OBJECT_NAME(mst.object_id)                        AS tableName,
										ss.name                                           AS [stat_name],
										col.name                                          AS column_name,
										ISNULL(sp.[rows], SUM(prt.[rows]))                AS [rows],
										sp.rows_sampled,
										sp.modification_counter,
										sp.steps,
										ss.filter_definition,
										STATS_DATE(mst.object_id, ss.stats_id)            AS [stats_date]
									FROM sys.stats AS ss
									INNER JOIN sys.stats_columns AS sc ON ss.object_id = sc.object_id AND ss.stats_id = sc.stats_id
									INNER JOIN sys.columns AS col ON sc.object_id = col.object_id AND sc.column_id = col.column_id
									INNER JOIN sys.objects AS obj ON obj.object_id = ss.object_id
									INNER JOIN sys.tables AS mst ON mst.object_id = obj.object_id
									INNER JOIN sys.schemas AS sch ON sch.schema_id = mst.schema_id
									INNER JOIN sys.partitions AS prt ON prt.object_id = ss.object_id
									CROSS APPLY sys.dm_db_stats_properties(ss.object_id, ss.stats_id) AS sp
										WHERE
											((NOT EXISTS (SELECT 1 FROM #IncludeSchemas) AND sch.name NOT IN (SELECT Name FROM #ExcludeSchemas))
												OR
											(EXISTS (SELECT 1 FROM #IncludeSchemas) AND sch.name IN (SELECT Name FROM #IncludeSchemas))
											)
									GROUP BY obj.object_id, mst.object_id, sch.name, ss.stats_id, col.name, ss.name, sp.[rows], sp.rows_sampled, sp.modification_counter, sp.steps, ss.filter_definition,STATS_DATE(mst.object_id, ss.stats_id)
									ORDER BY sch.name, OBJECT_NAME(mst.object_id), ss.name;
								';

						INSERT INTO #TempIndex (DBID, OBJECTID, STATSID, DBNAME, SCHEMANAME, TABLENAME, STATNAME, Stat_Column_name, No_of_Rows, Rows_Sampled, Modification_Counter, Steps_in_histogramme, Stat_Filter, Stats_Last_Update_Date)
						EXEC sys.sp_executesql @sqlcmd;
				END TRY
				BEGIN CATCH
					PRINT CONCAT('Stats collection failed for database ', @DBName, ' - ', ERROR_MESSAGE());
				END CATCH;
		FETCH NEXT FROM db_cur INTO @DBName;
	END
CLOSE db_cur;
DEALLOCATE db_cur;

--------------------------------------------------------------------------------
-- Final report
-- Includes a helper Update_Command (cross-DB) string for review/execution
--------------------------------------------------------------------------------
SELECT  *,
  'UPDATE STATISTICS ' + QUOTENAME(DBNAME) + '.' + QUOTENAME(SCHEMANAME) + '.' + QUOTENAME(TABLENAME) + ' ' + QUOTENAME(STATNAME) + ' WITH FULLSCAN, MAXDOP = 8' AS Update_Command
FROM #TempIndex
WHERE No_of_Rows > 0 
  AND (Rows_Sampled IS NULL OR No_of_Rows <> Rows_Sampled)          -- sampled or unknown
  AND (Stats_Last_Update_Date IS NULL OR Stats_Last_Update_Date < @CutoffDate)
  ORDER BY No_of_Rows DESC, DBNAME, SCHEMANAME, TABLENAME, STATNAME;
