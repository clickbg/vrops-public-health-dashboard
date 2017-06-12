# VMware vRealize Operations Manager Public Health Dashboard
**Name:** vROPSPHD  
**Description:**  
Integrate VMware vRealize Operations Manager (vROPS) with Cachet to create public health dashboard for your users.  
This script creates/deletes/updates Cachet components, incidents and health status based on active vROPs incidents and objects in vROPs custom group  
**Supported versions**: vROps 6.3 or newer, Cachet 2.3.x
**Author:** Daniel Zhelev  

## Prerequisites:
Installed and configured vROps  
Installed and configured Cachet - [How to install and configure Cachet](https://docs.cachethq.io/v1.0/docs/installing-cachet)  
JQ version 1.5 or newer - [About JQ](https://stedolan.github.io/jq/)  
vROPs custom group containing all the objects that you want to see in Cachet - [How to create vROPs custom groups](https://blogs.vmware.com/management/2016/07/organizing-your-vmware-vrealize-operations-environment-with-custom-groups.html)  

## Installation
1. Create vROPs custom group and put the desired objects in it.  
The script will create them in Cachet.

2. Get the vROPs custom group resource id.  
Open the custom group in vROPs from Environment > Custom Groups > [Your group name] and copy the group id from the url.  
Example: https://vrops.test.local/ui/index.action#/object/f848a8d3-4516-461f-bacb-2d9b867a4227/summary  
Id: f848a8d3-4516-461f-bacb-2d9b867a4227  

3. Decide where you will run the script  
You can run it directly on the Cachet VM or in a seperate VM  
Do not run it in the vROPs VA!  

4. Install JQ on the VM where you intend to run the script

5. Create user which will run the script  
You can run it as root, it’s not recommended  
Example: useradd -d /usr/local/sbin/vropsphd vropsphd  

6. If you have skipped 5. then create home directory  
The script will create sub-directories and generate JSON files so we need to have a home for it  
Example: mkdir /usr/local/sbin/vropsphd && chmod 700 /usr/local/sbin/vropsphd  

7. Download the vROPSPHD script  
Example:  
git clone https://github.com/clickbg/vrops-public-health-dashboard.git  
mv ./vrops-public-health-dashboard/vropsphd.sh /usr/local/sbin/vropsphd/vropsphd.sh  

8. Set owner and permissions  
Example:  
chown vropsphd:vropsphd /usr/local/sbin/vropsphd/vropsphd.sh  
chmod 700 /usr/local/sbin/vropsphd/vropsphd.sh  

9. Configure the script  
Example: vi /usr/local/sbin/vropsphd/vropsphd.sh  

10. First time run  
On first run the script will create directory structure and config files  
Its advisable not to delete anything outside of /usr/local/sbin/vropsphd/vropsphd.sh/tmp/  
Example: su vropsphd -c /usr/local/sbin/vropsphd/vropsphd.sh  

11. Schedule cron job  
Usually you will want the script to keep Cachet updated so its good idea to schedule a cron job  
Recommended is to run the job every two vROPs cycles - 10 minutes, but you can choose other interval.  
Since vROPs refreshes the data every 5 minutes running the script in lower interval than that would not make sense.  
Example: crontab -u vropsphd -e  
*/10 * * * * /usr/local/sbin/vropsphd/vropsphd.sh >> /var/log/vropsphd.log 2>&1  

12. Rename and group your objects in Cachet  
You are free to group and rename the Cachet components, it won't affect the script as we are using ids.  

## FAQ
Q: Will the script touch anything in vROPs?  
A: No, the script only collects from vROPs it doesn’t make any modifications.

Q: Will the script touch anything in Cachet?
A: Yes, the script creates, modifies, deletes Cachet components and alerts based on the objects in your vROPs custom group.  
It won't however delete anything that wasn't created by it in the first place.  
So if you have other Cachet components or alerts then they are safe.  
Every created component or alert is stored in $RUN_DIR/open_incidents.json and $RUN_DIR/cachet_components.json  

Q: Can I rename, group or re-arrange Cachet objects created by the script?  
A: Yes, the script uses Cachet ids to identify the objects managed by it.  

Q: Can I have other things integrated with Cachet - other components or incidents?
A: Yes, the script only deletes, updates objects which were created by it.
Everything else is safe.

Q: Is it safe to delete files in $RUN_DIR?  
A: No, you can delete anything in $RUN_DIR/tmp but if you delete cachet_components.json or open_incidents.json you will end up with duplicate Cachet components and alerts.  

Q: Can I delete components or open alerts which were created by the script from Cachet?
A: No, the script will re-create them.  
You need to remove an object from the vROPs custom group and the script will delete it from Cachet automatically.
It is safe to remove closed alerts as are we are not tracking those.

Q: Can I manually mark open Cachet alert created by the script as closed?
A: Yes, but it is better to wait for the script to it. Otherwise it might create a duplicate alert if there is vROPs alert still open.
