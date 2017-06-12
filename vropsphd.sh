#!/bin/bash
## License: GNU General Public License v2.0
## Author: Daniel Zhelev
## Version: 1.0

######## Script config

### Where to run the script from, be careful as we will be creating sub-directories
### This path needs to exists
RUN_DIR="/usr/local/sbin/vropsphd"

### Set the maximum vROPs objects that will be processes in parallel
MAX_PARALLEL_OBJECTS="4"

######## vROPs config

### URL of your vROPs LB or master node
VROPS_URL=""

### Should we skip certificate verification yes/no
VROPS_SKIP_CRT_VRF="yes"

### vROPs user and password. The respective user needs read-only rights and REST API access
VROPS_USER=""
VROPS_PASS=""

### ID of the vROPs custom group containing all the objects that will appear in Cachet
### Please read the README if you have issues creating this
VROPS_CUSTOM_GROUP_ID=""

### Level of alerts that you want to import into Cachet
### Please keep the exact syntax as the example below 
### EXAMPLE: VROPS_ALERT_LEVEL='"CRITICAL","IMMEDIATE","WARNING","INFORMATION"'
VROPS_ALERT_LEVEL='"CRITICAL"'

### Set the sub-category for which you want to import alerts into Cachet
### Usually you would want to keep those to 18 and 19 if you are building public health dashboard
### Please keep the exact syntax as the example below 
## 18 - Availability - Alerts that indicate the problems with resource availability
## 19 - Performance - Alerts that indicate performance problems
## 20 - Capacity - Alerts that indicate capacity planning problems
## 21 - Compliance - Alerts that indicate compliance problems
## 22 - Configuration - Alerts that indicate configuration problems
## EXAMPLE: VROPS_ALERT_SUBCATEGORY='"18","19"'
VROPS_ALERT_SUBCATEGORY='"18","19"'

######## Cachet config

### Cachet URL
CACHET_URL=""

### Should we skip certificate verification - yes/no
CACHET_SKIP_CRT_VRF="yes"

### Cachet api key
CACHET_API_KEY=""




######################## END OF CONFIGURATION

TMP="$RUN_DIR/tmp"
DATE=$(date +%Y-%m-%d\ %H:%M:%S)



############### Helper functions

#### Exit function
die()
 {
   echo "$DATE $@" >&2
   exit 1
  }

### Function to break out of the main loop
skip()
 {
   echo "$DATE $@" >&2
   continue
  }



#### vROPs curl connect command
VROPS_CURL()
 {
   case "$VROPS_SKIP_CRT_VRF" in
     [yY][eE][sS]|[yY])
        curl -u $VROPS_USER:$VROPS_PASS -k -s -H "Accept: application/json" -H 'Content-Type: application/json' --connect-timeout 15 $@
        ;;
     *)
        curl -u $VROPS_USER:$VROPS_PASS -s -H "Accept: application/json" -H 'Content-Type: application/json' --connect-timeout 15 $@
        ;;
   esac
  }



#### Cachet curl connect command
CACHET_CURL()
 {
   case "$CACHET_SKIP_CRT_VRF" in
     [yY][eE][sS]|[yY])
        curl -k -s -H "Content-Type: application/json;" -H "X-Cachet-Token: $CACHET_API_KEY" --connect-timeout 15 $@
        ;;
     *)
        curl -s -H "Content-Type: application/json;" -H "X-Cachet-Token: $CACHET_API_KEY" --connect-timeout 15 $@
        ;;
   esac
  }



############### Setup and collect basic info



