--to see master key only in code no GUI Availabel 
SELECT d.is_master_key_encrypted_by_server
FROM sys.databases AS d
WHERE d.name = 'master';

--result should be 1 means-- MK exist and 0 means No MK. only one master key support per server 

---create master key
USE master;
GO
CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'pass#12';
go


---Create Certificate protected by master key

Create CERTIFICATE DNTServerCert WITH SUBJECT = 'DNT DEK Certificate'
go
-- to see the certificate 

select * from sys.certificates

--  Also create a backup of the certificate with the private key and store it in a secure location. (
/* Note that the private key is stored in a separate file—be sure to keep both files). 
Be sure to maintain backups of the certificate as data loss may occur otherwise. */

BACKUP CERTIFICATE DNTServerCert TO FILE = 'C:\Software\DNTServerCert'

   WITH PRIVATE KEY (

         FILE = 'C:\Software\private_key_file',

         ENCRYPTION BY PASSWORD = 'pass#12');
 --Perform the following steps in the user database. These require CONTROL permissions on the database.

--Create the database encryption key (DEK) encrypted with the certificate designated from step 2 above. This certificate 
--is referenced as a server certificate to distinguish it from other certificates that may be stored in the user database.        
USE   DNT_Sample_TDE
GO

CREATE DATABASE ENCRYPTION KEY
WITH  ALGORITHM = AES_128
ENCRYPTION BY SERVER CERTIFICATE DNTServerCert
GO

 --Enable TDE. This command starts a background thread (referred to as the encryption scan), which runs asynchronously.
ALTER DATABASE DNT_Sample_TDE
SET ENCRYPTION on
GO


--To monitor progress, query the sys.dm_database_encryption_keys view (the VIEW SERVER STATE permission is required) as in the following example
select DB_NAME(database_id), encryption_state
from sys.dm_database_encryption_keys
--or 
SELECT
    DB_NAME(database_id) AS DatabaseName,
    encryption_state,
    CASE encryption_state
        WHEN 0 THEN 'No Encryption'
        WHEN 1 THEN 'Unencrypted'
        WHEN 2 THEN 'Encryption in Progress'
        WHEN 3 THEN 'Encrypted'
        WHEN 4 THEN 'Key Change in Progress'
        WHEN 5 THEN 'Decryption in Progress'
        WHEN 6 THEN 'Protection Changes in Progress'
    END AS EncryptionState,
    key_algorithm,
    key_length
FROM sys.dm_database_encryption_keys;
GO

  ---backup the database 
  BACKUP DATABASE DNT_Sample_TDE
    TO DISK = 'C:\Backup\DNT_Sample_TDE_Encrypted.bak';


---GO TO ANOHTER INSTANCE TRY  RESTORE DATABASE 
RESTORE DATABASE DNT_Sample_TDE
    FROM DISK = 'C:\Backup\DNT_Sample_TDE_Encrypted.bak';
GO

--- RESTORE DATABASE IN 2ND SERVER IT WILL FAILBECUASE OF THE ENCRIPTION 

--CREATE MASTER KEY IN 2ND INSTANCE 

CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'pass#12';
go
---create CERTIFICATE


--  Also create a backup of the certificate with the private key and store it in a secure location. (
/* Note that the private key is stored in a separate file—be sure to keep both files). 
Be sure to maintain backups of the certificate as data loss may occur otherwise. */

CREATE CERTIFICATE DNTServerCert2 FROM FILE = 'E:cer\DNTServerCert'

   WITH PRIVATE KEY (

         FILE = 'E:cer\private_key_file',

         DECRYPTION BY PASSWORD = 'pass#12');


---RESTORE DATABASE 
RESTORE DATABASE DNT_Sample_TDE
    FROM DISK = 'C:\Backup\DNT_Sample_TDE_Encrypted.bak';
GO

---find expire certificate 

select s.name, c.name, c.start_date, c.expiry_date
	from sys.services s
	join sys.certificates c on s.principal_id = c.principal_id
	where  c.is_active_for_begin_dialog = 1
		and GETUTCDATE() BETWEEN c.start_date AND c.expiry_date
		and s.service_id > 2;
		
		
		--Set database encryption off
ALTER DATABASE DNT_Sample_TDE SET ENCRYPTION off
--drop database encryption key
Drop MASTER KEY 
--drop certificate at master
Drop CERTIFICATE DNTServerCert 
--create certificate with below command to have new expiry date
Create CERTIFICATE DNT_Sample_TDE01 with subject = 'Certificate Subject',
START_DATE = '9/10/2012',EXPIRY_DATE='9/16/2050';
--create database encryption key
--Set database encryption on

DROP DATABASE ENCRYPTION KEY  --select database 

--verify CERTIFICATE 
select * from sys.certificates WHERE pvt_key_encryption_type <>'NA'

--verify ENCRYPTION KEY DETAILS 
select create_date,key_algorithm,key_length,encryptor_type from sys.dm_database_encryption_keys
