CREATE OR ALTER PROCEDURE [dbo].[sp_monitor_disk_free_space]
@Recipients varchar(200)
AS

/****** 
This script uses PowerShell and T-SQL
Collects disk usage and sends an HTML email with thresholds.
If any drive is in the red zone, the subject includes "URGENT".
The HTML report has proper 2px borders and color-coded Free Space (GB) and Free Space %.
******/
SET NOCOUNT ON

DECLARE @svrName NVARCHAR(256);
DECLARE @ComputerName NVARCHAR(256);
DECLARE @InstancePos INT;
DECLARE @sql NVARCHAR(4000);
DECLARE @mailprofile NVARCHAR(50);

-- Get the server and computer name
SET @svrName = CAST(SERVERPROPERTY('ServerName') AS NVARCHAR(256));
SET @InstancePos = CHARINDEX('\', @svrName);
SET @ComputerName = CASE WHEN @InstancePos > 0 THEN LEFT(@svrName, @InstancePos - 1) ELSE @svrName END;

-- PowerShell command to get drive space info
SET @sql = 'powershell.exe -c "Get-WmiObject -ComputerName ' 
    + QUOTENAME(@ComputerName,'''') 
    + ' -Class Win32_Volume -Filter ''DriveType = 3'' | select name,capacity,freespace | foreach{$_.name+''|''+$_.capacity/1048576+''%''+$_.freespace/1048576+''*''}"';

DROP TABLE IF EXISTS #output;
DROP TABLE IF EXISTS #DriveSpace;

CREATE TABLE #output (line VARCHAR(255));

INSERT #output
EXEC xp_cmdshell @sql;

CREATE TABLE #DriveSpace
(
    ServerName SYSNAME,
    [PhysicalName] SYSNAME,
    [Total Disk Capacity(GB)] FLOAT,
    [Used Space(GB)] FLOAT,
    [Free Space(GB)] FLOAT,
    [Free Space %] DECIMAL(5,2)
);

INSERT INTO #DriveSpace
SELECT 
    @ComputerName AS ServerName,
    RTRIM(LTRIM(SUBSTRING(line,1,CHARINDEX('|',line) -1))) AS PhysicalName,
    ROUND(CAST(RTRIM(LTRIM(SUBSTRING(line,CHARINDEX('|',line)+1,(CHARINDEX('%',line) -1)-CHARINDEX('|',line)))) AS FLOAT)/1024,0) AS [Total Disk Capacity(GB)],
    (ROUND(CAST(RTRIM(LTRIM(SUBSTRING(line,CHARINDEX('|',line)+1,(CHARINDEX('%',line) -1)-CHARINDEX('|',line)))) AS FLOAT)/1024,0) -
     ROUND(CAST(RTRIM(LTRIM(SUBSTRING(line,CHARINDEX('%',line)+1,(CHARINDEX('*',line) -1)-CHARINDEX('%',line)))) AS FLOAT)/1024,0)) AS [Used Space(GB)],
    ROUND(CAST(RTRIM(LTRIM(SUBSTRING(line,CHARINDEX('%',line)+1,(CHARINDEX('*',line) -1)-CHARINDEX('%',line)))) AS FLOAT)/1024,0) AS [Free Space(GB)],
    ((ROUND(CAST(RTRIM(LTRIM(SUBSTRING(line,CHARINDEX('%',line)+1,(CHARINDEX('*',line) -1)-CHARINDEX('%',line)))) AS FLOAT)/1024,0)) /
     ROUND(CAST(RTRIM(LTRIM(SUBSTRING(line,CHARINDEX('|',line)+1,(CHARINDEX('%',line) -1)-CHARINDEX('|',line)))) AS FLOAT)/1024,0)) * 100 AS [Free Space %]
FROM #output
WHERE line LIKE '[A-Z][:]%'
ORDER BY PhysicalName;

-- Determine if any drive is in the red zone
DECLARE @IsUrgent BIT = 0;

IF EXISTS (
    SELECT 1
    FROM #DriveSpace
    WHERE
        ([Total Disk Capacity(GB)] > 1024  AND [Free Space %] <= 5) OR
        ([Total Disk Capacity(GB)] BETWEEN 500 AND 1024 AND [Free Space %] <= 10) OR
        ([Total Disk Capacity(GB)] < 500 AND [Free Space %] <= 10)
)
    SET @IsUrgent = 1;

-- Build HTML table rows correctly and format Free Space (GB) and Free Space % with same color logic
IF EXISTS (SELECT 1 FROM #DriveSpace)
BEGIN
    DECLARE @tableHTML NVARCHAR(MAX);
    DECLARE @subject NVARCHAR(300);
    DECLARE @rows NVARCHAR(MAX);

    SET @subject = CASE WHEN @IsUrgent = 1 
                        THEN 'URGENT: Drive Free Space Alert From ' + @ComputerName
                        ELSE 'Drive Free Space Report From ' + @ComputerName 
                   END;

    -- Build the rows explicitly to avoid misalignment
    SELECT @rows = (
        SELECT 
            '<tr>' +
                '<td style="border:2px solid #333;padding:6px;">' + ServerName + '</td>' +
                '<td style="border:2px solid #333;padding:6px;">' + [PhysicalName] + '</td>' +
                '<td style="border:2px solid #333;padding:6px;text-align:center;">' + CAST([Total Disk Capacity(GB)] AS VARCHAR(20)) + '</td>' +
                '<td style="border:2px solid #333;padding:6px;text-align:center;">' + CAST([Used Space(GB)] AS VARCHAR(20)) + '</td>' +
                '<td style="border:2px solid #333;padding:6px;text-align:center;">' +
                    CASE 
                        -- Free Space (GB) color same as percent logic
                        WHEN [Total Disk Capacity(GB)] > 1024 AND [Free Space %] <= 5 THEN 
                            '<span style="background-color:red;color:white;padding:2px 6px;border-radius:4px;display:inline-block;">' + CAST([Free Space(GB)] AS VARCHAR(20)) + '</span>'
                        WHEN [Total Disk Capacity(GB)] > 1024 AND [Free Space %] < 10 THEN 
                            '<span style="background-color:orange;color:black;padding:2px 6px;border-radius:4px;display:inline-block;">' + CAST([Free Space(GB)] AS VARCHAR(20)) + '</span>'
                        WHEN [Total Disk Capacity(GB)] BETWEEN 500 AND 1024 AND [Free Space %] <= 10 THEN 
                            '<span style="background-color:red;color:white;padding:2px 6px;border-radius:4px;display:inline-block;">' + CAST([Free Space(GB)] AS VARCHAR(20)) + '</span>'
                        WHEN [Total Disk Capacity(GB)] BETWEEN 500 AND 1024 AND [Free Space %] < 20 THEN 
                            '<span style="background-color:orange;color:black;padding:2px 6px;border-radius:4px;display:inline-block;">' + CAST([Free Space(GB)] AS VARCHAR(20)) + '</span>'
                        WHEN [Total Disk Capacity(GB)] < 500 AND [Free Space %] <= 10 THEN 
                            '<span style="background-color:red;color:white;padding:2px 6px;border-radius:4px;display:inline-block;">' + CAST([Free Space(GB)] AS VARCHAR(20)) + '</span>'
                        WHEN [Total Disk Capacity(GB)] < 500 AND [Free Space %] < 15 THEN 
                            '<span style="background-color:orange;color:black;padding:2px 6px;border-radius:4px;display:inline-block;">' + CAST([Free Space(GB)] AS VARCHAR(20)) + '</span>'
                        ELSE CAST([Free Space(GB)] AS VARCHAR(20))
                    END + '</td>' +

                '<td style="border:2px solid #333;padding:6px;text-align:center;">' +
                    CASE 
                        -- Free Space % formatted with similar color
                        WHEN [Total Disk Capacity(GB)] > 1024 AND [Free Space %] <= 5 THEN 
                            '<span style="background-color:red;color:white;padding:2px 6px;border-radius:4px;display:inline-block;">' + CAST([Free Space %] AS VARCHAR(6)) + '%</span>'
                        WHEN [Total Disk Capacity(GB)] > 1024 AND [Free Space %] < 10 THEN 
                            '<span style="background-color:orange;color:black;padding:2px 6px;border-radius:4px;display:inline-block;">' + CAST([Free Space %] AS VARCHAR(6)) + '%</span>'
                        WHEN [Total Disk Capacity(GB)] BETWEEN 500 AND 1024 AND [Free Space %] <= 10 THEN 
                            '<span style="background-color:red;color:white;padding:2px 6px;border-radius:4px;display:inline-block;">' + CAST([Free Space %] AS VARCHAR(6)) + '%</span>'
                        WHEN [Total Disk Capacity(GB)] BETWEEN 500 AND 1024 AND [Free Space %] < 20 THEN 
                            '<span style="background-color:orange;color:black;padding:2px 6px;border-radius:4px;display:inline-block;">' + CAST([Free Space %] AS VARCHAR(6)) + '%</span>'
                        WHEN [Total Disk Capacity(GB)] < 500 AND [Free Space %] <= 10 THEN 
                            '<span style="background-color:red;color:white;padding:2px 6px;border-radius:4px;display:inline-block;">' + CAST([Free Space %] AS VARCHAR(6)) + '%</span>'
                        WHEN [Total Disk Capacity(GB)] < 500 AND [Free Space %] < 15 THEN 
                            '<span style="background-color:orange;color:black;padding:2px 6px;border-radius:4px;display:inline-block;">' + CAST([Free Space %] AS VARCHAR(6)) + '%</span>'
                        ELSE CAST([Free Space %] AS VARCHAR(6)) + '%'
                    END + '</td>' +
            '</tr>'
        FROM #DriveSpace
        FOR XML PATH(''), TYPE
    ).value('.', 'NVARCHAR(MAX)');

    SET @tableHTML = N'
    <body style="font-family:Segoe UI, sans-serif;">
    <h3 style="color:#333;">Drive Free Space Status From - ' + @ComputerName + N'</h3>
    <table style="width:100%;border-collapse:collapse;border:2px solid #333;">
        <tr style="background-color:#404040;color:white;">
            <th style="border:2px solid #333;padding:6px;text-align:left;">ServerName</th>
            <th style="border:2px solid #333;padding:6px;text-align:left;">Drive</th>
            <th style="border:2px solid #333;padding:6px;text-align:center;">Capacity (GB)</th>
            <th style="border:2px solid #333;padding:6px;text-align:center;">Used Space (GB)</th>
            <th style="border:2px solid #333;padding:6px;text-align:center;">Free Space (GB)</th>
            <th style="border:2px solid #333;padding:6px;text-align:center;">Free Space %</th>
        </tr>' 
        + ISNULL(@rows, '') +
    N'</table></body>';

    -- Decode XML entities if any
    SET @tableHTML = REPLACE(REPLACE(@tableHTML, '&lt;', '<'), '&gt;', '>');
    select  top 1 @mailprofile = name from msdb.dbo.sysmail_profile
    EXEC msdb.dbo.sp_send_dbmail
        @profile_name = @mailprofile,
        @recipients = @Recipients,
        @subject = @subject,
        @body = @tableHTML,
        @body_format = 'HTML';
END
GO

