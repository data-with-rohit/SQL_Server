--Note: I have only tested this with windows users. This may not work with SQL Logins/users
USE master;


GO
DECLARE @LoginList AS NVARCHAR (MAX) = 'YourDomain\User_Name1,YourDomain\User_Name2';

IF OBJECT_ID('tempdb..#LoginNames') IS NOT NULL
    DROP TABLE #LoginNames;

CREATE TABLE #LoginNames (
    LoginName SYSNAME
);

IF OBJECT_ID('tempdb..#total_permissions') IS NOT NULL
    DROP TABLE #total_permissions;

INSERT INTO #LoginNames (LoginName)
SELECT LTRIM(RTRIM(value))
FROM   STRING_SPLIT (@LoginList, ',')
WHERE  LTRIM(RTRIM(value)) <> '';

IF OBJECT_ID('tempdb..#tmpResultsMaster') IS NOT NULL
    DROP TABLE #tmpResultsMaster;

CREATE TABLE #tmpResultsMaster (
    [account name]      SYSNAME ,
    [type]              CHAR (8),
    privilege           CHAR (9),
    [mapped login name] SYSNAME ,
    [permission path]   SYSNAME  NULL
);

DECLARE @LoginName AS SYSNAME;

DECLARE cur CURSOR LOCAL FAST_FORWARD
    FOR SELECT LoginName
        FROM   #LoginNames;

OPEN cur;

FETCH NEXT FROM cur INTO @LoginName;

WHILE @@FETCH_STATUS = 0
    BEGIN
        BEGIN TRY
            INSERT INTO #tmpResultsMaster
            EXECUTE xp_logininfo @LoginName, 'all';
        END TRY
        BEGIN CATCH
            PRINT 'xp_logininfo failed for: ' + @LoginName + ' - Error: ' + ERROR_MESSAGE();
        END CATCH
        FETCH NEXT FROM cur INTO @LoginName;
    END

CLOSE cur;

DEALLOCATE cur;

DECLARE @DB_Users TABLE (
    DBName         SYSNAME      ,
    UserName       SYSNAME       COLLATE DATABASE_DEFAULT NULL,
    LoginType      SYSNAME      ,
    AssociatedRole VARCHAR (MAX),
    create_date    DATETIME     ,
    modify_date    DATETIME     );

DECLARE @sql AS NVARCHAR (MAX);

DECLARE @QuotedDBName AS SYSNAME;

DECLARE db_cursor CURSOR LOCAL FAST_FORWARD
    FOR SELECT name
        FROM   sys.databases
        WHERE  state_desc = 'ONLINE';

OPEN db_cursor;

FETCH NEXT FROM db_cursor INTO @QuotedDBName;

WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @sql = N'

    USE ' + QUOTENAME(@QuotedDBName) + N';

    SELECT

        ''' + @QuotedDBName + N''' AS DB_Name,

        CASE prin.name

            WHEN ''dbo'' THEN prin.name + '' ('' + SUSER_SNAME(owning_principal_id) + '')''

            ELSE prin.name

        END AS UserName,

        prin.type_desc AS LoginType,

        ISNULL(USER_NAME(mem.role_principal_id),'''') AS AssociatedRole,

        create_date,

        modify_date

    FROM sys.database_principals prin

    LEFT JOIN sys.database_role_members mem

        ON prin.principal_id = mem.member_principal_id

    WHERE prin.sid IS NOT NULL

      AND prin.sid NOT IN (0x00)

      AND prin.is_fixed_role <> 1

      AND prin.name NOT LIKE ''##%'';';
        INSERT INTO @DB_Users
        EXECUTE sys.sp_executesql @sql;
        FETCH NEXT FROM db_cursor INTO @QuotedDBName;
    END

CLOSE db_cursor;

DEALLOCATE db_cursor;

SELECT   user1.DBName,
         user1.UserName AS MappedADGroup,
         tr.[mapped login name] AS LoginName,
         user1.LoginType,
         STUFF((SELECT ',  (=) ' + CONVERT (VARCHAR (500), user2.AssociatedRole)
                FROM   @DB_Users AS user2
                WHERE  user1.DBName = user2.DBName
                       AND user1.UserName COLLATE DATABASE_DEFAULT = user2.UserName COLLATE DATABASE_DEFAULT
                       AND ISNULL(user2.AssociatedRole, '') <> ''
                FOR    XML PATH ('')), 1, 1, '') AS UserGetting_Access_Via_BelowDBRoles
INTO     #total_permissions
FROM     @DB_Users AS user1
         INNER JOIN
         #tmpResultsMaster AS tr
         ON user1.UserName COLLATE DATABASE_DEFAULT = tr.[permission path] COLLATE DATABASE_DEFAULT
GROUP BY tr.[mapped login name], user1.DBName, user1.UserName, user1.LoginType, user1.create_date, user1.modify_date
HAVING   COUNT(CASE WHEN ISNULL(user1.AssociatedRole, '') <> '' THEN 1 END) > 0
ORDER BY user1.DBName, user1.UserName;

SELECT *
FROM   #total_permissions;

IF OBJECT_ID('tempdb..#RolePermissions') IS NOT NULL
    DROP TABLE #RolePermissions;

CREATE TABLE #RolePermissions (
    DBName          SYSNAME        COLLATE DATABASE_DEFAULT,
    RoleName        SYSNAME        COLLATE DATABASE_DEFAULT,
    PermissionName  NVARCHAR (255) COLLATE DATABASE_DEFAULT,
    PermissionState NVARCHAR (60)  COLLATE DATABASE_DEFAULT,
    SecuredEntity   NVARCHAR (512) COLLATE DATABASE_DEFAULT,
    EntityType      NVARCHAR (60)  COLLATE DATABASE_DEFAULT
);

DECLARE @DBName AS SYSNAME, @RoleList AS NVARCHAR (MAX), @RoleName AS SYSNAME, @sql1 AS NVARCHAR (MAX);

DECLARE dbrole_cur CURSOR LOCAL FAST_FORWARD
    FOR SELECT DBName,
               UserGetting_Access_Via_BelowDBRoles
        FROM   #total_permissions;

OPEN dbrole_cur;

FETCH NEXT FROM dbrole_cur INTO @DBName, @RoleList;

WHILE @@FETCH_STATUS = 0
    BEGIN
        DECLARE role_split_cur CURSOR LOCAL FAST_FORWARD
            FOR SELECT LTRIM(RTRIM(REPLACE(REPLACE(value, '(=)', ''), ',', '')))
                FROM   STRING_SPLIT (@RoleList, ',')
                WHERE  LTRIM(RTRIM(REPLACE(REPLACE(value, '(=)', ''), ',', ''))) <> '';
        OPEN role_split_cur;
        FETCH NEXT FROM role_split_cur INTO @RoleName;
        WHILE @@FETCH_STATUS = 0
            BEGIN
                IF @RoleName COLLATE DATABASE_DEFAULT NOT IN ('db_owner', 'db_accesadmin', 'db_securityadmin', 'db_ddladmin', 'db_backupoperator', 'db_datareader', 'db_datawriter', 'db_denydatareader', 'db_denydatawriter')
                    BEGIN
                        SET @sql1 = N'

            USE ' + QUOTENAME(@DBName) + ';

            INSERT INTO #RolePermissions (DBName, RoleName, PermissionName, PermissionState, SecuredEntity, EntityType)

            SELECT

                ' + QUOTENAME(@DBName, '''') + ',

                ' + QUOTENAME(@RoleName, '''') + ',

                pr.permission_name COLLATE DATABASE_DEFAULT,

                pr.state_desc COLLATE DATABASE_DEFAULT,

                ISNULL(

                    CASE

                        WHEN pr.class_desc = ''DATABASE''

                            THEN ''Database''

                        WHEN pr.class_desc = ''SCHEMA''  

                            THEN QUOTENAME(s.name)

                        WHEN pr.class_desc = ''OBJECT_OR_COLUMN''

                            THEN QUOTENAME(s2.name) + ''.'' + QUOTENAME(o.name)

                        ELSE pr.class_desc

                    END, ''Unknown Entity''

                ) COLLATE DATABASE_DEFAULT AS SecuredEntity,

                ISNULL(o.type_desc, pr.class_desc) AS EntityType

            FROM sys.database_principals dp

            INNER JOIN sys.database_permissions pr

                ON dp.principal_id = pr.grantee_principal_id

            LEFT JOIN sys.objects o

                ON pr.major_id = o.object_id

            LEFT JOIN sys.schemas s

                ON pr.major_id = s.schema_id

            LEFT JOIN sys.schemas s2

                ON o.schema_id = s2.schema_id

            WHERE dp.name = ' + QUOTENAME(@RoleName, '''') + ';

            ';
                        EXECUTE sys.sp_executesql @sql1;
                    END
                FETCH NEXT FROM role_split_cur INTO @RoleName;
            END
        CLOSE role_split_cur;
        DEALLOCATE role_split_cur;
        FETCH NEXT FROM dbrole_cur INTO @DBName, @RoleList;
    END

CLOSE dbrole_cur;

DEALLOCATE dbrole_cur;

SELECT   *
FROM     #RolePermissions
ORDER BY DBName, RoleName, SecuredEntity;

IF OBJECT_ID('tempdb..#ADGroupMembers') IS NOT NULL
    DROP TABLE #ADGroupMembers;

CREATE TABLE #ADGroupMembers (
    DBName              SYSNAME  COLLATE DATABASE_DEFAULT,
    [account name]      SYSNAME  COLLATE DATABASE_DEFAULT,
    [type]              CHAR (8) COLLATE DATABASE_DEFAULT,
    [privilege]         CHAR (9) COLLATE DATABASE_DEFAULT,
    [mapped login name] SYSNAME  COLLATE DATABASE_DEFAULT,
    [permission path]   SYSNAME  COLLATE DATABASE_DEFAULT
);

