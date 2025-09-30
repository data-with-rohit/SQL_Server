--Step 1: Creating the Database Master Key (DMK
USE master;
GO
CREATE MASTER KEY
ENCRYPTION BY PASSWORD = 'UseAStrongPasswordHere!£$7';
GO

--Step 2: Backing up the DMK
BACKUP MASTER KEY TO FILE = 'C:\Test\MyDMK'   
ENCRYPTION BY PASSWORD = 'UseAnotherStrongPasswordHere!£$7';
GO

--Step 3: Creating the Certificate
USE master;     
GO
CREATE CERTIFICATE MyTDECert 
WITH SUBJECT = 'Certificate used for TDE in the TestTDE database';
GO

--Step 4: Backing up the Certificate
USE master;     
GO
BACKUP CERTIFICATE MyTDECert   
TO FILE = 'C:\Test\MyTDECert.cer'  
WITH PRIVATE KEY   
(  
    FILE = 'C:\Test\MyTDECert_PrivateKeyFile.pvk',  
    ENCRYPTION BY PASSWORD = 'UseAStrongPasswordHereToo!£$7'  
);
GO

-- Step 5: Create Test Database
CREATE DATABASE TDE_Demo;
GO
/*
OR ATTACH
USE [master];
GO

CREATE DATABASE [TDE_Demo]
ON 
(
    FILENAME = N'E:\SQL\TDE_Demo.mdf'
),
(
    FILENAME = N'E:\SQL\TDE_Demo_log.ldf'
)
FOR ATTACH;
GO
*/

--Step 6: Create DEK
USE TDE_Demo;     
GO
CREATE DATABASE ENCRYPTION KEY WITH ALGORITHM = AES_256
ENCRYPTION BY SERVER CERTIFICATE MyTDECert;
GO

--Step 7: Turn on encryption for database
ALTER DATABASE TDE_Demo SET ENCRYPTION ON;
GO

--Step 8: Viewing list of encrypted databases
SELECT name
FROM sys.databases
WHERE is_encrypted = 1;
GO

--Step 9: Viewing more details about TDE configuarion
SELECT
   d.name,
   k.encryption_state,
   k.encryptor_type,
   k.key_algorithm,
   k.key_length,
   k.percent_complete
FROM sys.dm_database_encryption_keys k
INNER JOIN sys.databases d
   ON k.database_id = d.database_id;
GO

--Step 10: Turning encryption off again
ALTER DATABASE TDE_Demo SET ENCRYPTION OFF;
GO

--Step 11: Bulk loading our TDE_Demo database
USE TDE_Demo;
CREATE TABLE dbo.DummyData(Id INT IDENTITY(1,1), DummyText VARCHAR(255));
GO

INSERT INTO dbo.DummyData (DummyText) 
SELECT TOP 1000000 
('This is Dummy data')
FROM sys.objects a
CROSS JOIN sys.objects b
CROSS JOIN sys.objects c
CROSS JOIN sys.objects d;
GO 350

--Step 12: Turning encryption back on agaian
ALTER DATABASE TDE_Demo SET ENCRYPTION ON;
GO

--Step 13: Polling to monitor the progress of encryption (Run in a different window)
DECLARE @state tinyint;
DECLARE @encyrption_progress 
    TABLE(sample_time DATETIME, percent_complete DECIMAL(5,2))

SELECT @state = k.encryption_state
FROM sys.dm_database_encryption_keys k
INNER JOIN sys.databases d
   ON k.database_id = d.database_id
WHERE d.name = 'TDE_Demo';

WHILE @state != 3
BEGIN
   INSERT INTO @encyrption_progress(sample_time, percent_complete)
   SELECT GETDATE(), percent_complete
   FROM sys.dm_database_encryption_keys k
   INNER JOIN sys.databases d
      ON k.database_id = d.database_id
   WHERE d.name = 'TDE_Demo';


   WAITFOR delay '00:00:05';

   SELECT @state = k.encryption_state
   FROM sys.dm_database_encryption_keys k
   INNER JOIN sys.databases d
      ON k.database_id = d.database_id
   WHERE d.name = 'TDE_Demo'; 
END

SELECT * FROM @encyrption_progress;
GO

--Step 14: Checking for blocking caused by encryption
SELECT *
FROM sys.dm_tran_locks
WHERE resource_type = 'ENCRYPTION_SCAN';
GO