#### Setup directory structure and test connectivity to vROPs and Cachet
setup_env()
 {

# Check for jq, we really need jq
   test -x $(which jq) || die "jq was not found in your path. Please install jq 1.5 and re-run the script."

# Create dirs
   test -w $RUN_DIR || die  "$RUN_DIR cannot be found or is not writable. Please create it first."
   test -w $TMP     || mkdir $TMP     || die  "$TMP cannot be created"
   test -w $RUN_DIR/open_incidents.json || touch $RUN_DIR/open_incidents.json || die  "$RUN_DIR/open_incidents.json cannot be created"
   test -w $RUN_DIR/cachet_components.json || touch $RUN_DIR/cachet_components.json || die  "$RUN_DIR/cachet_components.json cannot be created"

# Test connection to vROPs and Cachet
  VROPS_HTTP_CODE=$(VROPS_CURL -s -o /dev/null -w "%{http_code}" -X GET $VROPS_URL/suite-api/api/versions/current)
  if [[ "$VROPS_HTTP_CODE" != +(200|204) ]]
   then
    die "vROPs at address: $VROPS_URL is not accessible. HTTP code: $VROPS_HTTP_CODE"
  fi

  CACHET_HTTP_CODE=$(CACHET_CURL -s -o /dev/null -w "%{http_code}" -X GET $CACHET_URL/api/v1/components)
  if [[ "$CACHET_HTTP_CODE" != +(200|204) ]]
   then
    die "Cachet at address: $CACHET_URL is not accessible. HTTP code: $CACHET_HTTP_CODE"
  fi

# Retrive all vROPs custom group members and compile list of their resourceIds for processing in main()
  VROPS_CURL -X GET $VROPS_URL/suite-api/api/resources/$VROPS_CUSTOM_GROUP_ID/relationships > $TMP/$VROPS_CUSTOM_GROUP_ID.vROPS.custom.group.members.json
  [[ $? -ne 0 ]] && die "Failed to retrive list of vROPs custom group members for group: $VROPS_CUSTOM_GROUP_ID. Please check if the custum group id is correct."

  VROPS_RESOURCE_ID_LIST=$(jq -re '.resourceList[].identifier' $TMP/$VROPS_CUSTOM_GROUP_ID.vROPS.custom.group.members.json)
  [[ $? -ne 0 ]] && die "Failed to compile list of vROPs custom group members for group: $VROPS_CUSTOM_GROUP_ID. Please check if the custum group id is correct."
  [[ -z $VROPS_RESOURCE_ID_LIST ]] && die "Failed to compile list of vROPs custom group members for group: $VROPS_CUSTOM_GROUP_ID. Please check if the custum group id is correct."

 }



### Collect vROPs and Cachet info for $VROPS_RESOURCE_ID
collect_vrops_info()
 {

# Collect vROPs name for $VROPS_RESOURCE_ID
   OBJECT_NAME=$(jq -re --arg VROPS_RESOURCE_ID "$VROPS_RESOURCE_ID" \
   '.resourceList[] | select(.identifier==$VROPS_RESOURCE_ID)|.resourceKey.name' $TMP/$VROPS_CUSTOM_GROUP_ID.vROPS.custom.group.members.json)
   [[ $? -ne 0 ]] && skip "Cannot compile object name for vROPs resourceId: $VROPS_RESOURCE_ID. Skipping."

# Collect and save all vROPs alerts for $VROPS_RESOURCE_ID
   VROPS_CURL -X GET $VROPS_URL/suite-api/api/alerts?resourceId=$VROPS_RESOURCE_ID | jq -re '.' > $TMP/$VROPS_RESOURCE_ID.vROPS.alerts.json
   [[ $? -ne 0 ]] && skip "Cannot retrive vROPs alerts for $OBJECT_NAME. Skipping."


 }



############### Cachet component managment



##### Helper functions called from manage_cachet_components



#### Check Cachet components
check_cachet_component()
 {
  local CACHET_OBJECT_ID=$@

# Check in Cachet. If $CACHET_OBJECT_ID is not found locally the object is not present in Cachet. So no point in going with further checks.
  if [[ -z $CACHET_OBJECT_ID ]]
   then
    echo 404
    return 404
  fi

# Found locally so lets check in Cachet
  local CACHET_COMPONENT_HTTP_CODE=$(CACHET_CURL -s -o /dev/null -w "%{http_code}" -X GET $CACHET_URL/api/v1/components/$CACHET_OBJECT_ID)

# If the Object is found locally, but not in Cachet, then someone deleted it manually from Cachet so return 410 - Gone.
  if [[ ! -z $CACHET_OBJECT_ID ]] && [[ $CACHET_COMPONENT_HTTP_CODE = 404 ]]
   then
    echo 410
    return 410
  fi

# In all other cases return the Cachet HTTP code
  echo $CACHET_COMPONENT_HTTP_CODE
  return $CACHET_COMPONENT_HTTP_CODE

 }



