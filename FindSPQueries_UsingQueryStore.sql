/*=======================================================================================================================
  File:     FindSPQueries_UsingQueryStore.sql

  SQL Server Versions: 2016, 2017
-------------------------------------------------------------------------------------------------------------------------
  Written by Erin Stellato, SQLskills.com

  In support of post: 
  https://www.pass.org/Community/PASSBlog/tabid/1476/entryid/898/Finding-the-Slowest-Query-in-a-Stored-Procedure.aspx
  
  (c) 2018, SQLskills.com. All rights reserved.

  For more scripts and sample code, check out 
    http://www.SQLskills.com

  You may alter this code for your own *non-commercial* purposes. You may
  republish altered code as long as you include this copyright and give due
  credit, but you must obtain prior permission before blogging this code.
  
  THIS CODE AND INFORMATION ARE PROVIDED "AS IS" WITHOUT WARRANTY OF 
  ANY KIND, EITHER EXPRESSED OR IMPLIED, INCLUDING BUT NOT LIMITED 
  TO THE IMPLIED WARRANTIES OF MERCHANTABILITY AND/OR FITNESS FOR A
  PARTICULAR PURPOSE.
=======================================================================================================================*/

/*
	Enable Query Store
*/
ALTER DATABASE [WideWorldImporters] 
	SET QUERY_STORE = ON;
GO
ALTER DATABASE [WideWorldImporters] 
	SET QUERY_STORE (
	OPERATION_MODE = READ_WRITE, 
	INTERVAL_LENGTH_MINUTES = 10
	);
GO

/*
	Do not run in a Production database unless you want
	to remove all Query Store data
*/
ALTER DATABASE [WideWorldImporters] 
	SET QUERY_STORE CLEAR;
GO

/*
	Create SP for testing
*/
USE [WideWorldImporters];
GO

DROP PROCEDURE IF EXISTS [Sales].[usp_GetCustomerDetail];
GO

CREATE PROCEDURE [Sales].[usp_GetCustomerDetail]
	@CustomerName NVARCHAR(100)
