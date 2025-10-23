--- YOU MUST EXECUTE THE FOLLOWING SCRIPT IN SQLCMD MODE.

----------------------------------------------------------------------------------------------------
-- STEP 1: Configuration on AG1 (First Replica)
----------------------------------------------------------------------------------------------------

-- Connect to the first SQL Server instance (replica)
:Connect AG1

USE [master]
GO
-- Create the Database Mirroring / Always On communication endpoint
-- Use port 5022 (common port for HADR endpoint) with AES encryption, required for security.

IF NOT EXISTS (SELECT * FROM sys.endpoints WHERE name = 'Hadr_endpoint')
BEGIN
    CREATE ENDPOINT [Hadr_endpoint] AS TCP (LISTENER_PORT = 5022) FOR DATA_MIRRORING (ROLE = ALL, ENCRYPTION = REQUIRED ALGORITHM AES);
END
GO

-- Ensure the endpoint state is STARTED
IF (SELECT state FROM sys.endpoints WHERE name = N'Hadr_endpoint') <> 0
BEGIN
    ALTER ENDPOINT [Hadr_endpoint] STATE = STARTED
END
GO

USE [master];
GO
-- Dynamically find and store the SQL Server service account
DECLARE @sqlServiceAccount sysname;
SELECT TOP 1 @sqlServiceAccount = service_account FROM sys.dm_server_services WHERE servicename LIKE N'SQL Server (%' 
-- Grant CONNECT permission on the HADR endpoint to the SQL Server service account
IF @sqlServiceAccount IS NOT NULL
BEGIN
    DECLARE @sqlGrantCommand nvarchar(MAX);
    -- Construct the dynamic GRANT statement
    SET @sqlGrantCommand = N'GRANT CONNECT ON ENDPOINT::[Hadr_endpoint] TO [' + @sqlServiceAccount + N']';
    Print @sqlGrantCommand
    EXEC sp_executesql @sqlGrantCommand;
    PRINT 'Successfully attempted to grant CONNECT permission on ENDPOINT::[Hadr_endpoint] to the SQL Service Account: ' + @sqlServiceAccount;
END
ELSE
BEGIN
    PRINT 'ERROR: Could not identify the SQL Server service account.';
END
GO

-- Connect to the first replica again (ensures connection context after preceding GO)
:Connect AG1
-- Enable and start the 'AlwaysOn_health' Extended Event session for monitoring
-- This session is critical for diagnostics and is required for the AG Dashboard in SSMS
IF EXISTS(SELECT * FROM sys.server_event_sessions WHERE name='AlwaysOn_health')
BEGIN
  -- Set the session to start automatically when the SQL Server instance starts
  ALTER EVENT SESSION [AlwaysOn_health] ON SERVER WITH (STARTUP_STATE=ON);
END
IF NOT EXISTS(SELECT * FROM sys.dm_xe_sessions WHERE name='AlwaysOn_health')
BEGIN
  -- Start the session immediately if it's not currently running
  ALTER EVENT SESSION [AlwaysOn_health] ON SERVER STATE=START;
END
GO

----------------------------------------------------------------------------------------------------
-- STEP 2: Configuration on AG2 (Second Replica)
----------------------------------------------------------------------------------------------------

-- Connect to the second SQL Server instance (replica)
:Connect AG2
USE [master]
GO
-- Create the Database Mirroring / Always On communication endpoint (same configuration as AG1)
IF NOT EXISTS (SELECT * FROM sys.endpoints WHERE name = 'Hadr_endpoint')
BEGIN
    CREATE ENDPOINT [Hadr_endpoint] AS TCP (LISTENER_PORT = 5022) FOR DATA_MIRRORING (ROLE = ALL, ENCRYPTION = REQUIRED ALGORITHM AES);
END
GO

-- Ensure the endpoint state is STARTED
IF (SELECT state FROM sys.endpoints WHERE name = N'Hadr_endpoint') <> 0
BEGIN
    ALTER ENDPOINT [Hadr_endpoint] STATE = STARTED
