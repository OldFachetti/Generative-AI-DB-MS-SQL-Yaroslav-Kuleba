CREATE PROCEDURE sp_CustomerRevenue
(
    @FromYear INT = NULL,
    @ToYear INT = NULL,
    @Period VARCHAR(10) = 'Year',
    @CustomerID INT = NULL
)
AS
BEGIN
    BEGIN TRY
        -- Ensure the table [ErrorLog] exists
        IF NOT EXISTS (SELECT * FROM sys.tables WHERE name='ErrorLog')
        BEGIN
            CREATE TABLE [ErrorLog]
            (
                [ErrorID] INT PRIMARY KEY IDENTITY(1,1),
                [ErrorNumber] INT,
                [ErrorSeverity] INT,
                [ErrorMessage] VARCHAR(255),
                [CustomerID] INT,
                [Period] VARCHAR(8),
                [CreatedAt] DATETIME DEFAULT GETDATE()
            )
        END
        
        -- Set the default values for @FromYear and @ToYear if not provided
        SET @FromYear = ISNULL(@FromYear, (SELECT MIN(YEAR([Invoice Date Key])) FROM fact.sale))
        SET @ToYear = ISNULL(@ToYear, (SELECT MAX(YEAR([Invoice Date Key])) FROM fact.sale))
        
        -- Ensure the year is from 2000 onwards
        IF @FromYear < 2000 OR @ToYear < 2000
        BEGIN
            THROW 50001, 'The provided year(s) should be from 2000 onwards.', 1
        END
        
        DECLARE @TableName NVARCHAR(255)
        DECLARE @Query NVARCHAR(MAX)

        
        IF @CustomerID IS NOT NULL
        BEGIN
            SET @TableName = QUOTENAME(CONVERT(NVARCHAR, @CustomerID) + '_' + 
                             (SELECT Customer FROM Dimension.Customer WHERE [Customer Key] = @CustomerID) + '_' + 
                             CONVERT(NVARCHAR, @FromYear) + '_' + 
                             CONVERT(NVARCHAR, @ToYear) + '_' + 
                             LEFT(@Period, 1))
        END
        ELSE
        BEGIN
            SET @TableName = QUOTENAME('All_' + 
                             CONVERT(NVARCHAR, @FromYear) + '_' + 
                             CONVERT(NVARCHAR, @ToYear) + '_' + 
                             LEFT(@Period, 1))
        END
        
        -- Drop the table if it already exists
        SET @Query = 'IF OBJECT_ID(''' + @TableName + ''', ''U'') IS NOT NULL DROP TABLE ' + @TableName
        EXEC sp_executesql @Query


        -- Build the dynamic query to create the table and insert the results
        SET @Query = 
        'CREATE TABLE ' + @TableName + ' 
        (
            CustomerID INT,
            CustomerName VARCHAR(50),
            Period VARCHAR(10),
            Revenue DECIMAL(18,2)
        )

        INSERT INTO ' + @TableName + ' 
        SELECT 
            s.[Customer Key] AS CustomerID,
            c.Customer AS CustomerName,'

        -- Define the aggregation for the period
        IF @Period IN ('Month', 'M')
        BEGIN
            SET @Query += 'FORMAT(s.[Invoice Date Key], ''MMM yyyy'') AS Period,'
        END
        ELSE IF @Period IN ('Quarter', 'Q')
        BEGIN
            SET @Query += '''Q'' + CONVERT(VARCHAR, DATEPART(QUARTER, s.[Invoice Date Key])) + '' '' + CONVERT(VARCHAR, YEAR(s.[Invoice Date Key])) AS Period,'
        END
        ELSE
        BEGIN
            SET @Query += 'CONVERT(VARCHAR, YEAR(s.[Invoice Date Key])) AS Period,'
        END

        SET @Query +=
        'ISNULL(SUM(s.quantity * s.[unit price]), 0) AS Revenue
        FROM fact.sale s
        INNER JOIN Dimension.Customer c ON s.[Customer Key] = c.[Customer Key]
        WHERE YEAR(s.[Invoice Date Key]) BETWEEN ' + CONVERT(NVARCHAR, @FromYear) + ' AND ' + CONVERT(NVARCHAR, @ToYear)

        IF @CustomerID IS NOT NULL
        BEGIN
            SET @Query += ' AND s.[Customer Key] = ' + CONVERT(NVARCHAR, @CustomerID)
        END

        SET @Query += 
        ' GROUP BY s.[Customer Key], c.Customer, '
        
        IF @Period IN ('Month', 'M')
        BEGIN
            SET @Query += 'MONTH(s.[Invoice Date Key]), YEAR(s.[Invoice Date Key]), FORMAT(s.[Invoice Date Key], ''MMM yyyy'')'
        END
        ELSE IF @Period IN ('Quarter', 'Q')
        BEGIN
            SET @Query += 'DATEPART(QUARTER, s.[Invoice Date Key]), YEAR(s.[Invoice Date Key]), ''Q'' + CONVERT(VARCHAR, DATEPART(QUARTER, s.[Invoice Date Key])) + '' '' + CONVERT(VARCHAR, YEAR(s.[Invoice Date Key]))'
        END
        ELSE
        BEGIN
            SET @Query += 'YEAR(s.[Invoice Date Key])'
        END


        -- Execute the dynamic SQL
        EXEC sp_executesql @Query

    END TRY
    BEGIN CATCH
        INSERT INTO [ErrorLog]
        (
            [ErrorNumber],
            [ErrorSeverity],
            [ErrorMessage],
            [CustomerID],
            [Period]
        )
        VALUES
        (
            ERROR_NUMBER(),
            ERROR_SEVERITY(),
            ERROR_MESSAGE(),
            @CustomerID,
            @Period
        )
    END CATCH
END
