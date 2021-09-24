#!/usr/bin/env bash
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Set up some functions, initialize vars
SAFEMODE=1
ALREADYHOST=1
K8S=0
COUNT=0
ERROR=0
ERRORMSG="OK"

# Error out function to call if needed
ERROR_OUT() {
    if [ $ERROR -ne 0 ]; then
        echo ""
        echo $ERRORMSG
        echo "See help:"
        SHOW_HELP
        exit
    fi
}

# Arguments and switches input
if [[ ${#} -eq 0 ]]; then
    ERROR_OUT
else
    while getopts "h:c:n:s:kz" OPTION; do
        case $OPTION in
            h) HOSTPROJECT_ID=${OPTARG};;
            c) CHILDPROJECT_ID=${OPTARG};;
            n) NETWORK=${OPTARG};;
            s) SUBNET=${OPTARG};;
            k) K8S=1;;
            z) SAFEMODE=0;;
            \?) ERRORMSG="Unknown option: -$OPTARG";ERROR_OUT;;
            :) ERRORMSG="Missing option argument for -$OPTARG.";ERROR_OUT;;
            *) ERRORMSG="Unimplemented option: -$OPTARG";ERROR_OUT;;
        esac
    done
fi

# Shows help function and instructions if errors are found
SHOW_HELP() {
    echo "NETWORK SHARE SCRIPT HELP"
    echo "  Use format ./share-vpc.sh -h <host project> -c <child project> -n <network to share> -s <subnet to share>"
    echo "      <host project>: This is the project ID of the host project, which will share its networks and subnets with other child projects"
    echo "      <child project>: Project ID of the child project, who will create resources in the parent project's network and subnets"
    echo "      <network to share>: Name of the network in the host project that will be shared"
    echo "      <subnet to share>: The specific subnet name you wish to share"
    echo " "
    echo " Optional flags:"
    echo "      -k: enable GKE access to the subnet"
    echo "      -z: skip error checking and validation of inputs"
    echo " "
    echo "  Examples:"
    echo "      ./share-vpc.sh -h shared-svc-project -c my-app-project -n shared-vpc-network -s app-project-subnet"    
}

# Make sure the user entered the correct # of args.  Merge into one function to do all validation in one function
COUNT_ARGS() {
    if [ -z "$HOSTPROJECT_ID" ] || [ -z "$CHILDPROJECT_ID" ] || [ -z "$NETWORK" ] || [ -z "$SUBNET" ]; then
        ERROR=1
        ERRORMSG="ERRORS FOUND IN ARGUMENTS - One or more required arguments not found"
        ERROR_OUT
    fi
}

#Check the project(s) to make sure it exists
CHECK_PROJECT() {
	gcloud projects describe $1 > /dev/null 2>&1
        if [ $? -ne 0 ]; then
            ERROR=1
            ERRORMSG="ERRORS FOUND IN ARGUMENTS - One or more projects not found, please verify project IDs"
            ERROR_OUT
        fi
    echo "Project $1 verified"   
}

# Check destination network to make sure it exists
CHECK_NETWORK() {
    echo "Checking network $NETWORK"
    gcloud compute networks list | grep -w $NETWORK > /dev/null 2>&1
        if [ $? -ne 0 ]; then
            ERROR=1 
            ERRORMSG="ERRORS FOUND IN ARGUMENTS - Network '$NETWORK' not found, please check network name"
        fi
    
    echo "Checking subnet $SUBNET..."
    gcloud compute networks subnets list | grep -iw $SUBNET > /dev/null 2>&1
        if [ $? -ne 0 ]; then
            ERROR=1 
            ERRORMSG="ERRORS FOUND IN ARGUMENTS - Subnet '$SUBNET' not found, please check subnet name"
            ERROR_OUT #error out if there are any issues
        fi 
}

#Verify all the things before proceeding!
if [ $SAFEMODE -ne 0 ]; then
    echo "Running pre-flight checks..."
    COUNT_ARGS
    CHECK_PROJECT "$HOSTPROJECT_ID" 
    CHECK_PROJECT "$CHILDPROJECT_ID" 
    CHECK_NETWORK 
    echo "Validated command arguments..."
    else 
        echo "-z detected: Safe mode disabled, proceeding without pre-flight checks..."
fi

#Check that we're in the correct project to have CLI work appropriately.
echo "Checking if we are already in the project..."
CURRENTPROJECT=$(gcloud config list project | grep project | awk ' { print $3 } ')
if [ "$CURRENTPROJECT" != "$HOSTPROJECT_ID" ]; then
    echo "Setting $HOSTPROJECT_ID as current project"
    gcloud config set project $HOSTPROJECT_ID
    if [ $? -ne 0 ]; then
        echo "Could not set project to $HOSTPROJECT_ID, exiting"
        ERROR_OUT
        exit
    fi
    else
        echo "Already in $HOSTPROJECT_ID, continuing!"
