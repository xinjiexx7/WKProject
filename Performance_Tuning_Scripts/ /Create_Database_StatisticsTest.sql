CREATE DATABASE [StatisticsTest]
GO
 
ALTER DATABASE [StatisticsTest] SET   AUTO_CREATE_STATISTICS OFF
ALTER DATABASE [StatisticsTest] SET   AUTO_UPDATE_STATISTICS OFF
ALTER DATABASE [StatisticsTest] SET   AUTO_UPDATE_STATISTICS_ASYNC OFF
GO
 
USE   [StatisticsTest]
GO
CREATE TABLE [SalesOrderDetail](
        [SalesOrderID]   [int] NOT NULL,
        [SalesOrderDetailID]   [int] NOT NULL,
        [CarrierTrackingNumber]   [nvarchar](25)   NULL,
        [OrderQty]   [smallint] NOT NULL,
        [ProductID]   [int] NOT NULL,
        [SpecialOfferID]   [int] NOT NULL,
        [UnitPrice]   [money] NOT NULL,
        [UnitPriceDiscount]   [money] NOT NULL,
        [LineTotal]   money NOT NULL,
        [rowguid]   [uniqueidentifier] ROWGUIDCOL  NOT NULL,
        [ModifiedDate]   [datetime] NOT NULL,
) ON [PRIMARY]
GO
 
INSERT INTO [SalesOrderDetail]
SELECT * FROM   [AdventureWorks2016].[Sales].[SalesOrderDetail]
GO 10

--Now let’s run these two queries and have a look on their execution plan. Notice the yellow exclamation mark on the “Table Scan” operator; this indicates the missing statistics. Further, notice between the “Actual Number of Rows” and “Estimated Number of Rows” that there is a huge difference. This means, obviously, the execution plan used for query execution was not optimal.

select * from [dbo].[SalesOrderDetail]
where   ProductID <= 800;

select * from [dbo].[SalesOrderDetail]
where   ProductID >= 800;


select * from [dbo].[SalesOrderDetail]
where   ProductID <= 800;

CREATE NONCLUSTERED INDEX   [NCI_SalesOrderDetail_ProductID]
ON   [dbo].[SalesOrderDetail] ([ProductID])

drop index [SalesOrderDetail].NCI_SalesOrderDetail_ProductID
select * from [dbo].[SalesOrderDetail]
where   ProductID >= 800;


select * from [dbo].[SalesOrderDetail]
where   ProductID <= 800;




http://www.databasejournal.com/features/mssql/importance-of-statistics-and-how-it-works-in-sql-server-part-1.html