END
GO

USE [master];
GO

-- Dynamically find and store the SQL Server service account for AG2
DECLARE @sqlServiceAccount sysname;
SELECT TOP 1 @sqlServiceAccount = service_account FROM sys.dm_server_services WHERE servicename LIKE N'SQL Server (%' 

-- Grant CONNECT permission on the HADR endpoint to the SQL Server service account for AG2
IF @sqlServiceAccount IS NOT NULL
BEGIN
    DECLARE @sqlGrantCommand nvarchar(MAX);
    SET @sqlGrantCommand = N'GRANT CONNECT ON ENDPOINT::[Hadr_endpoint] TO [' + @sqlServiceAccount + N']';
    EXEC sp_executesql @sqlGrantCommand;
    PRINT 'Successfully attempted to grant CONNECT permission on ENDPOINT::[Hadr_endpoint] to the SQL Service Account: ' + @sqlServiceAccount;
END
ELSE
BEGIN
    PRINT 'ERROR: Could not identify the SQL Server service account.';
END
GO

-- Connect to the second replica again
:Connect AG2

-- Enable and start the 'AlwaysOn_health' Extended Event session for monitoring
IF EXISTS(SELECT * FROM sys.server_event_sessions WHERE name='AlwaysOn_health')
BEGIN
  ALTER EVENT SESSION [AlwaysOn_health] ON SERVER WITH (STARTUP_STATE=ON);
END
IF NOT EXISTS(SELECT * FROM sys.dm_xe_sessions WHERE name='AlwaysOn_health')
BEGIN
  ALTER EVENT SESSION [AlwaysOn_health] ON SERVER STATE=START;
END
GO

----------------------------------------------------------------------------------------------------
-- STEP 3: Database Creation and Backup (Must be on Primary Replica, AG1)
----------------------------------------------------------------------------------------------------

-- Connect back to the first replica (which will be the initial primary)
:Connect AG1

-- Declare variables for dynamic database creation
DECLARE @DataPath nvarchar(512);
DECLARE @LogPath nvarchar(512);
DECLARE @SqlStatement nvarchar(max);
DECLARE @DBName sysname = N'AG2025_1'; -- Database to be added to the AG

-- Retrieve the instance's default data and log paths
SELECT
    @DataPath = CONVERT(nvarchar(512), SERVERPROPERTY('InstanceDefaultDataPath')),
    @LogPath = CONVERT(nvarchar(512), SERVERPROPERTY('InstanceDefaultLogPath'));

-- Error handling for path retrieval
IF @DataPath IS NULL OR @LogPath IS NULL
BEGIN
    RAISERROR(N'Could not retrieve instance default data or log paths.', 16, 1);
    RETURN;
END

-- Construct and execute dynamic SQL to CREATE the database at default instance locations
SET @SqlStatement = N'
CREATE DATABASE ' + QUOTENAME(@DBName) + N'
ON 
( NAME = N''' + @DBName + N'_Data'',
    FILENAME = N''' + @DataPath + @DBName + N'_Data.mdf'',
    SIZE = 8192KB , 
    MAXSIZE = UNLIMITED, 
    FILEGROWTH = 65536KB 
)
LOG ON 
( NAME = N''' + @DBName + N'_Log'',
    FILENAME = N''' + @LogPath + @DBName + N'_Log.ldf'',
    SIZE = 8192KB , 
    MAXSIZE = 2048GB , 
    FILEGROWTH = 65536KB 
)';
EXEC sp_executesql @SqlStatement;
GO

-- Perform Full and Log Backups (required for a database to be added to an Availability Group)
DECLARE @BackupPath nvarchar(512);
-- @DBName is still set to 'AG2025_1'

-- Retrieve the instance's default backup path
SELECT
    @BackupPath = CONVERT(nvarchar(512), SERVERPROPERTY('InstanceDefaultBackupPath'));

