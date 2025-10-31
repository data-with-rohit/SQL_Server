

-- Drop old temp tables
IF OBJECT_ID('tempdb..#Principals') IS NOT NULL DROP TABLE #Principals;
IF OBJECT_ID('tempdb..#RoleLinks') IS NOT NULL DROP TABLE #RoleLinks;
IF OBJECT_ID('tempdb..#Processing') IS NOT NULL DROP TABLE #Processing;
IF OBJECT_ID('tempdb..#RolePermissions') IS NOT NULL DROP TABLE #RolePermissions;
IF OBJECT_ID('tempdb..#DirectPermissions') IS NOT NULL DROP TABLE #DirectPermissions;
IF OBJECT_ID('tempdb..#ADMembers') IS NOT NULL DROP TABLE #ADMembers;
IF OBJECT_ID('tempdb..#FinalResult') IS NOT NULL DROP TABLE #FinalResult;

-- Base principals
CREATE TABLE #Principals (PrincipalName SYSNAME, PrincipalType NVARCHAR(60));

-- Role mapping
CREATE TABLE #RoleLinks (PrincipalName SYSNAME, DBRole SYSNAME);
CREATE TABLE #Processing (PrincipalName SYSNAME, DBRole SYSNAME);

-- Permissions
CREATE TABLE #RolePermissions (
    DBRole SYSNAME,
    PermissionLevel NVARCHAR(50),
    PermissionType NVARCHAR(255),
    PermissionState NVARCHAR(60),
    ObjectName NVARCHAR(512),
    ObjectType NVARCHAR(60)
);
CREATE TABLE #DirectPermissions (
    PrincipalName SYSNAME,
    PermissionLevel NVARCHAR(50),
    PermissionType NVARCHAR(255),
    PermissionState NVARCHAR(60),
    ObjectName NVARCHAR(512),
    ObjectType NVARCHAR(60)
);

-- AD group expansion
CREATE TABLE #ADMembers (
    ADGroup SYSNAME,
    ContainedADUser SYSNAME,
    ADType CHAR(8),
    ADPrivilege CHAR(9),
    ADMLoginName SYSNAME,
    ADPermPath SYSNAME
);

-- Final result
CREATE TABLE #FinalResult (
    PrincipalName SYSNAME,
    PrincipalType NVARCHAR(60),
    ADGroupOrLogin SYSNAME,
    ContainedADUser SYSNAME NULL,
    DBRole SYSNAME NULL,
    PermissionLevel NVARCHAR(50),
    PermissionType NVARCHAR(255),
    PermissionState NVARCHAR(60),
    ObjectName NVARCHAR(512),
    ObjectType NVARCHAR(60)
);

------------------------------------------------------------
-- 1: Base principals (no DB roles/system noise)
------------------------------------------------------------
INSERT INTO #Principals
SELECT dp.name, dp.type_desc
FROM sys.database_principals dp
WHERE dp.sid IS NOT NULL
  AND dp.type <> 'R'
  AND dp.name NOT LIKE '##%';

------------------------------------------------------------
-- 2: Build role membership iteratively
------------------------------------------------------------
INSERT INTO #Processing
SELECT member.name, role.name
FROM sys.database_role_members drm
JOIN sys.database_principals role 
    ON role.principal_id = drm.role_principal_id
JOIN sys.database_principals member 
    ON member.principal_id = drm.member_principal_id
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
        ON rl.DBRole = role1.name AND role1.type = 'R'
    JOIN sys.database_role_members drm2
        ON role1.principal_id = drm2.member_principal_id
    JOIN sys.database_principals role2
        ON drm2.role_principal_id = role2.principal_id
    LEFT JOIN #RoleLinks chk
        ON chk.PrincipalName = rl.PrincipalName AND chk.DBRole = role2.name
    WHERE chk.PrincipalName IS NULL;
END

------------------------------------------------------------
-- 3: Explicit role perms
------------------------------------------------------------
INSERT INTO #RolePermissions
SELECT dp.name,
       CASE 
         WHEN perm.class_desc='DATABASE' THEN 'DATABASE'
         WHEN perm.class_desc='SCHEMA' THEN 'SCHEMA'
         WHEN perm.class_desc IN ('OBJECT_OR_COLUMN','OBJECT') THEN 'OBJECT'
         ELSE perm.class_desc END,
       perm.permission_name,
       perm.state_desc,
       CASE 
         WHEN perm.class_desc='DATABASE' THEN DB_NAME()
         WHEN perm.class_desc='SCHEMA' THEN s.name
         WHEN perm.class_desc IN ('OBJECT_OR_COLUMN','OBJECT') THEN OBJECT_SCHEMA_NAME(o.object_id) + '.' + o.name
         ELSE perm.class_desc END,
       COALESCE(o.type_desc, perm.class_desc)
FROM sys.database_permissions perm
JOIN sys.database_principals dp 
    ON perm.grantee_principal_id = dp.principal_id
LEFT JOIN sys.objects o 
    ON perm.class_desc IN ('OBJECT_OR_COLUMN','OBJECT') AND perm.major_id = o.object_id
LEFT JOIN sys.schemas s 
    ON perm.class_desc='SCHEMA' AND perm.major_id = s.schema_id
WHERE dp.type = 'R';

-- Also add implied DB-level perms for built-ins
INSERT INTO #RolePermissions
SELECT name AS DBRole,
       'DATABASE', 'IMPLIED ACCESS', 'GRANT', DB_NAME(), 'DATABASE'
FROM sys.database_principals
WHERE type='R'
  AND name IN ('db_owner','db_datareader','db_datawriter','db_ddladmin','db_securityadmin');

