--Step 15: Pausing the encryption scan for all databases using the trace flag
DBCC TRACEON(5004);
DBCC TRACEOFF(5004,-1);
ALTER DATABASE TDE_Demo SET ENCRYPTION ON;

--Step 16: Suspending the encryption scan for a database using ALTER DATABASE 
ALTER DATABASE TDE_Demo SET ENCRYPTION SUSPEND;
GO

--Step 17: Resuming the encryption scan for a database using ALTER DATABASE 
ALTER DATABASE TDE_Demo SET ENCRYPTION RESUME;
GO