-- Error handling for path retrieval
IF @BackupPath IS NULL
BEGIN
    RAISERROR(N'Could not retrieve instance default backup path.', 16, 1);
    RETURN;
END

-- Ensure the path ends with a backslash for proper concatenation
IF RIGHT(@BackupPath, 1) <> '\'
BEGIN
    SET @BackupPath = @BackupPath + '\';
END

-- Construct and execute dynamic SQL for a Full Database Backup
SET @SqlStatement = N'
BACKUP DATABASE ' + QUOTENAME(@DBName) + N' 
TO DISK = N''' + @BackupPath + @DBName + N'_FULL.bak'' 
WITH COMPRESSION, INIT; -- INIT overwrites the file if it exists
';
EXEC sp_executesql @SqlStatement;

-- Construct and execute dynamic SQL for a Log Backup (required for log chain integrity)
SET @SqlStatement = N'
BACKUP LOG ' + QUOTENAME(@DBName) + N' 
TO DISK = N''' + @BackupPath + @DBName + N'_LOG.trn'' 
WITH COMPRESSION;
';
EXEC sp_executesql @SqlStatement;
GO

----------------------------------------------------------------------------------------------------
-- STEP 4: Create Availability Group, Listener, and Finalize
----------------------------------------------------------------------------------------------------

USE [master]
GO

-- Create the Availability Group (AG) 'TestNew_AG'
CREATE AVAILABILITY GROUP [TestNew_AG] 
WITH (
    AUTOMATED_BACKUP_PREFERENCE = PRIMARY, 
    DB_FAILOVER = ON, 
    DTC_SUPPORT = NONE, 
    REQUIRED_SYNCHRONIZED_SECONDARIES_TO_COMMIT = 0 -- Configures minimal sync commit for failover
)
-- Add the database 'AG2025_1' to the AG (assuming this DB was prepared separately)
FOR DATABASE [AG2025_1] 
REPLICA ON 
    -- AG1 Configuration
    N'AG1' WITH (
        ENDPOINT_URL = N'TCP://AG1.SQLServer.local:5022', 
        FAILOVER_MODE = AUTOMATIC, 
        AVAILABILITY_MODE = SYNCHRONOUS_COMMIT, -- Data is synchronized
        BACKUP_PRIORITY = 50, 
        SEEDING_MODE = AUTOMATIC, -- Allows automatic initial synchronization
        SECONDARY_ROLE(ALLOW_CONNECTIONS = NO)
    ),
    -- AG2 Configuration
    N'AG2' WITH (
        ENDPOINT_URL = N'TCP://AG2.SQLServer.local:5022', 
        FAILOVER_MODE = AUTOMATIC, 
        AVAILABILITY_MODE = SYNCHRONOUS_COMMIT, 
        BACKUP_PRIORITY = 50, 
        SEEDING_MODE = AUTOMATIC, 
        SECONDARY_ROLE(ALLOW_CONNECTIONS = NO)
    );
GO

-- Connect to the initial Primary Replica (AG1)
:Connect AG1
USE [master]
GO

-- Create the Availability Group Listener 'TestNew_AG_L' 
-- This requires a cluster resource (Client Access Point) to be created in the Windows Failover Cluster.
ALTER AVAILABILITY GROUP [TestNew_AG] 
    ADD LISTENER N'TestNew_AG_L' (WITH IP((N'192.168.1.145', N'255.255.255.0')), PORT=1433);
GO

-- Connect to the Secondary Replica (AG2)
:Connect AG2

-- Join AG2 to the newly created Availability Group 'TestNew_AG'
ALTER AVAILABILITY GROUP [TestNew_AG] JOIN;
GO

-- Grant permission on AG2 to allow automatic creation of databases from seeding
ALTER AVAILABILITY GROUP [TestNew_AG] GRANT CREATE ANY DATABASE;
GO