------------------------------------------------------------
-- 4: Direct perms to principals
------------------------------------------------------------
INSERT INTO #DirectPermissions
SELECT dp.name,
       CASE 
         WHEN perm.class_desc='DATABASE' THEN 'DATABASE'
         WHEN perm.class_desc='SCHEMA' THEN 'SCHEMA'
         WHEN perm.class_desc IN ('OBJECT_OR_COLUMN','OBJECT') THEN 'OBJECT'
         ELSE perm.class_desc END,
       perm.permission_name,
       perm.state_desc,
       CASE 
         WHEN perm.class_desc='DATABASE' THEN DB_NAME()
         WHEN perm.class_desc='SCHEMA' THEN s.name
         WHEN perm.class_desc IN ('OBJECT_OR_COLUMN','OBJECT') THEN OBJECT_SCHEMA_NAME(o.object_id) + '.' + o.name
         ELSE perm.class_desc END,
       COALESCE(o.type_desc, perm.class_desc)
FROM sys.database_permissions perm
JOIN sys.database_principals dp 
    ON perm.grantee_principal_id = dp.principal_id
LEFT JOIN sys.objects o 
    ON perm.class_desc IN ('OBJECT_OR_COLUMN','OBJECT') AND perm.major_id = o.object_id
LEFT JOIN sys.schemas s 
    ON perm.class_desc='SCHEMA' AND perm.major_id = s.schema_id
WHERE dp.type <> 'R';

------------------------------------------------------------
-- 5: Expand AD group members
------------------------------------------------------------
DECLARE @PrincipalName SYSNAME;
DECLARE ad_cur CURSOR LOCAL FAST_FORWARD FOR
SELECT PrincipalName FROM #Principals WHERE PrincipalType='WINDOWS_GROUP';

OPEN ad_cur;
FETCH NEXT FROM ad_cur INTO @PrincipalName;
WHILE @@FETCH_STATUS=0
BEGIN
    BEGIN TRY
        IF OBJECT_ID('tempdb..#xp_results') IS NOT NULL DROP TABLE #xp_results;
        CREATE TABLE #xp_results(
            [account name] SYSNAME,[type] CHAR(8),
            [privilege] CHAR(9),[mapped login name] SYSNAME,[permission path] SYSNAME
        );
        INSERT INTO #xp_results EXEC xp_logininfo @PrincipalName, 'members';

        INSERT INTO #ADMembers
        SELECT @PrincipalName,[account name],[type],[privilege],[mapped login name],[permission path]
        FROM #xp_results;
    END TRY
    BEGIN CATCH
    END CATCH;
    FETCH NEXT FROM ad_cur INTO @PrincipalName;
END
CLOSE ad_cur;
DEALLOCATE ad_cur;

------------------------------------------------------------
-- 6: Final result build - FIXED to avoid NULL ContainedADUser for AD groups with members
------------------------------------------------------------

-- Direct perms for principal itself:
-- Skip for AD groups *that have members* in #ADMembers
INSERT INTO #FinalResult
SELECT p.PrincipalName,p.PrincipalType,p.PrincipalName,NULL,NULL,
       dp.PermissionLevel,dp.PermissionType,dp.PermissionState,dp.ObjectName,dp.ObjectType
FROM #Principals p
JOIN #DirectPermissions dp ON dp.PrincipalName = p.PrincipalName
WHERE NOT (
    p.PrincipalType = 'WINDOWS_GROUP'
    AND EXISTS (SELECT 1 FROM #ADMembers am WHERE am.ADGroup = p.PrincipalName)
);

-- Group’s direct perms applied to members
INSERT INTO #FinalResult
SELECT p.PrincipalName,p.PrincipalType,p.PrincipalName,adm.ContainedADUser,NULL,
       dp.PermissionLevel,dp.PermissionType,dp.PermissionState,dp.ObjectName,dp.ObjectType
FROM #Principals p
JOIN #ADMembers adm ON p.PrincipalName = adm.ADGroup
JOIN #DirectPermissions dp ON dp.PrincipalName = p.PrincipalName;

-- AD member’s own direct perms
INSERT INTO #FinalResult
SELECT p.PrincipalName,p.PrincipalType,p.PrincipalName,adm.ContainedADUser,NULL,
       dp.PermissionLevel,dp.PermissionType,dp.PermissionState,dp.ObjectName,dp.ObjectType
FROM #Principals p
JOIN #ADMembers adm ON p.PrincipalName = adm.ADGroup
JOIN #DirectPermissions dp ON dp.PrincipalName = adm.ContainedADUser
WHERE NOT (dp.PermissionLevel='DATABASE' AND dp.PermissionType='CONNECT');

-- Role-based perms
INSERT INTO #FinalResult
SELECT p.PrincipalName,p.PrincipalType,p.PrincipalName,adm.ContainedADUser,rl.DBRole,
       rp.PermissionLevel,rp.PermissionType,rp.PermissionState,rp.ObjectName,rp.ObjectType
FROM #Principals p
LEFT JOIN #ADMembers adm ON p.PrincipalName = adm.ADGroup
JOIN #RoleLinks rl ON p.PrincipalName = rl.PrincipalName
JOIN #RolePermissions rp ON rl.DBRole = rp.DBRole
WHERE NOT (rp.PermissionLevel='DATABASE' AND rp.PermissionType='CONNECT');

------------------------------------------------------------
-- Query final results once
------------------------------------------------------------
SELECT 
PrincipalName ,
    PrincipalType ,
    ContainedADUser ,
    DBRole ,
    PermissionLevel ,
    PermissionType ,
    PermissionState ,
    ObjectName ,
    ObjectType 
FROM #FinalResult

ORDER BY PrincipalName,ContainedADUser,DBRole,ObjectName;