#### Delete Cachet components
delete_cachet_component()
 {
  local VROPS_RESOURCE_ID=$@

# Get Cachet resource id
  if [[ -z $CACHET_OBJECT_ID ]]
   then
    local CACHET_OBJECT_ID=$(jq -re --arg VROPS_RESOURCE_ID "$VROPS_RESOURCE_ID" \
    '.component[]|select(.vrops_id==$VROPS_RESOURCE_ID)|.cachet_id' $RUN_DIR/cachet_components.json)
    [[ $? -ne 0 ]] && skip "Cannot find Cachet id for object: $OBJECT_NAME in $RUN_DIR/cachet_components.json. Skipping."
  fi


# Remove from Cachet
    local CACHET_DELETE_COMPONENT_HTTP_CODE=$(CACHET_CURL -s -o /dev/null -w "%{http_code}" -X DELETE $CACHET_URL/api/v1/components/$CACHET_OBJECT_ID)
     if [[ "$CACHET_DELETE_COMPONENT_HTTP_CODE" != +(200|204) ]]
      then
       skip "Cannot remove Cachet component: $OBJECT_NAME HTTP code: $CACHET_DELETE_COMPONENT_HTTP_CODE. Please remove it manually. Skipping."
     fi

# Remove from local file containing all Cachet components
   jq -r --arg CACHET_OBJECT_ID "$CACHET_OBJECT_ID" 'select(.component[]|.cachet_id!=$CACHET_OBJECT_ID)' $RUN_DIR/cachet_components.json > $TMP/cachet_components.json
   [[ $? -ne 0 ]] && skip "Failed to remove $OBJECT_NAME from $RUN_DIR/cachet_components.json. Please remove it manually. Skipping."
   mv $TMP/cachet_components.json $RUN_DIR/cachet_components.json

# Verify removal
   grep -wq "$CACHET_OBJECT_ID" $RUN_DIR/cachet_components.json
   [[ $? -eq 0 ]] && skip "Failed to remove $OBJECT_NAME from $RUN_DIR/cachet_components.json. Please remove it manually. Skipping."

}



#### Creates Cachet components
create_cachet_component()
 {
  local VROPS_RESOURCE_ID=$@

# Generate Cachet component config
   cat <<EOF > $TMP/$VROPS_RESOURCE_ID.Cachet.component.config.json
         {
         "name": "$OBJECT_NAME",
         "status": 1,
         "link": "$VROPS_URL/ui/index.action#/object/$VROPS_RESOURCE_ID/summary",
         "enabled": "true"
         }
EOF


# Create Cachet components for $VROPS_RESOURCE_ID
   local CACHET_OBJECT_ID=$(CACHET_CURL -X POST $CACHET_URL/api/v1/components --data @$TMP/$VROPS_RESOURCE_ID.Cachet.component.config.json | jq -re '.data.id')
   [[ $? -ne 0 ]] && skip "Failed to create Cachet component for $OBJECT_NAME. Skipping."


# Check if the component was saved
   local CACHET_COMPONENT_HTTP_CODE=$(CACHET_CURL -s -o /dev/null -w "%{http_code}" -X GET $CACHET_URL/api/v1/components/$CACHET_OBJECT_ID)
    if [[ "$CACHET_COMPONENT_HTTP_CODE" != +(200|204) ]]
     then
      skip "Failed to create Cachet component for $OBJECT_NAME. HTTP code: $CACHET_COMPONENT_HTTP_CODE. Skipping"
    fi


# Save Cachet component configuration
   cat <<EOF >> $RUN_DIR/cachet_components.json
         {
         "component": [
          {
           "name" : "$OBJECT_NAME",
           "cachet_id" : "$CACHET_OBJECT_ID",
           "vrops_id"  : "$VROPS_RESOURCE_ID",
           "vrops_custom_group_id" : "$VROPS_CUSTOM_GROUP_ID"
          }
         ]
        }
EOF

  echo $CACHET_OBJECT_ID

 }



#### Manage the availability status of OBJECT in Cachet based on the vROPs System Attributes|availability metric
manage_cachet_availability()
 {
  local CACHET_OBJECT_ID=$@

# Get vROPS metric System Attributes|availability
   local VROPS_SYSATTR_AVAIL=$(VROPS_CURL -X GET \
   "$VROPS_URL/suite-api/api/resources/stats/latest?resourceId=$VROPS_RESOURCE_ID&statKey=System%20Attributes|availability" | jq '.values[]."stat-list".stat[].data[]')

# vROPs: 1 = Avaliable, 0 or -1 = not avaliable
# Cachet: 1 = Operational, 2 = Performance issue, 3 = Partial outage, 4 = Major Outage

   if [ "$VROPS_SYSATTR_AVAIL" -ge 1 ]; then
     SET_CACHET_HEALTH=$(CACHET_CURL -s -o /dev/null -w "%{http_code}" -X PUT $CACHET_URL/api/v1/components/$CACHET_OBJECT_ID --data '{"status":1}')
     [[ "$SET_CACHET_HEALTH" != +(200|204) ]] && skip "Failed to set Cachet availability for $OBJECT_NAME. Skipping."
   else
     SET_CACHET_HEALTH=$(CACHET_CURL -s -o /dev/null -w "%{http_code}" -X PUT $CACHET_URL/api/v1/components/$CACHET_OBJECT_ID --data '{"status":4}')
     [[ "$SET_CACHET_HEALTH" != +(200|204) ]] && skip "Failed to set Cachet availability for $OBJECT_NAME. Skipping."
   fi

}



