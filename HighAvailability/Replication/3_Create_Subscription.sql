-----------------BEGIN: Script to be run at Publisher 'AG1'-----------------
use [AG2025_1]
exec sp_addsubscription @publication = N'Category', @subscriber = N'SQLSERVER2025', @destination_db = N'AG2025_1', @sync_type = N'Automatic', @subscription_type = N'pull', @update_mode = N'read only'
GO
-----------------END: Script to be run at Publisher 'AG1'-----------------

-----------------BEGIN: Script to be run at Subscriber 'SQLSERVER2025'-----------------
use [AG2025_1]
exec sp_addpullsubscription @publisher = N'AG1', @publication = N'Category', @publisher_db = N'AG2025_1', @independent_agent = N'True', @subscription_type = N'pull', @description = N'', @update_mode = N'read only', @immediate_sync = 1

exec sp_addpullsubscription_agent @publisher = N'AG1', @publisher_db = N'AG2025_1', @publication = N'Category', @distributor = N'AG1', @distributor_security_mode = 1, @distributor_login = N'', @distributor_password = null, @enabled_for_syncmgr = N'False', @frequency_type = 64, @frequency_interval = 0, @frequency_relative_interval = 0, @frequency_recurrence_factor = 0, @frequency_subday = 0, @frequency_subday_interval = 0, @active_start_time_of_day = 0, @active_end_time_of_day = 235959, @active_start_date = 20251022, @active_end_date = 99991231, @alt_snapshot_folder = N'', @working_directory = N'', @use_ftp = N'False', @job_login = null, @job_password = null, @publication_type = 0
GO
-----------------END: Script to be run at Subscriber 'SQLSERVER2025'-----------------

