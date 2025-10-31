-- Drop temp tables if they already exist
IF OBJECT_ID('tempdb..#Principals') IS NOT NULL DROP TABLE #Principals;
IF OBJECT_ID('tempdb..#RoleLinks') IS NOT NULL DROP TABLE #RoleLinks;
IF OBJECT_ID('tempdb..#Processing') IS NOT NULL DROP TABLE #Processing;
IF OBJECT_ID('tempdb..#RolePermissions') IS NOT NULL DROP TABLE #RolePermissions;
IF OBJECT_ID('tempdb..#DirectPermissions') IS NOT NULL DROP TABLE #DirectPermissions;
IF OBJECT_ID('tempdb..#ADMembers') IS NOT NULL DROP TABLE #ADMembers;
IF OBJECT_ID('tempdb..#FinalResult') IS NOT NULL DROP TABLE #FinalResult;
GO

CREATE TABLE #Principals
(
    PrincipalName SYSNAME,
    PrincipalType NCHAR(60)
);

CREATE TABLE #RoleLinks
(
    PrincipalName SYSNAME,
    DBRole SYSNAME
);

CREATE TABLE #Processing
(
    PrincipalName SYSNAME,
    DBRole SYSNAME
);

CREATE TABLE #RolePermissions
(
    DBRole SYSNAME,
    PermissionLevel NVARCHAR(50),
    PermissionType NVARCHAR(255),
    PermissionState NVARCHAR(60),
    ObjectName NVARCHAR(512),
    ObjectType NVARCHAR(60)
);

CREATE TABLE #DirectPermissions
(
    PrincipalName SYSNAME,
    PermissionLevel NVARCHAR(50),
    PermissionType NVARCHAR(255),
    PermissionState NVARCHAR(60),
    ObjectName NVARCHAR(512),
    ObjectType NVARCHAR(60)
);

CREATE TABLE #ADMembers
(
    ADGroup SYSNAME,
    ContainedADUser SYSNAME,
    ADType CHAR(8),
    ADPrivilege CHAR(9), -- (mapped login name)
    ADMLoginName SYSNAME,
    ADPermPath SYSNAME
);
GO
-- 1: Base principals (exclude DB Roles)
INSERT INTO #Principals
SELECT dp.name, dp.type_desc
FROM sys.database_principals dp
WHERE dp.sid IS NOT NULL
  AND dp.type <> 'R'
  AND dp.name NOT LIKE '##%';

-- 2: Role membership expansion (iterative)
INSERT INTO #Processing
SELECT member.name, role.name
FROM sys.database_role_members drm
JOIN sys.database_principals role ON role.principal_id = drm.role_principal_id
JOIN sys.database_principals member ON member.principal_id = drm.member_principal_id
WHERE member.type <> 'R';

WHILE @@ROWCOUNT > 0
BEGIN
    INSERT INTO #RoleLinks
    SELECT p.PrincipalName, p.DBRole
    FROM #Processing p
    LEFT JOIN #RoleLinks rl
      ON rl.PrincipalName = p.PrincipalName
     AND rl.DBRole = p.DBRole
    WHERE rl.PrincipalName IS NULL;

    DELETE FROM #Processing;

    INSERT INTO #Processing
    SELECT rl.PrincipalName, role2.name
    FROM #RoleLinks rl
    JOIN sys.database_principals role1
      ON role1.name = rl.DBRole and role1.type='R'
    JOIN sys.database_role_members drm2
      ON drm2.role_principal_id = role1.principal_id
    JOIN sys.database_principals role2
      ON role2.principal_id = drm2.member_principal_id
    LEFT JOIN #RoleLinks chk
      ON chk.PrincipalName = rl.PrincipalName
     AND chk.DBRole = role2.name
    WHERE chk.PrincipalName IS NULL
END;
-- 3: Explicit role permissions
INSERT INTO #RolePermissions
SELECT
    dp.name,
    CASE WHEN perm.class_desc='DATABASE' THEN 'DATABASE'
         WHEN perm.class_desc='SCHEMA' THEN 'SCHEMA'
         WHEN perm.class_desc IN ('OBJECT_OR_COLUMN', 'OBJECT') THEN 'OBJECT'
         ELSE perm.class_desc END,
    perm.permission_name,
    perm.state_desc,
    CASE WHEN perm.class_desc='DATABASE' THEN DB_NAME()
         WHEN perm.class_desc='SCHEMA' THEN s.name
         WHEN perm.class_desc IN ('OBJECT_OR_COLUMN', 'OBJECT') THEN OBJECT_SCHEMA_NAME(e.object_id) + '.' + e.name
         ELSE perm.class_desc END AS obj_name,
    COALESCE(e.type_desc, perm.class_desc) AS obj_type
FROM sys.database_permissions perm
JOIN sys.database_principals dp ON perm.grantee_principal_id = dp.principal_id
LEFT JOIN sys.objects e ON perm.class_desc IN ('OBJECT_OR_COLUMN', 'OBJECT') AND perm.major_id = e.object_id
LEFT JOIN sys.schemas s ON perm.class_desc='SCHEMA' AND perm.major_id = s.schema_id
WHERE dp.type = 'R'; -- Only roles

-- Add implied DB-level perms for system roles
INSERT INTO #RolePermissions
SELECT
    name AS DBRole,
    'DATABASE' AS PermissionLevel,
    'IMPLIED ACCESS' AS PermissionType,
    'GRANT' AS PermissionState,
    DB_NAME() AS ObjectName,
    'DATABASE' AS ObjectType
