# VMware vRealize Operations Manager Public Health Dashboard
Name: vROPSPHD
Description: Integrate VMware vRealize Operations Manager (vROPS) with Cachet and create public health dashboard for your users
Author: Daniel Zhelev

## Prerequisites:
Installed and configured vROPs
Installed and configured Cachet - [How to install and configure Cachet](https://docs.cachethq.io/v1.0/docs/installing-cachet)
JQ version 1.5 or newer - [About JQ](https://stedolan.github.io/jq/)
vROPs custom group containing all objects that you want to see in Cachet - [How to create vROPs custom groups](https://blogs.vmware.com/management/2016/07/organizing-your-vmware-vrealize-operations-environment-with-custom-groups.html)

## Installation
1. Create vROPs custom group and put the desired objects in it.  
The script will create them in Cachet.

2. Get the vROPs custom group resource id.  
Open the custom group in vROPs from Environment > Custom Groups > [Your group name] and copy the group id from its url.  
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
Example: wget --content-disposition https://raw.githubusercontent.com/clickbg/vrops-public-health-dashboard/master/vropsphd.sh -O /usr/local/sbin/vropsphd/vropsphd.sh  

8. Set owner and permissions  
Example: chown vropsphd:vropsphd /usr/local/sbin/vropsphd/vropsphd.sh && chmod 700 /usr/local/sbin/vropsphd/vropsphd.sh  

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
