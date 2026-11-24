# Technical Assesment Project

## Design

I chose to utilize a shell script for cluster provisioning primarily to avoid the overhead of other utilities and maximize environmental portability. The provided script and configuration file enable provisioning a Kubernetes cluster with one control plane node and as many worker nodes as provided in the settings file. `cluster-provision.sh` installs the Calico CNI, MetalLB, Kubernetes Gateway API, Kgateway, and Cert Manager. Ansible was considered for cluster provisioning, but due to the requirement for installing additional utilities, and this being a Proof of Concept level project was rejected. This script should function for clusters on bare metal, vms, and cloud compute instances. Additionally it could be utilized in IaC utilities like CloudFormation, and Terraform to add full infrastructure deployment automation. The provisioning script creates a role for our imaginary user named Johnny Droptables, which limits his permissions to what is needed to deploy and observe his nginx hosted application. 

## Install

### Pre-requisites

1. 3+ Ubuntu 24.04 Server machines/virtual machines.
---Configured for SSL key authentication, and passwordless `sudo`. (Most Cloud provider's compute instances ship with this configuration)

### Install

1. Download/Clone this repo.
2. Edit `cluster/settings.conf` to conform to your environment. 
---`control_node`, `worker_nodes`, `ssh_user`, and `ssh_key_path` will need to be edited from defaults, other settings will function as is and are provided for customization.
3. Run `cluster/cluster-provision.sh`

