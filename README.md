# Share VPC Script

share-vpc.sh is a script developed to help automate the sharing of VPC networks and subnets with other projects in GCP.

## Disclaimer

This tool is provided without any warranty, make sure you review the script code and test accordingly with your requirements.
Always make sure you have backups and have **validated** recovery from those backups before running, especially in production environments. 

## Getting Started

* Make sure you know the host project id, child project id , and finally the network and subnet you wish to share.  
* Clone the repository, and make sure you install the Google cloud SDK (or, just run the script from CloudShell).
* If running outside of cloud shell, authenticate by running "gcloud auth login" 
* Use format: 
    - `./share-vpc.sh -h <host project> -c <child project> -n <network to share> -s <subnet to share>`

### Required options
* **-h `<host project>`**: This is the project ID of the host project, which will share its networks and subnets with other child projects"
* **-c `<child project>`**: Project ID of the child project, who will create resources in the parent project's network and subnets"
* **-n `<network to share>`**: Name of the network in the host project that will be shared"
* **-s `<subnet to share>`**: The specific subnet name you wish to share"

## Examples:
```
./share-vpc.sh -h shared-svc-project -c my-app-project -n shared-vpc-network -s app-project-subnet"    
   - This share the subnet 'app-project-subnet' with the my-app-project, allowing resources to connect to the shared-vpc-network
```

### Authors
* **Eric VanBergen** - [Github](https://github.com/vanberge) - [Personal](https://www.ericvb.com)

### License
This project is licensed under the Apache 2 License - see the [LICENSE.md](LICENSE.md) file for details
