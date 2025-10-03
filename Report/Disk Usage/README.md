This script helps in automating proactive disk space monitoring. 

What sets this script apart?
> Granular Filtering: Includes options to filter by disk capacity, remaining free space (GB), and free space percentage.
> 
> Conditional Formatting: The HTML report uses intuitive color-coding to highlight drive status, including an "Urgent" flag for critical thresholds.
> 
> Focus on Action: Designed to let DBAs instantly see where intervention is required.

I'm sharing this version—created today in my local lab—to help others automate this essential task. Let me know what features you'd add!

You can execute it by running: EXEC DBNAME.[dbo].[sp_monitor_disk_free_space] @Recipients = 'Email Goes here'
