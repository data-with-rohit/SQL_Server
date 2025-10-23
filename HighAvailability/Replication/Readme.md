**Highly Available Transactional Replication in Always On Environment**

These scripts and notes document the process of setting up Transactional Replication in a SQL Server Always On Availability Group (AG) environment.

This configuration is specifically designed to provide a true Server/Database-level Disaster Recovery (DR) solution while utilizing a **shared distributor** for replication.

💡 **The Goal**

My client required a DR solution that paired highly customized transactional replication (with CDC) with a high-availability solution. 
The constraint was that a shared distributor (co-located on a replica) had to be used, rather than a separate distributor server.

🛠️ **Setup and Implementation**

The following steps outline the environment setup, replication configuration, and the challenges faced.

**1. Availability Group Setup**

I created a two-node AG setup:

    Primary Replica: AG1 (also acts as the shared Distributor).
    Secondary Replica: AG2.
    Listener: TestNew_AG_L.
    Publishing Database: AG2025_1.
          Link to the AG creation scripts: https://github.com/rohitagio/SQL_Server/tree/main/HighAvailability/Alwayson

**2. Replication Configuration**

The initial replication was configured using the GUI (scripts are attached to this repository for reference):

<img width="724" height="287" alt="image" src="https://github.com/user-attachments/assets/f12b7516-eae9-40f3-a8b2-10c282fd672d" />

**3. Initial Challenge: Snapshot Agent Failure**

**Issue: ** The Log Reader Agent failed because the Subscriber (SqlServer2025) did not have access to the initial Snapshot Folder.

**Resolution:**

    Shared the Snapshot Folder path on the network.
    Deleted the existing snapshot (if any).
    Edited the publication property to use the shared network path for the snapshot location.
    Restarted the Snapshot Agent.

**4. Redirecting the Publisher to the AG Listener**

To ensure replication continuity after a failover, the Publisher must be redirected to the AG Listener (TestNew_AG_L). 
This allows the distribution agents to connect to the active primary replica, regardless of which node it is running on.

Run this T-SQL script in SQLCMD mode on the Distributor (AG1):

      :CONNECT AG1
      
      use distribution
      go
      exec sp_redirect_publisher
          @original_publisher =  N'AG1'
          ,  @publisher_db =  N'AG2025_1'
          ,  @redirected_publisher =  N'TestNew_AG_L' 
      go

⚠️ ** Further Challenges i faced Post-Failover and Solutions i implemented**

After successfully failing over the AG from AG1 to AG2, the Log Reader Agent failed with the following series of errors, which required additional configuration on both replicas.

**Challenge 1:** Publisher Unknown at Distributor

    2025-10-23 04:32:30.703 Status: 0, code: 21891, text: 'The publisher 'AG2' with distributor 'AG1' is not known as a publisher at distributor 'AG1'. Run sp_adddistpublisher at distributor 'AG1' to enable the remote server to host the publishing database 'AG2025_1'.'.
    2025-10-23 04:32:30.703 Status: 0, code: 22037, text: 'Errors were logged when validating the redirected publisher.'.

**Solution:** The secondary replica (AG2) needed to be explicitly registered as a potential Publisher on the Distributor (AG1).
Run this T-SQL script on the Distributor (AG1) under **distribution** database:
      
      EXEC sys.sp_adddistpublisher 
        @publisher = N'AG2', 
        @distribution_db = N'distribution', 
        @security_mode = 1;

**Challenge 2:** Publisher Not Enabled as Distributor
After solving the first error and restarting the Log Reader Agent, it failed again with: 
      
      2025-10-23 04:34:13.716 Status: 0, code: 21889, text: 'The SQL Server instance 'AG2' is not a replication publisher. Run sp_adddistributor on SQL Server instance 'AG2' with distributor 'AG1' in order to enable the instance to host the publishing database 'AG2025_1'. Make certain to specify the same login and password as that used for the original publisher.'.
      2025-10-23 04:34:13.716 Status: 0, code: 22037, text: 'Errors were logged when validating the redirected publisher.'.

**Solution: **The secondary replica (AG2) needed to be configured to recognize and use the shared Distributor (AG1).
Run this T-SQL script on the Publisher (AG2):

    USE [master]
    GO
    
    EXEC sys.sp_adddistributor 
        @distributor = N'AG1', 
        @password = N'CrapPWD@231177'; 
    GO

**Note on @password: **The @password used here must match the password for the hidden distributor_admin SQL login created on the Distributor (AG1). 
Since the initial distribution setup was done via the GUI without explicitly setting this password, I had to:

    Change the password for the distributor_admin login on AG1.
    Use that same password in the sp_adddistributor command on AG2.


✅ Conclusion

Once all steps were complete and the Log Reader Agent was restarted, the replication resumed successfully from the new primary (AG2). 
This validates a fully functional, highly available transactional replication environment using a shared distributor within a SQL Server Always On Availability Group.








