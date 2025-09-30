USE master;
SELECT name, subject, expiry_date
FROM sys.certificates
WHERE name = 'MyTDECert';

USE master;
CREATE CERTIFICATE MyTDECert_new
WITH SUBJECT = 'Rotate the certificate used for TDE in the TDE_Demo database',
EXPIRY_DATE = '20301231';

USE TDE_Demo;
ALTER DATABASE ENCRYPTION KEY
ENCRYPTION BY SERVER CERTIFICATE MyTDECert_with_longevity;
