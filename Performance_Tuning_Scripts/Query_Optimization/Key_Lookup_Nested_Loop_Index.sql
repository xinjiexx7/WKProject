USE [AdventureWorks] 
GO 
SET NOCOUNT ON --do not count each row in the query result 
-- Create New Table Empty Table 
SELECT * INTO [dbo].[address] 
FROM AdventureWorks2016.[person].[address] 
GO 

--create cluster index
CREATE CLUSTERED INDEX [IX_Addressid] ON address ([addressID] ASC) 

SELECT *  FROM address  
WHERE city ='new york' ---cluster index scan becase of *

SELECT *  FROM address  
WHERE city ='new york' ----cluster index scan becase of *

SELECT city,PostalCode 
FROM address  
WHERE city ='new york' ---cluster index scan becase of city,PostalCode does not have index

CREATE NONCLUSTERED INDEX [IX_city]  
ON address ([city] ASC) 

SELECT city,PostalCode 
FROM address  
WHERE city ='new york' --neested loop/key look up  becuase one colum found index but 
--other cluumn does not find index/  PostalCode does not have index 
  
SELECT city,PostalCode 
FROM address  
WHERE city ='new york' 

--create non cluster index on PostalCode
CREATE NONCLUSTERED INDEX [IX_PostalCode]  
ON address ([PostalCode] ASC)  

SELECT city,PostalCode 
FROM address  
WHERE city ='new york' --neested loop/key look up bucasae two separate index 

drop index [IX_PostalCode]  ON address  
drop index [IX_city]  ON address  

--create covering index 
CREATE NONCLUSTERED INDEX [IX_city PostalCode]  
ON address (city,postalcode) 

 set statistics io on   --2--real  85
SELECT city,PostalCode 
FROM address  
WHERE city ='new york' --remove key look up becase of covering index 

drop index [IX_city PostalCode]  ON address 

--create include index becuase less logical reads 
CREATE NONCLUSTERED INDEX [IX_city PostalCode]  
ON address (city) include(postalcode) 

set statistics io on   --2   -real  5
SELECT city,PostalCode 
FROM address  
WHERE city ='new york' 