fi

#Enable shared project host if not already
echo "Checking if $HOSTPROJECT_ID is already a shared VPC host project..."
gcloud compute shared-vpc list-associated-resources $HOSTPROJECT_ID > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "$HOSTPROJECT_ID is not currently a shared project"
        echo "To continue, $HOSTPROJECT_ID must be set to shared VPC host. If this is not desired, abort when prompted..."
        ALREADYHOST=0
        else
            echo "$HOSTPROJECT_ID is already a shared VPC host, continuing..."   
    fi

#Now we can start!
echo ""
echo -e "Confirm: sharing subnet \e[32m$SUBNET\e[0m from network \e[32m$NETWORK\e[0m in project \e[32m$HOSTPROJECT_ID\e[0m with \e[32m$CHILDPROJECT_ID\e[0m...?"
read -p "Press enter to continue, or ctrl-c to abort!" </dev/tty

echo "Continuing..."
echo "Getting Region of subnet $SUBNET"
REGION=$(gcloud compute networks subnets list --filter=$SUBNET | grep -iw REGION | awk '{print $2}')
    if [ $? -ne 0 ]; then
        ERROR=1 
        ERRORMSG="UNABLE TO GET REGION OF $SUBNET"
    fi
echo "Region is $REGION..."

#Dump out the existing share settings of the SN
echo "Saving IAM policy of subnet $SUBNET before making changes"
gcloud beta compute networks subnets get-iam-policy $SUBNET --region $REGION --project $HOSTPROJECT_ID --format json > $SUBNET.orig.json
echo "Saved to JSON formatted IAM policy to: $SUBNET.iam-orig.json"
echo "Refer to this later in case permission issues are encountered"

#Enable host project if needed
if [ $ALREADYHOST -ne 1 ]; then
    echo "Enabling shared VPC host for project $HOSTPROJECT_ID..."
    gcloud compute shared-vpc enable $HOSTPROJECT_ID
        if [ $? -ne 0 ]; then
            ERROR=1 
            ERRORMSG="UNABLE TO SET $HOSTPROJECT_ID TO SHARED VPC HOST"
        fi
fi

echo "Adding $CHILDPROJECT_ID association to host project..."
gcloud compute shared-vpc associated-projects add $CHILDPROJECT_ID --host-project=$HOSTPROJECT_ID
    if [ $? -ne 0 ]; then
        ERROR=1 
        ERRORMSG="UNABLE TO ADD $CHILDPROJECT_ID AS SHARED PROJECT"
    fi

#Share specific subnet, By default this includes the following roles from the child project:
# - Compute Instance Admins
# - Compute Network Admins
# - Owners
# - Editors
echo "Getting current permissions on child project..."
gcloud projects get-iam-policy $CHILDPROJECT_ID --flatten="bindings[].members" \
    --filter="bindings.role=( 'roles/owner' OR 'roles/editor' OR 'roles/compute.networkAdmin' OR 'roles/compute.instanceAdmin')" \
    --format table"(bindings.role,bindings.members)" | grep @ | awk '{ print $2 }' | while read MEMBER 
        do
            echo "Adding $MEMBER as compute.networkUser"
            gcloud beta compute networks subnets add-iam-policy-binding $SUBNET \
                --region=$REGION --member=$MEMBER --role='roles/compute.networkUser'
                if [ $? -ne 0 ]; then
                    echo "Failed to add user $MEMBER"
                    ERROR=1 
                    ERRORMSG="failed to add one or more members to IAM policy binding on $SUBNET"
                fi
        done

        #Handle K8s Service Account if -k
        if [ $K8S -ne 0 ]; then
            echo "-k was detected, enabling Kubernetes access to shared VPC..."
            #get k8s service account
            K8SACCT=$(gcloud projects get-iam-policy $CHILDPROJECT_ID --flatten="bindings[].members" \
            --filter="bindings.role=( 'roles/container.serviceagent' )" \
            --format table"(bindings.role,bindings.members)" | grep @ | awk '{ print $2 }')
                if [ -z "$K8SACCT" ]; then
                    echo "Not able to find Kubernetes service account"
                    ERROR=1 
                    ERRORMSG="Failed to add Kubernetes integration for $SUBNET - Is GKE API enabled?"
                    ERROR_OUT
                else      
                    echo "Adding $K8SACCT to $SUBNET"
                    gcloud beta compute networks subnets add-iam-policy-binding $SUBNET \
                    --region=$REGION --member=$K8SACCT --role='roles/compute.networkUser'
                        if [ $? -ne 0 ]; then
                            echo "failed Kubernetes service account $K8SACCT"
                            ERROR=1 
                            ERRORMSG="Failed to add Kubernetes integration for $SUBNET - Is GKE API enabled?"
                        fi
                fi
        fi

#Done, so check error level and error out if so
ERROR_OUT
echo "Done!"