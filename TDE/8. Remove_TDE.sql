/*
Check current TDE status — verify which databases are encrypted.
Turn off encryption on the target database (ALTER DATABASE … SET ENCRYPTION OFF).
Monitor decryption progress until the state shows UNENCRYPTED.
Drop the Database Encryption Key (DEK) from the user database.
Recheck database status to confirm decryption is complete.
Drop the TDE certificate from the master database.
Drop the Database Master Key (DMK) from the master database.
Restart SQL Server to decrypt tempdb and finalize cleanup.
*/

----Step 1: Check TDE on SQL Server Instance
SELECT DB_Name(database_id) As [DB Name], encryption_state, encryption_state_desc
FROM sys.dm_database_encryption_keys
GO
SELECT name, is_encrypted
FROM sys.databases
Go

----Step 2: Replace “TDE_Demo” with your target user database name
USE master;
GO
ALTER DATABASE TDE_Demo SET ENCRYPTION OFF;
GO

----Step 3: Monitor the decryption process and wait until encryption_state_desc says "UNENCRYPTED" 
--or encryption_state has a value of 1 and percent_complete has value 0.
SELECT GETUTCDATE() As TimeUTC,
DB_NAME(database_id) AS DBName,
encryption_state, --Indicates whether the database is encrypted or not encrypted.
percent_complete,--Percent complete of the database encryption state change. This will be 0 if there is no state change.
encryption_state_desc,--String that indicates whether the database is encrypted or not encrypted.
encryption_scan_state, --Indicates the current state of the encryption scan.
encryption_scan_state_desc, --String that indicates the current state of the encryption scan.  for instance, if it is running or suspended.
encryption_scan_modify_date --Displays the date (in UTC) the encryption scan state was last modified. we can use that to tell when a scan was suspended or resumed.
FROM sys.dm_database_encryption_keys


----Step 4:  Drop Database Encryption key
USE TDE_Demo;
GO
DROP DATABASE ENCRYPTION KEY;
GO

----Step 5:  Check the DB status again using the query from Step 3.

---- Step 6: Drop Certificate
USE master
Go
DROP CERTIFICATE [MyTDECert];
Go

---- Step 7: Drop master key
USE master
Go
DROP MASTER KEY;
GO

----Step 8: Restart SQL Server. This ensures that tempdb is decrypted as well.