
create  database DNT_Sample_TDE


CREATE TABLE [Customers](
	[CustomerNumber] int NOT NULL,
	[FirstName] [varchar](50) NULL,
	[LastName] [varchar](50) NULL,
	[Phone] [varchar](50) NULL,
	[Address] [varchar](50) NULL,
	[City] [varchar](50) NULL,
	[State] [varchar](50) NULL,
	[Zip] [varchar](10) NULL,
	[Email] [varchar](50) NULL,
	[Birthdate] [varchar](50) NULL,
	[Anniversary] [varchar](50) NULL,
	[CCNumber] [varchar](20) NULL
	CONSTRAINT [PK_Customers] PRIMARY KEY CLUSTERED 
	(
	[CustomerNumber] ASC
)WITH (PAD_INDEX  = OFF, STATISTICS_NORECOMPUTE  = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS  = ON, ALLOW_PAGE_LOCKS  = ON) ON [PRIMARY]
) ON [PRIMARY]

GO

/********************************/


BULK 
INSERT Customers
        FROM 'F:\DNT_Springfiled\Security\Security_Part_2\customer.csv'
            WITH
    (
                FIELDTERMINATOR = ',',
                ROWTERMINATOR = '\n'
    )
GO
Select * from customers
--Create database master key
use DNT_Sample_TDE;
go
create master key encryption by password='Pass#12';
go

--Create certificate
create certificate DNT_Sample_TDE01 with subject='DNT_Sample_TDE';
go

--Create symmetric key

create symmetric key CCNumber_key_01 
with algorithm=triple_des
encryption by certificate DNT_Sample_TDE01;
go


--add new column for encrypted data

alter table customers
add EncryptedCCNumbers varbinary(128);
go

--Encrypt and copy data to new column
open symmetric key CCNumber_key_01
decryption by certificate DNT_Sample_TDE01;

update Customers
set EncryptedCCNumbers = 
ENCRYPTBYKEY (key_guid('CCnumber_key_01'),CCnumber);
close symmetric key CCNumber_Key_01;
go

select * from  customers


---to see the with decryption option /column decryption

open symmetric key CCNumber_key_01
decryption by certificate DNT_Sample_TDE01;

select convert (varchar, 
DECRYPTBYKEY(EncryptedCCNumbers)) as [DeCrypted CC Numbers]
from Customers;
close symmetric key ccNumber_key_01;
go
