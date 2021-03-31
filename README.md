# stateful container backup of nexus iq with embedded db

- The startup.sh script was written to enable a consitent backup of nexus-iq running in a kubernetes environment. 
- The script first checks if it is in the backup window. 
- If backup window is true, then the backup steps will run before nexus-iq starts. 
- It uses restic to backup to cloud object storage. 
- It can run any other daily check such as storage usage. 
- Before posting a message in this example to MS Teams, but could be slack etc. 
- It then starts nexus-iq and sets up schedule to watch for the next backup window. 
- When it hits that windows it will terminate the nexus-iq process, upon which the kubernetes scheduler will see the process has exited and reschedule the pod, thus starting another backup and so the cycle repeats.


## manifest.yaml

- 
