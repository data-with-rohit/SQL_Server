Always On Availability Group Setup Script

This T-SQL script, designed to be run in SQLCMD mode, automates the critical prerequisites and final creation steps for a two-replica Always On Availability Group named [TestNew_AG] spanning two SQL Server instances, AG1 and AG2.

Prerequisites

    The SQL Server instances must be part of a Windows Server Failover Cluster (WSFC).
    The script must be executed in SQLCMD mode (usually by enabling it in SSMS or running via the sqlcmd utility).
    The login running the script must have SA or high-level permissions on both AG1 and AG2.
    The Kerberos configuration (SPNs) must be correct to avoid SSPI errors during the :Connect steps.

<img width="1244" height="342" alt="image" src="https://github.com/user-attachments/assets/b11e4341-45fb-4246-86a7-ae2a73ac5e12" />
