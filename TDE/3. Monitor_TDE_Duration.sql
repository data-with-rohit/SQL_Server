
--Step 13: Polling to monitor the progress of encryption (Run in a different window)
DECLARE @state tinyint;
DECLARE @encyrption_progress 
    TABLE(sample_time DATETIME, percent_complete DECIMAL(5,2))

SELECT @state = k.encryption_state
FROM sys.dm_database_encryption_keys k
INNER JOIN sys.databases d
   ON k.database_id = d.database_id
WHERE d.name = 'TestTDE';

WHILE @state != 3
BEGIN
   INSERT INTO @encyrption_progress(sample_time, percent_complete)
   SELECT GETDATE(), percent_complete
   FROM sys.dm_database_encryption_keys k
   INNER JOIN sys.databases d
      ON k.database_id = d.database_id
   WHERE d.name = 'TestTDE';


   WAITFOR delay '00:00:05';

   SELECT @state = k.encryption_state
   FROM sys.dm_database_encryption_keys k
   INNER JOIN sys.databases d
      ON k.database_id = d.database_id
   WHERE d.name = 'TestTDE'; 
END

SELECT * FROM @encyrption_progress;
GO