FROM sys.database_principals
WHERE type = 'R'
  AND name IN ('db_owner', 'db_datareader', 'db_datawriter', 'db_ddladmin', 'db_securityadmin');



INSERT INTO #DirectPermissions
SELECT
    dp.name,
    CASE WHEN perm.class_desc='DATABASE' THEN 'DATABASE'
         WHEN perm.class_desc='SCHEMA' THEN 'SCHEMA'
         WHEN perm.class_desc IN ('OBJECT_OR_COLUMN', 'OBJECT') THEN 'OBJECT'
         ELSE perm.class_desc END AS perm_level,
    perm.permission_name,
    perm.state_desc,
    CASE WHEN perm.class_desc='DATABASE' THEN DB_NAME()
         WHEN perm.class_desc='SCHEMA' THEN s.name
         WHEN perm.class_desc IN ('OBJECT_OR_COLUMN', 'OBJECT') THEN OBJECT_SCHEMA_NAME(e.object_id) + '.' + e.name
         ELSE perm.class_desc END AS obj_name,
    COALESCE(e.type_desc, perm.class_desc) AS obj_type
FROM sys.database_permissions perm
JOIN sys.database_principals dp ON perm.grantee_principal_id = dp.principal_id
LEFT JOIN sys.objects e ON perm.class_desc IN ('OBJECT_OR_COLUMN', 'OBJECT') AND perm.major_id = e.object_id
LEFT JOIN sys.schemas s ON perm.class_desc='SCHEMA' AND perm.major_id = s.schema_id
WHERE dp.type <> 'R'; -- Not roles

DECLARE @PrincipalName SYSNAME;
DECLARE ad_cur CURSOR LOCAL FAST_FORWARD FOR
SELECT PrincipalName FROM #Principals WHERE PrincipalType='WINDOWS_GROUP';

OPEN ad_cur;
FETCH NEXT FROM ad_cur INTO @PrincipalName;

WHILE @@FETCH_STATUS = 0
BEGIN
    BEGIN TRY
        IF OBJECT_ID('tempdb..#xp_results') IS NOT NULL DROP TABLE #xp_results;
        CREATE TABLE #xp_results ([account name] SYSNAME, [type] CHAR(8), [privilege] CHAR(9), [mapped login name] SYSNAME, [permission path] SYSNAME);

        INSERT INTO #xp_results
        EXEC xp_logininfo @PrincipalName, 'members';

        INSERT INTO #ADMembers
        SELECT @PrincipalName, [account name], [type], [privilege], [mapped login name], [permission path]
        FROM #xp_results;
      END TRY
        
        BEGIN CATCH
        END CATCH;
    FETCH NEXT FROM ad_cur INTO @PrincipalName;
END;

CLOSE ad_cur;
DEALLOCATE ad_cur;




CREATE TABLE #FinalResult
(
    PrincipalName SYSNAME,
    PrincipalType NCHAR(60),
    ADGroupOrLogin SYSNAME NULL,
    ContainedADUser SYSNAME NULL,
    DBRole SYSNAME NULL,
    PermissionLevel NVARCHAR(50),
    PermissionType NVARCHAR(255),
    PermissionState NVARCHAR(60),
    ObjectName NVARCHAR(512),
    ObjectType NVARCHAR(60)
);


INSERT INTO #FinalResult
SELECT
    p.PrincipalName,
    p.PrincipalType,
    p.PrincipalName,  
    NULL,             
    NULL,             
    dp.PermissionLevel,
    dp.PermissionType,
    dp.PermissionState,
    dp.ObjectName,
    dp.ObjectType
FROM #Principals p
JOIN #DirectPermissions dp ON dp.PrincipalName = p.PrincipalName;



INSERT INTO #FinalResult
SELECT
    p.PrincipalName,
    p.PrincipalType,
    p.PrincipalName,      
    adm.ContainedADUser,
    NULL,             
    dp.PermissionLevel,
    dp.PermissionType,
    dp.PermissionState,
    dp.ObjectName,
    dp.ObjectType
FROM #Principals p
JOIN #ADMembers adm ON p.PrincipalName = adm.ADGroup
JOIN #DirectPermissions dp ON dp.PrincipalName = adm.ADGroup
WHERE NOT (dp.PermissionLevel='DATABASE' AND dp.PermissionType='CONNECT'); 

INSERT INTO #FinalResult
SELECT
    p.PrincipalName,
    p.PrincipalType,
    p.PrincipalName,
    adm.ContainedADUser,
    rl.DBRole,
    rp.PermissionLevel,
    rp.PermissionType,
    rp.PermissionState,
    rp.ObjectName,
    rp.ObjectType
FROM #Principals p
LEFT JOIN #ADMembers adm ON p.PrincipalName = adm.ADGroup 
LEFT JOIN #RoleLinks rl ON rl.PrincipalName = p.PrincipalName 
JOIN #RolePermissions rp ON rl.DBRole = rp.DBRole
WHERE NOT (rp.PermissionLevel='DATABASE' AND rp.PermissionType='CONNECT'); 


SELECT
    PrincipalName,
    PrincipalType,
    ContainedADUser,
    DBRole,
    PermissionLevel,
    PermissionType,
    PermissionState,
    ObjectName,
    ObjectType
FROM #FinalResult
ORDER BY PrincipalName, ContainedADUser, DBRole, ObjectName;