#### Check/create/delete Cachet components
manage_cachet_components()
 {

# Try to get the Cachet component id from the vROPs $VROPS_RESOURCE_ID
  CACHET_OBJECT_ID=$(jq -r --arg VROPS_RESOURCE_ID "$VROPS_RESOURCE_ID" \
  '.component[]|select(.vrops_id==$VROPS_RESOURCE_ID)|.cachet_id' $RUN_DIR/cachet_components.json)

# Check if we already have Cachet component for this. If we don't create one.
   CACHET_COMPONENT_EXISTS=$(check_cachet_component $CACHET_OBJECT_ID)
     case "$CACHET_COMPONENT_EXISTS" in
      404)
        CACHET_OBJECT_ID=$(create_cachet_component $VROPS_RESOURCE_ID)
        [[ -z $CACHET_OBJECT_ID ]] && skip "Failed to create Cachet component for object: $OBJECT_NAME. Skipping."
        manage_cachet_availability $CACHET_OBJECT_ID
        ;;
      410)
        jq -r --arg VROPS_RESOURCE_ID "$VROPS_RESOURCE_ID" 'select(.component[]|.vrops_id!=$VROPS_RESOURCE_ID)' $RUN_DIR/cachet_components.json > $TMP/cachet_components.json
        [[ $? -ne 0 ]] && skip "Cannot remove orphan Cachet component: $OBJECT_NAME from $RUN_DIR/cachet_components.json. Please remove it manually. Skipping."
        mv $TMP/cachet_components.json $RUN_DIR/cachet_components.json
        grep -wq "$VROPS_RESOURCE_ID" $RUN_DIR/cachet_components.json
        [[ $? -eq 0 ]] && skip "Failed to remove orphan Cachet component: $OBJECT_NAME from $RUN_DIR/cachet_components.json. Please remove it manually. Skipping."
        ;;
      200)
        manage_cachet_availability $CACHET_OBJECT_ID
        ;;
      *)
        skip "Unexpected Cachet return code HTTP:$CACHET_COMPONENT_EXISTS when checking for component: $OBJECT_NAME. Skipping."
      esac

}



#### Cleanup old Cachet components, not called from main()
cleanup_cachet_components()
 {

# Remove Cachet components that are no longer present in the vROPs custom group
   ACTIVE_CACHET_OBJECTS=$(jq -re '.component[].vrops_id' $RUN_DIR/cachet_components.json)
     for ACTIVE_CACHET_OBJECT in $ACTIVE_CACHET_OBJECTS
      do
       jq -re --arg ACTIVE_CACHET_OBJECT "$ACTIVE_CACHET_OBJECT" \
       '.resourceList[] | select(.identifier==$ACTIVE_CACHET_OBJECT)' $TMP/$VROPS_CUSTOM_GROUP_ID.vROPS.custom.group.members.json >/dev/null
        if [[ $? -ne 0 ]]
         then
          delete_cachet_component $ACTIVE_CACHET_OBJECT
        fi
      done

 }



############### Cachet incident managment



##### Helper functions called from manage_cachet_incidents



