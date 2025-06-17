
USE AdventureWorks
GO
-- Build Sample DB
SELECT *
INTO DNTSalesOrderDetail
FROM [Sales].[SalesOrderDetail]
GO

----------------------------------------------------------------------------------
-- Clustered Index Scan and Clustered Index Seek
----------------------------------------------------------------------------------
-- CTRL+M
-- Build Sample DB
SET STATISTICS IO ON
GO
SELECT * FROM DNTSalesOrderDetail
-- logical reads 1495
GO
SELECT *
FROM DNTSalesOrderDetail
WHERE SalesOrderID = 60726 AND SalesOrderDetailID = 74616
-- logical reads 1495--subtree cost --1.2434
GO

-- Create Clustered Index
ALTER TABLE DNTSalesOrderDetail 
ADD CONSTRAINT [PK_DNTSalesOrderDetail_SalesOrderID_SalesOrderDetailID] 
PRIMARY KEY CLUSTERED 
(
	[SalesOrderID] ASC,
	[SalesOrderDetailID] ASC
)
GO

SELECT * FROM DNTSalesOrderDetail
-- logical reads 1502---Subtreecost-1.2434

GO
SELECT *FROM DNTSalesOrderDetail
WHERE SalesOrderID = 60726 AND SalesOrderDetailID = 74616
--logical reads 3 Because Index seek --subtree cost .00328
--now change colum in where clause 
GO
SELECT ProductID
FROM DNTSalesOrderDetail
WHERE  ProductID = 799 
-- logical reads 1502-- sutreecost 1.24
-- Clean up
/*
ALTER TABLE [dbo].[DNTSalesOrderDetail] 
DROP CONSTRAINT [PK_DNTSalesOrderDetail_SalesOrderID_SalesOrderDetailID]
GO
*/
SET STATISTICS IO OFF
GO

----------------------------------------------------------------------------------
-- Non-Clustered Index Scan
----------------------------------------------------------------------------------
-- Create a sample non clustered index

CREATE NONCLUSTERED INDEX [IX_DNTSalesOrderDetail_OrderQty_ProductID_1] 
ON DNTSalesOrderDetail
([ProductID])
GO
---create non cluster index fixed the issue 
SELECT ProductID
FROM DNTSalesOrderDetail
WHERE  ProductID = 799 
--two column

SET STATISTICS IO ON
GO

-- Sample Query with Where clause
SELECT  ProductID, OrderQty
FROM DNTSalesOrderDetail
WHERE ProductID = 799
GO
-- Method : Add OrderQty in WHERE clause
SELECT ProductID, OrderQty
FROM DNTSalesOrderDetail
WHERE ProductID = 799 AND OrderQty > 0 
GO

-- Method 2: Create Index with ProductID as first col
CREATE NONCLUSTERED INDEX [IX_DNTSalesOrderDetail_ProductID_OrderQty] 
ON DNTSalesOrderDetail
([ProductID],[OrderQty])
GO

SELECT ProductID, OrderQty
FROM DNTSalesOrderDetail
WHERE ProductID = 799 
GO

SELECT ProductID, OrderQty
FROM DNTSalesOrderDetail
WHERE ProductID = 799 AND OrderQty > 0 

-- Clean up
SET STATISTICS IO OFF
GO
/*
DROP INDEX [IX_DNTSalesOrderDetail_OrderQty_ProductID] ON [dbo].[DNTSalesOrderDetail]
GO
DROP INDEX [IX_DNTSalesOrderDetail_ProductID_OrderQty] ON [dbo].[DNTSalesOrderDetail]
GO 
*/
drop table DNTSalesOrderDetail
