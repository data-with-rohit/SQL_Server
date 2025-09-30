
--Step 13: Polling to monitor the progress of encryption (Run in a different window)
DECLARE @state tinyint;
DECLARE @TDE_encyrption_progress 
    TABLE(sample_time DATETIME, percent_complete DECIMAL(5,2))

SELECT @state = k.encryption_state FROM sys.dm_database_encryption_keys k
INNER JOIN sys.databases d    ON k.database_id = d.database_id
WHERE d.name = 'TDE_Demo';

WHILE @state != 3
BEGIN
   INSERT INTO @TDE_encyrption_progress(sample_time, percent_complete)
   SELECT GETDATE(), percent_complete FROM sys.dm_database_encryption_keys k
   INNER JOIN sys.databases d ON k.database_id = d.database_id
   WHERE d.name = 'TDE_Demo';


   WAITFOR delay '00:00:10';

   SELECT @state = k.encryption_state FROM sys.dm_database_encryption_keys k
   INNER JOIN sys.databases d ON k.database_id = d.database_id
   WHERE d.name = 'TDE_Demo'; 
END

SELECT * FROM @TDE_encyrption_progress;

GO