DECLARE @ADGroup AS SYSNAME;

DECLARE adgroup_cur CURSOR LOCAL FAST_FORWARD
    FOR SELECT DISTINCT DBName,
                        MappedADGroup
        FROM   #total_permissions
        WHERE  ISNULL(MappedADGroup, '') <> '';

OPEN adgroup_cur;

FETCH NEXT FROM adgroup_cur INTO @DBName, @ADGroup;

WHILE @@FETCH_STATUS = 0
    BEGIN
        BEGIN TRY
            IF OBJECT_ID('tempdb..#xp_results') IS NOT NULL
                DROP TABLE #xp_results;
            CREATE TABLE #xp_results (
                [account name]      SYSNAME  COLLATE DATABASE_DEFAULT,
                [type]              CHAR (8) COLLATE DATABASE_DEFAULT,
                [privilege]         CHAR (9) COLLATE DATABASE_DEFAULT,
                [mapped login name] SYSNAME  COLLATE DATABASE_DEFAULT,
                [permission path]   SYSNAME  COLLATE DATABASE_DEFAULT
            );
            SET @sql = '

        USE ' + QUOTENAME(@DBName) + ';

        INSERT INTO #xp_results

        EXEC xp_logininfo ' + QUOTENAME(@ADGroup, '''') + ', ''members'';';
            EXECUTE sys.sp_executesql @sql;
            INSERT INTO #ADGroupMembers (DBName, [account name], [type], [privilege], [mapped login name], [permission path])
            SELECT @DBName,
                   [account name],
                   [type],
                   [privilege],
                   [mapped login name],
                   [permission path]
            FROM   #xp_results;
        END TRY
        BEGIN CATCH
            PRINT 'xp_logininfo members failed for: ' + @DBName + '\' + @ADGroup + ' - Error: ' + ERROR_MESSAGE();
        END CATCH
        FETCH NEXT FROM adgroup_cur INTO @DBName, @ADGroup;
    END

CLOSE adgroup_cur;

DEALLOCATE adgroup_cur;

SELECT   *
FROM     #ADGroupMembers
ORDER BY DBName;
