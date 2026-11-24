# Technical Assesment Project

## Design

I chose to utilize a shell script for cluster provisioning primarily to avoid the overhead of other utilities and maximize environmental portability. The provided script and configuration file enable provisioning a Kubernetes cluster with one control plane node and as many worker nodes as provided in the settings file. `cluster-provision.sh` installs the Calico CNI, MetalLB, Kubernetes Gateway API, Kgateway, and Cert Manager. 

Ansible was considered for cluster provisioning, but due to the requirement for installing additional utilities, and this being a Proof of Concept level project was rejected. This script should function for clusters on bare metal, vms, and cloud compute instances. Additionally it could be utilized in IaC utilities like CloudFormation, and Terraform to add full infrastructure deployment automation. 

The cluster is provisioned such that TLS terminates at the gateway, meaning traffic between the gateway and Nginx pod is unecrypted. Security posture could be improved by Changing TLS termination to occur at the Nginx pod, adding configuration to Cert-Manager for cluster-internal mTLS, or the deployment of a service mesh like Istio.

Cert Manager is configured to issue self-signed certificates as this is intended to provide a development environment for Johnny to learn with. Johnny will be required to edit his hosts file to provide DNS resolution to test his application.

The provisioning script creates a role for our imaginary summer intern named Johnny Droptables, which limits his permissions to what is needed to deploy and observe his nginx hosted application. 

## Install

### Pre-requisites

1. 3+ Ubuntu 24.04 Server machines/virtual machines.
---Configured for SSL key authentication, and passwordless `sudo`. (Most Cloud provider's compute instances ship with this configuration)

### Install

1. Download/Clone this repo.
2. Edit `kube-deploy/cluster/settings.conf` to conform to your environment. 
---`control_node`, `worker_nodes`, `ssh_user`, and `ssh_key_path` will need to be edited from defaults, other settings will function as is and are provided for customization.
3. Run `kube-deploy/cluster/cluster-provision.sh`

### Johnny Instructions

1. SSH to the control node machine
2. Deploy helm chart
3. Edit hosts file
4. Check site

## Notes

* `cluster-provision.sh` is not idempotent running the script on the same infrastructure multiple times could break the deployment. This is a possible area of improvement, or a reason to refactor to a utility like Ansible.
* Johnny is provided with a legacy long-lived cluster authentication token, which is not secure. Providing instructions or a token request script that updates Johnny's kubeconfig for him would solve this. Or adding an identity management utility like Teleport would solve this.