AS	
	
	CREATE TABLE #CustomerList (
		[RowID] INT IDENTITY (1,1),
		[CustomerID] INT,
		[CustomerName] NVARCHAR (100)
		);

	INSERT INTO #CustomerList (
		[CustomerID], 
		[CustomerName]
		)
	SELECT 
		[CustomerID], 
		[CustomerName]
	FROM [Sales].[Customers]
	WHERE [CustomerName] LIKE @CustomerName
	UNION
	SELECT 
		[CustomerID], 
		[CustomerName]
	FROM [Sales].[Customers_Archive]
	WHERE [CustomerName] LIKE @CustomerName;

	SELECT 
		[o].[CustomerID], 
		[o].[OrderID],
		[il].[InvoiceLineID],
		[o].[OrderDate], 
		[i].[InvoiceDate],
		[ol].[StockItemID], 
		[ol].[Quantity],
		[ol].[UnitPrice],
		[il].[LineProfit]
	INTO #CustomerOrders
	FROM [Sales].[Orders] [o]
	INNER JOIN [Sales].[OrderLines] [ol] 
		ON [o].[OrderID] = [ol].[OrderID]
	INNER JOIN [Sales].[Invoices] [i]	
		ON [o].[OrderID] = [i].[OrderID]
	INNER JOIN [Sales].[InvoiceLines] [il] 
		ON [i].[InvoiceID] =  [il].[InvoiceID]		
		AND [il].[StockItemID] = [ol].[StockItemID]
		AND [il].[Quantity] = [ol].[Quantity]
		AND [il].[UnitPrice] = [ol].[UnitPrice]
	WHERE [o].[CustomerID] IN (SELECT [CustomerID] FROM #CustomerList);

	SELECT 
		[cl].[CustomerName],
		[si].[StockItemName],
		SUM([co].[Quantity]) AS [QtyPurchased],
		SUM([co].[Quantity]*[co].[UnitPrice]) AS [TotalCost],
		[co].[LineProfit],
		[co].[OrderDate],
		DATEDIFF(DAY,[co].[OrderDate],[co].[InvoiceDate]) AS [DaystoInvoice]
	FROM #CustomerOrders [co]
	INNER JOIN #CustomerList [cl]
		ON [co].[CustomerID] = [cl].[CustomerID]
	INNER JOIN [Warehouse].[StockItems] [si]
		ON [co].[StockItemID] = [si].[StockItemID]
	GROUP BY [cl].[CustomerName], [si].[StockItemName],[co].[InvoiceLineID], [co].[LineProfit], [co].[OrderDate], DATEDIFF(DAY,[co].[OrderDate],[co].[InvoiceDate])
	ORDER BY [co].[OrderDate];

GO


/*
	Run SP with different input parameters
*/
EXEC [Sales].[usp_GetCustomerDetail] N'Alvin Bollinger';
GO 10

EXEC [Sales].[usp_GetCustomerDetail] N'Tami Braggs';
GO 10

EXEC [Sales].[usp_GetCustomerDetail] N'Logan Dixon';
GO 10

EXEC [Sales].[usp_GetCustomerDetail] N'Tara Kotadia';
GO 10


/*
	Check to see what queries exist for the SP
*/
SELECT
	[qsq].[query_id], 
	[qsp].[plan_id], 
	[qsq].[object_id], 
	[qst].[query_sql_text], 
	ConvertedPlan = TRY_CONVERT(XML, [qsp].[query_plan])
FROM [sys].[query_store_query] [qsq] 
JOIN [sys].[query_store_query_text] [qst]
	ON [qsq].[query_text_id] = [qst].[query_text_id]
JOIN [sys].[query_store_plan] [qsp] 
	ON [qsq].[query_id] = [qsp].[query_id]
WHERE [qsq].[object_id] = OBJECT_ID(N'Sales.usp_GetCustomerDetail');
GO
  

/*
	Look at runtime stats for each query in the SP
*/
SELECT
	[qsq].[query_id], 
	[qsp].[plan_id], 
	[qsq].[object_id], 
	[rs].[runtime_stats_interval_id],
	[rsi].[start_time],
	[rsi].[end_time],
	[rs].[count_executions],
	[rs].[avg_duration],
	[rs].[avg_cpu_time],
	[rs].[avg_logical_io_reads],
	[rs].[avg_rowcount],
	[qst].[query_sql_text], 
	ConvertedPlan = TRY_CONVERT(XML, [qsp].[query_plan])
FROM [sys].[query_store_query] [qsq] 
JOIN [sys].[query_store_query_text] [qst]
	ON [qsq].[query_text_id] = [qst].[query_text_id]
JOIN [sys].[query_store_plan] [qsp] 
	ON [qsq].[query_id] = [qsp].[query_id]
JOIN [sys].[query_store_runtime_stats] [rs] 
	ON [qsp].[plan_id] = [rs].[plan_id]
JOIN [sys].[query_store_runtime_stats_interval] [rsi]
	ON [rs].[runtime_stats_interval_id] = [rsi].[runtime_stats_interval_id]
WHERE [qsq].[object_id] = OBJECT_ID(N'Sales.usp_GetCustomerDetail')
AND [rs].[last_execution_time] > DATEADD(HOUR, -1, GETUTCDATE())  
AND [rs].[execution_type] = 0
ORDER BY [qsq].[query_id], [qsp].[plan_id], [rs].[runtime_stats_interval_id];
GO


					 

/*
	Run the SP for a while to create more data
*/
DECLARE @CustomerID INT = 801
DECLARE @CustomerName NVARCHAR(100)

WHILE 1=1
BEGIN

	SELECT @CustomerName = SUBSTRING([CustomerName], 1, 10) + '%'
	FROM [Sales].[Customers]
	WHERE [CustomerID] = @CustomerID;

	EXEC [Sales].[usp_GetCustomerDetail] @CustomerName;

	IF @CustomerID < 1092
	BEGIN
		SET @CustomerID = @CustomerID + 1
	END
	ELSE
	BEGIN
		SET @CustomerID = 801
	END

END


/*
	Check aggregate runtime stats for the SP
*/
SELECT
	[qsq].[query_id], 
	[qsp].[plan_id], 
	OBJECT_NAME([qsq].[object_id]) AS [ObjectName], 
	SUM([rs].[count_executions]) AS [TotalExecutions],
	AVG([rs].[avg_duration]) AS [Avg_Duration],
	AVG([rs].[avg_cpu_time]) AS [Avg_CPU],
	AVG([rs].[avg_logical_io_reads]) AS [Avg_LogicalReads],
	MIN([qst].[query_sql_text]) AS[Query]
FROM [sys].[query_store_query] [qsq] 
JOIN [sys].[query_store_query_text] [qst]
	ON [qsq].[query_text_id] = [qst].[query_text_id]
JOIN [sys].[query_store_plan] [qsp] 
	ON [qsq].[query_id] = [qsp].[query_id]
JOIN [sys].[query_store_runtime_stats] [rs] 
	ON [qsp].[plan_id] = [rs].[plan_id]
JOIN [sys].[query_store_runtime_stats_interval] [rsi]
	ON [rs].[runtime_stats_interval_id] = [rsi].[runtime_stats_interval_id]
WHERE [qsq].[object_id] = OBJECT_ID(N'Sales.usp_GetCustomerDetail')
AND [rs].[last_execution_time] > DATEADD(HOUR, -1, GETUTCDATE())  
AND [rs].[execution_type] = 0
GROUP BY [qsq].[query_id], [qsp].[plan_id], OBJECT_NAME([qsq].[object_id])
ORDER BY AVG([rs].[avg_cpu_time]) DESC;
