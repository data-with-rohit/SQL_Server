use master
go
SELECT * FROM sys.symmetric_keys 
go
SELECT name AS DatabaseName, is_master_key_encrypted_by_server FROM sys.databases;
GO
SELECT name,subject,expiry_date,pvt_key_encryption_type_desc FROM sys.certificates;
GO
SELECT db.name AS DatabaseName,c.name AS CertificateName,c.thumbprint FROM sys.databases AS db
JOIN sys.dm_database_encryption_keys AS dek ON db.database_id = dek.database_id
LEFT JOIN master.sys.certificates AS c ON dek.encryptor_thumbprint = c.thumbprint;
GO