#### Check if vROPs alert exists as Cachet incident
check_cachet_incident()
 {
  local ALERT=$@

# Get the Cachet incident id from the vROPs alert id
  local ACTIVE_CACHET_INCIDENT_ID=$(jq -r --arg ALERT "$ALERT" \
  '.incident[] | select(.vrops_alert_id==$ALERT) | .cachet_incident_id' $RUN_DIR/open_incidents.json)

# Check in Cachet
  if [[ -z $ACTIVE_CACHET_INCIDENT_ID ]]
   then
    echo 404
    return 404
  fi

# Found locally so lets check in Cachet
  local ACTIVE_CACHET_INCIDENT_HTTP_CODE=$(CACHET_CURL -s -o /dev/null -w "%{http_code}" -X GET $CACHET_URL/api/v1/incidents/$ACTIVE_CACHET_INCIDENT_ID)

# If the alert is found locally, but not in Cachet, then someone deleted it manually from Cachet so return 410 - Gone.
  if [[ ! -z $ACTIVE_CACHET_INCIDENT_ID ]] && [[ $ACTIVE_CACHET_INCIDENT_HTTP_CODE = 404 ]]
   then
    echo 410
    return 410
  fi

# In all other cases return the Cachet HTTP code
  echo $ACTIVE_CACHET_INCIDENT_HTTP_CODE
  return $ACTIVE_CACHET_INCIDENT_HTTP_CODE

 }



#### Create Cachet incident from vROPs alert
create_cachet_incident()
 {
  local ALERT=$@

# Get alert subject
   local ALERT_SUBJECT=$(jq -re --arg ALERT "$ALERT" \
   '.alerts[] | select(.alertId==$ALERT) .alertDefinitionName' $TMP/$VROPS_RESOURCE_ID.vROPS.alerts.json)
   [[ $? -ne 0 ]] && skip "Failed get the alert subject for alert: $ALERT and object: $OBJECT_NAME. Skipping."

# Prepare incident, you can customize this part. Cachet uses markdown.
   cat <<EOF > $TMP/$VROPS_RESOURCE_ID.$ALERT.json
         {
          "name": "$ALERT_SUBJECT",
          "message": "**System:** [$OBJECT_NAME]($VROPS_URL/ui/index.action#/object/$VROPS_RESOURCE_ID/summary) \n\n**Message:** [$ALERT_SUBJECT]($VROPS_URL/ui/index.action#/alert/$ALERT/summary)",
          "status": 1,
          "visible": 1,
          "component_id": $CACHET_OBJECT_ID,
          "component_status": 1,
          "notify": "true"
         }
EOF

# Log incident
   local CACHET_INCIDENT_ID=$(CACHET_CURL -X POST $CACHET_URL/api/v1/incidents --data @$TMP/$VROPS_RESOURCE_ID.$ALERT.json | jq -re '.data.id')
   [[ $? -ne 0 ]] && skip "Failed to log Cachet incident for alert $ALERT and object: $OBJECT_NAME. Skipping."


# Check if the incident was saved
   local CACHET_INCIDENT_HTTP_CODE=$(CACHET_CURL -s -o /dev/null -w "%{http_code}" -X GET $CACHET_URL/api/v1/incidents/$CACHET_INCIDENT_ID)
    if [[ "$CACHET_INCIDENT_HTTP_CODE" != +(200|204) ]]
     then
      skip "Failed to create Cachet incident for $OBJECT_NAME. HTTP code: $CACHET_INCIDENT_HTTP_CODE. Skipping"
    fi


# Save active incidents in json
   cat <<EOF >> $RUN_DIR/open_incidents.json
         {
         "incident": [
          {
           "name" : "$OBJECT_NAME",
           "cachet_id" : "$CACHET_OBJECT_ID",
           "vrops_id"  : "$VROPS_RESOURCE_ID",
           "vrops_alert_id" : "$ALERT",
           "cachet_incident_id" : "$CACHET_INCIDENT_ID"
          }
         ]
        }
EOF

 }



#### Cancels incident from Cachet
cancel_cachet_incident()
 {
  local ALERT=$@

# Get the Cachet incident id from the vROPs alert id
   local CACHET_INCIDENT_ID=$(jq -re --arg ALERT "$ALERT" \
   '.incident[] | select(.vrops_alert_id==$ALERT) | .cachet_incident_id' $RUN_DIR/open_incidents.json)
   [[ $? -ne 0 ]] && skip "Cannot retrive Cachet incident id from from $RUN_DIR/open_incidents.json. Skipping."

# Cancel incident, don't verify status since a human might have deleted the alert manually
   CACHET_CURL -X PUT $CACHET_URL/api/v1/incidents/$CACHET_INCIDENT_ID --data '{"status":4}' >/dev/null

# Delete incident from local file of open incidents
   jq -r --arg ALERT "$ALERT" 'select(.incident[]|.vrops_alert_id!=$ALERT)' $RUN_DIR/open_incidents.json > $TMP/open_incidents.tmp.json
   [[ $? -ne 0 ]] && skip "Cannot remove incident from $RUN_DIR/open_incidents.json. Skipping."
   mv $TMP/open_incidents.tmp.json $RUN_DIR/open_incidents.json

# Verify removal
   grep -wq "$ALERT" $RUN_DIR/open_incidents.json
   [[ $? -eq 0 ]] && skip "Failed to remove $ALERT from $RUN_DIR/open_incidents.json. Please remove it manually. Skipping."

 }



