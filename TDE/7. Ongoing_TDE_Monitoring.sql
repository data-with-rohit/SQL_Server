

SELECT GETUTCDATE() As TimeUTC,
DB_NAME(database_id) AS DBName,
encryption_state, --Indicates whether the database is encrypted or not encrypted.
/*
0 = No database encryption key present, no encryption
1 = Unencrypted
2 = Encryption in progress
3 = Encrypted
4 = Key change in progress
5 = Decryption in progress
6 = Protection change in progress (The certificate or asymmetric key that is encrypting the database encryption key is being changed.)
*/
create_date, --Displays the date (in UTC) the encryption key was created.
regenerate_date,--Displays the date (in UTC) the encryption key was regenerated.
modify_date,--Displays the date (in UTC) the encryption key was modified.
set_date,--Displays the date (in UTC) the encryption key was applied to the database.
opened_date,--Shows when (in UTC) the database key was last opened.
--key_algorithm,
--key_length,
encryptor_thumbprint,--Shows the thumbprint of the encryptor.
encryptor_type,--Describes the encryptor.
percent_complete,--Percent complete of the database encryption state change. This will be 0 if there is no state change.
encryption_state_desc,--String that indicates whether the database is encrypted or not encrypted.
/*
NONE
UNENCRYPTED
ENCRYPTED
DECRYPTION_IN_PROGRESS
ENCRYPTION_IN_PROGRESS
KEY_CHANGE_IN_PROGRESS
PROTECTION_CHANGE_IN_PROGRESS
*/
encryption_scan_state, --Indicates the current state of the encryption scan.
/*
0 = No scan has been initiated, TDE is not enabled
1 = Scan is in progress.
2 = Scan is in progress but has been suspended, user can resume.
3 = Scan was aborted for some reason, manual intervention is required. Contact Microsoft Support for more assistance.
4 = Scan has been successfully completed, TDE is enabled and encryption is complete.
*/
encryption_scan_state_desc, --String that indicates the current state of the encryption scan.  for instance, if it is running or suspended.
/*
NONE
RUNNING
SUSPENDED
ABORTED
COMPLETE
*/
encryption_scan_modify_date --Displays the date (in UTC) the encryption scan state was last modified. we can use that to tell when a scan was suspended or resumed.
FROM sys.dm_database_encryption_keys