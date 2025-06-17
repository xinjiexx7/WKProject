--create table
CREATE TABLE EmployeeData
(MemberID INT IDENTITY PRIMARY KEY,
FirstName varchar(100)	MASKED WITH (Function = 'default()'),
LastName varchar(100) MASKED WITH (Function = 'partial(1,"XXX",1)'),
Email varchar(100) MASKED WITH (function = 'email()'),
Age int MASKED WITH (Function = 'default()'),
JoinDate date MASKED WITH (Function = 'default()'),
LeaveDays int MASKED WITH (FUNCTION = 'random(1,5)')
)

--insert data into table

INSERT INTO EmployeeData
(FirstName, LastName, Email,Age,JoinDate,LeaveDays)
VALUES
('Dinesh','Asanka','Dineshasanka@gmail.com',35,'2020-01-01',12),
('Saman','Perera','saman@somewhere.lk',45,'2020-01-01',1),
('Julian','Soman','j.soman@uniersity.edu.org',37,'2019-11-01',1),
('Telishia','Mathewsa','tm1@rose.lk',51,'2018-01-01',6)

--read data from table 
select * from EmployeeData

--create mask user and grant user 
CREATE USER MaskUser WITHOUT Login;
GRANT SELECT ON EmployeeData TO MaskUser

---excute as a mask user 

EXECUTE AS User= 'MaskUser';
SELECT * FROM EmployeeData
REVERT

--When you need to provide the UNMASK permissions to the above user.
GRANT UNMASK TO MaskUser

EXECUTE AS User= 'MaskUser';
SELECT * FROM EmployeeData
REVERT

--find out what are the masked columns in the database, you can use the following script.
SELECT OBJECT_NAME(OBJECT_ID) TableName, 
Name ,
is_masked,
masking_function
FROM sys.masked_columns

---remove mask from column 
ALTER TABLE dbo.EmployeeData
ALTER COLUMN FirstName DROP MASKED;