#### Manage the creation and deletion of incidents
manage_cachet_incidents()
 {

# Collect all Cachet incidents for $VROPS_RESOURCE_ID
   CACHET_CURL -X GET $CACHET_URL/api/v1/incidents?component_Id=$CACHET_OBJECT_ID | jq -re '.' > $TMP/$VROPS_RESOURCE_ID.Cachet.incidents.json
   [[ $? -ne 0 ]] && skip "Cannot retrive Cachet incidents for $OBJECT_NAME. Skipping."

# Cancel old incidents for which the vROPs alerts are no longer active
   OPEN_ALERTS=$(jq -re --arg VROPS_RESOURCE_ID "$VROPS_RESOURCE_ID" \
   '.incident[] | select(.vrops_id==$VROPS_RESOURCE_ID) | .vrops_alert_id' $RUN_DIR/open_incidents.json)
     for OPEN_ALERT in $OPEN_ALERTS
      do
       jq -re --arg OPEN_ALERT "$OPEN_ALERT" '.alerts[] | select(.status=="ACTIVE") | select(.alertId==$OPEN_ALERT)' $TMP/$VROPS_RESOURCE_ID.vROPS.alerts.json >/dev/null
        if [[ $? -ne 0 ]]
         then
          cancel_cachet_incident $OPEN_ALERT
        fi
      done

# Create new incidents from vROPs alerts
   ACTIVE_ALERTS_LIST=$(jq -re \
   '.alerts[] | select(.status=="ACTIVE") | select(.subType | contains('$VROPS_ALERT_SUBCATEGORY')) | select(.alertLevel | contains('$VROPS_ALERT_LEVEL')) | .alertId' $TMP/$VROPS_RESOURCE_ID.vROPS.alerts.json)
    for ALERT in $ACTIVE_ALERTS_LIST
     do
# Check if we already have incident for this. If we don't create one.
   CACHET_INCIDENT_EXISTS=$(check_cachet_incident $ALERT)
     case "$CACHET_INCIDENT_EXISTS" in
      404)
        create_cachet_incident $ALERT
        ;;
      410)
        jq -r --arg ALERT "$ALERT" 'select(.incident[]|.vrops_alert_id!=$ALERT)' $RUN_DIR/open_incidents.json > $TMP/open_incidents.tmp.json
        [[ $? -ne 0 ]] && skip "Cannot remove orphan incident id: $ALERT from $RUN_DIR/open_incidents.json. Please remove it manually. Skipping."
        mv $TMP/open_incidents.tmp.json $RUN_DIR/open_incidents.json
        grep -wq "$ALERT" $RUN_DIR/open_incidents.json
        [[ $? -eq 0 ]] && skip "Cannot remove orphan incident id: $ALERT from $RUN_DIR/open_incidents.json. Please remove it manually. Skipping."
        ;;
      200)
        ;;
      *)
        skip "Unexpected Cachet return code HTTP:$CACHET_INCIDENT_EXISTS when checking for open incidents for $OBJECT_NAME. Skipping."
      esac
    done

 }



#### Cleanup our $TMP
cleanup_env()
 {
  rm -f $TMP/*.json >/dev/null 2>&1
 }



#### Main function calling all major sub-functions. If you want to disable something comment it out here.
main()
 {
# Setup our env
   umask 0077
   cd $RUN_DIR
   setup_env
   cleanup_cachet_components

# Process maximum $MAX_PARALLEL_OBJECTS OBJECTs in parallel
   cur_running=0

   for VROPS_RESOURCE_ID in $VROPS_RESOURCE_ID_LIST
    do
     if [ $cur_running -ge $MAX_PARALLEL_OBJECTS ] ; then
         wait
         cur_running=0
     fi
       ( 
         collect_vrops_info
         manage_cachet_components
         manage_cachet_incidents
       ) &
         let "cur_running++"
    done
    wait
    
    cleanup_env
 }

#### Run
main
