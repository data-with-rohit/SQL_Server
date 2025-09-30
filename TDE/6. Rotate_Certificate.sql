USE master;
SELECT name, subject, expiry_date
FROM sys.certificates
WHERE name = 'MyTDECert';

USE master;
CREATE CERTIFICATE MyTDECert_with_longevity
WITH SUBJECT = 'Certificate used for TDE in the TDE_Demo database for years to come',
EXPIRY_DATE = '20251231';

USE TDE_Demo;
ALTER DATABASE ENCRYPTION KEY
ENCRYPTION BY SERVER CERTIFICATE MyTDECert_with_longevity;