/*
Step 1: Create a new database TDE_Demo.
Step 2: Create a table and insert dummy data.
Step 3: Detach the database from SQL Server.
Step 4: Open the data file (.mdf) in a Hex Editor to view raw data.
*/
---------------------------------------------------------------------------
USE master
GO
CREATE DATABASE [TDE_Demo]
 CONTAINMENT = NONE
 ON  PRIMARY 
( NAME = N'TDE_Demo', FILENAME = N'E:\SQL\TDE_Demo.mdf' , SIZE = 8192KB , MAXSIZE = UNLIMITED, FILEGROWTH = 65536KB )
 LOG ON 
( NAME = N'TDE_Demo_log', FILENAME = N'E:\SQL\TDE_Demo_log.ldf' , SIZE = 8192KB , MAXSIZE = 2048GB , FILEGROWTH = 65536KB )
 WITH CATALOG_COLLATION = DATABASE_DEFAULT
GO
---------------------------------------------------------------------------
USE TDE_Demo;
GO
CREATE TABLE dbo.DummyData
(Id INT IDENTITY(1,1), DummyText VARCHAR(255));
GO
INSERT INTO dbo.DummyData (DummyText) VALUES('This is Dummy data');
GO
---------------------------------------------------------------------------
USE master;
GO
ALTER DATABASE [TDE_Demo] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
GO
EXEC master.dbo.sp_detach_db @dbname = N'TDE_Demo';
GO
---------------------------------------------------------------------------
/*Read the datafile using HEX Editor*/
---------------------------------------------------------------------------
