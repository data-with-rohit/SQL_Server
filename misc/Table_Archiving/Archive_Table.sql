/*
Background: One fellow DBA reached out and asked help with an archival script. He requested the table structure so i can tailor build one. Table structure is also attached in this folder for you to refer and understand why i created this script this way.
Reason for the first loop on EmployeeNumber: Table Primary Key has EmployeeNumber as the leading column and this coilumn isnt highly unique which means each employee has a lot of data.
Reason for the second loop on Date: This loop was added to ensure that we do not end up archiving data which we still need in the main table because this loop only pulls DISTINCT DATEs which are newer than DateThreshold.
This also has a waitfor statement to give some breathing room to your HA/DR solution if you have one. 
Please ensure that archive table already exists. Ensure to use proper DB name. 
Most importantly - This is not one solution fit all scenerio. You may have different requirement but you can always tune this code to your needs or at least get some idea from here.

Please test it properly in NON-PROD before running in PROD and use it at your own risk.
*/

SET NOCOUNT ON;

----------------------------------------------------------------------------------------------------
-- CONFIGURATION
----------------------------------------------------------------------------------------------------

DECLARE @BatchSize INT = 500; -- rows per delete batch
DECLARE @DateThreshold DATE = '2020-06-01'; -- Archive records where [StartDate] is OLDER than this date

-- Specify your Archive Table name and database here.
-- NOTE: The target table (FCaps_HR_Attendance_Archive) MUST have the same columns as the source.
DECLARE @ArchiveTable SYSNAME = N'TSQLDemoDB.dbo.FCaps_HR_Attendance_Archive';

----------------------------------------------------------------------------------------------------
-- TEMP TABLES TO HOLD LOOPING KEYS
----------------------------------------------------------------------------------------------------

-- 1. Temp table to hold distinct Employee Numbers to process
IF OBJECT_ID('tempdb..#DeleteEmployees') IS NOT NULL DROP TABLE #DeleteEmployees;

CREATE TABLE #DeleteEmployees
(
    PK INT IDENTITY(1,1) PRIMARY KEY,
    EmployeeNumber VARCHAR(10) NOT NULL
);

-- 2. Temp table to hold distinct Start Dates for the current employee
IF OBJECT_ID('tempdb..#DeleteDates') IS NOT NULL DROP TABLE #DeleteDates;

CREATE TABLE #DeleteDates
(
    PK INT IDENTITY(1,1) PRIMARY KEY,
    StartDate DATETIME NOT NULL
);

----------------------------------------------------------------------------------------------------
-- POPULATE EMPLOYEE LOOP KEYS
----------------------------------------------------------------------------------------------------

INSERT INTO #DeleteEmployees (EmployeeNumber)
SELECT DISTINCT EmployeeNumber FROM dbo.FCaps_HR_Attendance WITH (NOLOCK)
WHERE StartDate < @DateThreshold ORDER BY EmployeeNumber;

----------------------------------------------------------------------------------------------------
-- MAIN EMPLOYEE LOOP VARIABLES
----------------------------------------------------------------------------------------------------

DECLARE @TotalEmployees INT = (SELECT COUNT(*) FROM #DeleteEmployees);
DECLARE @EmpCounter INT = 1;
DECLARE @CurrentEmployeeNumber VARCHAR(10);

----------------------------------------------------------------------------------------------------
-- MAIN EMPLOYEE LOOP
----------------------------------------------------------------------------------------------------

WHILE @EmpCounter <= @TotalEmployees
BEGIN
    -- Get the current Employee Number to process
    SELECT @CurrentEmployeeNumber = EmployeeNumber FROM #DeleteEmployees WHERE PK = @EmpCounter;

    PRINT '--------------------------------------------------';
    PRINT 'Processing Employee: ' + @CurrentEmployeeNumber;
    PRINT '--------------------------------------------------';

    -- Clear and repopulate the Date Keys for the current employee
    TRUNCATE TABLE #DeleteDates;

    INSERT INTO #DeleteDates (StartDate)
    SELECT DISTINCT StartDate FROM dbo.FCaps_HR_Attendance WITH (NOLOCK)
    WHERE EmployeeNumber = @CurrentEmployeeNumber AND StartDate < @DateThreshold ORDER BY StartDate;

    ----------------------------------------------------------------
    -- DATE LOOP VARIABLES
    ----------------------------------------------------------------

    DECLARE @TotalDates INT = (SELECT COUNT(*) FROM #DeleteDates);
    DECLARE @DateCounter INT = 1;
    DECLARE @CurrentStartDate DATETIME;

    ----------------------------------------------------------------
    -- BATCHED DELETE LOOP (NESTED)
    ----------------------------------------------------------------
    
    WHILE @DateCounter <= @TotalDates
    BEGIN
        -- Get the current Start Date to process
        SELECT @CurrentStartDate = StartDate FROM #DeleteDates WHERE PK = @DateCounter;

        PRINT '  -> Processing date: ' + CONVERT(VARCHAR(30), @CurrentStartDate, 120);

        -- BATCHED DELETE LOOP FOR THE CURRENT EMPLOYEE AND DATE
        
        DECLARE @RowsDeleted INT = 1;
        WHILE @RowsDeleted > 0
        BEGIN
            -- Archive/Delete based on EmployeeNumber and StartDate (the first two parts of the PK)
            DELETE TOP (@BatchSize) FROM dbo.FCaps_HR_Attendance
            
            -- Use OUTPUT INTO to simultaneously archive the data
            OUTPUT deleted.* INTO TSQLDemoDB.dbo.FCaps_HR_Attendance_Archive
            
            WHERE EmployeeNumber = @CurrentEmployeeNumber
              AND StartDate = @CurrentStartDate;
            
            SET @RowsDeleted = @@ROWCOUNT
            
            IF @RowsDeleted > 0
            BEGIN
                PRINT '     | Deleting ' + CAST(@RowsDeleted AS VARCHAR(10)) + ' rows...';
                WAITFOR DELAY '00:00:02'; -- 2 sec pause for AG/DR log catch-up
            END
        END
        
        SET @DateCounter = @DateCounter + 1;
    END

    SET @EmpCounter = @EmpCounter + 1;
END

PRINT '==================================================';
PRINT 'Archive of FCaps_HR_Attendance completed successfully!';
PRINT '==================================================';

-- Clean up temp tables
DROP TABLE #DeleteDates;
DROP TABLE #DeleteEmployees;
GO
