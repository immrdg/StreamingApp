# Jenkins infrastructure setup

This directory provisions and configures a Jenkins controller for StreamingApp:

1. Terraform creates an Amazon Linux 2023 EC2 instance in the default VPC, plus the IAM role, SSH key pair, and security group needed for EC2 cloud build agents.
2. Ansible installs Jenkins over the SSM connection plugin, installs the required plugins, and deploys a **Jenkins Configuration as Code (JCasC)** file so the controller's security, admin account, and EC2 cloud agents are always reproduced from code — running the playbook again never leaves Jenkins in a different state than what is checked in.

SSH keys and inbound port 22 are not required for the controller. Jenkins port `8080` is restricted to the CIDRs supplied in `jenkins_allowed_cidrs`. A dedicated SSH key pair is generated for EC2 build agents only (the EC2 plugin uses it to bootstrap agent nodes it launches).

> **Security note:** the controller is bootstrapped with the credentials `admin` / `admin` (set in `ansible/group_vars/all/vars.yml`) so the whole environment is scriptable end to end without manual setup-wizard steps. Change these before exposing Jenkins beyond a private/test network.

## Repository layout

| Path | Purpose |
| --- | --- |
| `terraform/` | EC2 controller, IAM roles/policies, security groups, agent SSH key pair, and outputs |
| `ansible/jenkins.yml` | Jenkins host configuration playbook (packages, plugins, JCasC, systemd) |
| `ansible/templates/jenkins.casc.yaml.j2` | JCasC template: security realm, admin user, EC2 cloud + agent templates |
| `ansible/group_vars/all/vars.yml` | Static configuration (admin creds, plugin list, agent sizing) |
| `ansible/group_vars/all/terraform.yml` | Auto-generated from Terraform outputs — **do not edit by hand** |
| `ansible/inventory.aws_ec2.yml` | Dynamic inventory and SSM connection settings |
| `ansible/ansible.cfg` | Ansible inventory and AWS collection configuration |
| `scripts/render-tfvars.sh` | Renders Terraform outputs into `group_vars/all/terraform.yml` before every playbook run |

## Prerequisites

- AWS CLI authenticated to the target account
- Terraform 1.6+
- Ansible with `amazon.aws` installed
- Session Manager plugin installed locally
- An existing default VPC with at least one default subnet in the selected region
- An S3 bucket in the same region for Ansible's SSM connection transport
- An AWS identity permitted to create EC2, IAM, security-group, and SSM-related resources

The AWS CLI, Terraform, Ansible, and the Session Manager plugin must be installed on the machine running these commands. The EC2 instance needs outbound internet access to download packages and connect to AWS services.

Install the Ansible collection once:

```bash
ansible-galaxy collection install amazon.aws
```

## 1. Configure Terraform variables

Run these commands from the application root:

```bash
cd infrastructure/jenkins/terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` and replace the example CIDR with your public IPv4 address:

```hcl
aws_region           = "ap-south-1"
name_prefix          = "streamingapp"
instance_type        = "t3.medium"
root_volume_size_gb  = 30
jenkins_allowed_cidrs = ["203.0.113.10/32"]
```

Find the current public IPv4 address with:

```bash
curl -4 https://ifconfig.me
```

Do not use `0.0.0.0/0` for Jenkins access. Keep `terraform.tfvars` private; it is excluded by `.gitignore`.

EC2 cloud-agent sizing is controlled by these variables (defaults shown):

```hcl
jenkins_agent_instance_types      = ["t3.small", "c7i-flex.large"]
jenkins_agent_max_total_instances = 3
jenkins_agent_min_idle_instances  = 1
```

## 2. Create the EC2 instance and agent infrastructure

```bash
cd infrastructure/jenkins/terraform
terraform init
terraform plan
terraform apply
```

Terraform creates:

- Amazon Linux 2023 AMI lookup through the AWS public SSM parameter, used for both the controller and cloud agents.
- A `t3.medium` EC2 instance by default, with an encrypted 30 GiB gp3 root volume (the controller).
- An IAM role with `AmazonSSMManagedInstanceCore` and `AmazonEC2ContainerRegistryPowerUser`, plus an inline policy granting the controller's role `ec2:RunInstances`/`TerminateInstances`/`DescribeInstances`/etc. and `iam:PassRole` on the agent role, so the EC2 plugin can launch and terminate build agents.
- An instance profile attached to EC2.
- A security group allowing TCP `8080` only from `jenkins_allowed_cidrs` (controller) and a second security group allowing SSH only from the controller (agents).
- A dedicated IAM role/instance profile for agent nodes (SSM access only).
- An RSA key pair (`tls_private_key`/`aws_key_pair`) the EC2 plugin uses to SSH into freshly launched agents. The private key is written locally to `terraform/generated/jenkins-agent.pem` (gitignored, `0600` permissions) and consumed by Ansible when rendering the JCasC credential.
- IMDSv2 enforcement through required metadata tokens.

The default VPC and one default subnet are used; this configuration does not create networking.

Wait until SSM reports the instance as online:

```bash
aws ssm describe-instance-information \
  --region ap-south-1 \
  --filters "Key=InstanceIds,Values=$(terraform output -raw instance_id)"
```

Replace `ap-south-1` with the `aws_region` value from `terraform.tfvars` when using another region.

If the command returns no instance, wait a few minutes and verify that the EC2 instance has outbound access and that the SSM agent is running.

## 3. Configure Jenkins over SSM

> **macOS users:** Ansible's `amazon.aws.aws_ssm` connection plugin crashes natively on macOS due to a known fork-safety bug in Apple's networking frameworks (`SIGSEGV` in `Network.framework`/`CFPreferences` after `fork()`). Run Ansible inside a Linux container instead — see the Docker command below. Linux users can skip straight to running `ansible-playbook` directly.

Create the S3 transfer bucket once (used by Ansible's SSM connection plugin to move module code to the instance):

```bash
BUCKET="streamingapp-ssm-transfer-<your-account-id>"
aws s3api create-bucket \
  --bucket "$BUCKET" \
  --region ap-southeast-1 \
  --create-bucket-configuration LocationConstraint=ap-southeast-1
```

Set `ansible_aws_ssm_bucket_name` in `ansible/inventory.aws_ec2.yml` to this bucket name.

Before every playbook run, regenerate `ansible/group_vars/all/terraform.yml` from the current Terraform state so the JCasC template always reflects the live infrastructure (AMI id, security group, subnet, key pair, agent private key path):

```bash
cd infrastructure/jenkins
./scripts/render-tfvars.sh
```

### Run natively (Linux only)

```bash
cd ansible
AWS_PROFILE=<your-profile> ansible-playbook -i inventory.aws_ec2.yml jenkins.yml
```

### Run via Docker (required on macOS)

```bash
cd infrastructure/jenkins

docker run --rm \
  -v "$PWD":/jenkins \
  -v ~/.aws:/root/.aws:ro \
  -w /jenkins/ansible \
  -e AWS_PROFILE=<your-profile> \
  -e DEBIAN_FRONTEND=noninteractive \
  python:3.11-slim bash -c "
    apt-get update -qq && apt-get install -y -qq curl >/dev/null &&
    curl -sSL 'https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_arm64/session-manager-plugin.deb' -o /tmp/smp.deb &&
    dpkg -i /tmp/smp.deb >/dev/null &&
    ln -sf /usr/local/sessionmanagerplugin/bin/session-manager-plugin /usr/local/bin/session-manager-plugin &&
    pip install --quiet ansible boto3 botocore &&
    ansible-galaxy collection install amazon.aws &&
    ansible-playbook -i inventory.aws_ec2.yml jenkins.yml
  "
```

Mount the whole `infrastructure/jenkins` directory (not just `ansible/`) so the container can resolve the relative path to `terraform/generated/jenkins-agent.pem` referenced by `group_vars/all/terraform.yml`. Use `ubuntu_64bit` instead of `ubuntu_arm64` in the plugin URL if running on an Intel/AMD64 Docker host.

The playbook:

- Installs Amazon Corretto 21, Docker, Git, and fontconfig.
- Downloads the official Jenkins stable repository file and signing key, then installs Jenkins.
- Starts Docker and adds the `jenkins` user to the Docker group.
- Downloads the [Jenkins Plugin Installation Manager Tool](https://github.com/jenkinsci/plugin-installation-manager-tool) and installs the required plugins non-interactively: `configuration-as-code`, `ec2`, `docker-plugin`, `docker-workflow`, `ssh-credentials`, `ssh-slaves`, `credentials-binding`, `matrix-auth`.
- Renders and deploys `templates/jenkins.casc.yaml.j2` to `/var/lib/jenkins/casc_configs/jenkins.yaml`, defining:
  - A local security realm with a single `admin`/`admin` user and full `Overall/Administer` rights.
  - An **Amazon EC2** cloud (`streamingapp-ec2-agents`) with two agent templates — `t3.small` and `c7i-flex.large` — each installing Docker + Java on first boot via `initScript`.
  - `minimumNumberOfSpareInstances: 1` on the `t3.small` template keeps one agent warm/idle at all times; `instanceCapStr` caps the cloud at `jenkins_agent_max_total_instances` (default `3`) total concurrent agents across both templates; idle agents terminate after 30 minutes of inactivity.
  - An SSH private-key credential (`jenkins-agent-ssh-key`) built from the Terraform-generated key pair, used by the EC2 plugin to connect to agents it launches.
- Configures a systemd drop-in (`/etc/systemd/system/jenkins.service.d/override.conf`) that disables the setup wizard (`-Djenkins.install.runSetupWizard=false`) and points Jenkins at the JCasC file (`-Dcasc.jenkins.config=...`), and pre-seeds the upgrade-wizard state files so Jenkins never shows the "create first admin user" flow.
- Restarts Jenkins with the new configuration applied.

Because JCasC re-applies the whole configuration file on every restart, **re-running the playbook is safe and idempotent** — it always converges Jenkins back to the state described in `templates/jenkins.casc.yaml.j2`, regardless of any manual changes made through the UI in between.

Open the URL from `terraform output -raw jenkins_url` and log in with `admin` / `admin`. Configure GitHub and other job-specific credentials in Jenkins (Manage Jenkins → Credentials) rather than adding them to repository files; do not commit real secrets into `templates/jenkins.casc.yaml.j2`.

### EC2 cloud agents

Manage Jenkins → Clouds → `streamingapp-ec2-agents` shows the AWS EC2 cloud. Jobs are dispatched to agents by matching a label:

- `ec2-agent t3-small` — general-purpose build agent, kept warm (min 1 idle instance). Free Tier-eligible sizes only ('t3.small', 't3.micro', 't4g.small', 't4g.micro', 'c7i-flex.large', 'm7i-flex.large') are permitted in this AWS account — verify with `aws ec2 describe-instance-types --filters Name=free-tier-eligible,Values=true` before changing instance types.
- `ec2-agent c7i-flex-large` — larger, compute-oriented agent, launched only on demand (0 idle instances).

Jenkins launches additional agents (up to the shared cap of `jenkins_agent_max_total_instances`) automatically when the build queue has jobs waiting and no idle agent matches the required label; agents that idle for 30 minutes are terminated automatically to control cost.

## SSM shell access


No SSH access is configured. Open an interactive shell with Session Manager:

```bash
cd ../terraform
aws ssm start-session --target "$(terraform output -raw instance_id)"
```

## Validation

Run these checks before applying changes:

```bash
cd infrastructure/jenkins/terraform
terraform fmt -check -recursive
terraform init -backend=false
terraform validate

cd ../ansible
ansible-playbook --syntax-check -i localhost, jenkins.yml
```

The dynamic inventory performs an AWS API lookup when the playbook runs, so valid AWS credentials and an online tagged instance are required for a full Ansible execution.

## Cleanup

Destroy the resources when they are no longer required to prevent AWS charges:

```bash
cd ../terraform
terraform destroy
```

This also terminates any running EC2 build agents' supporting resources (key pair, security group, IAM role/profile) but **not the agent instances themselves** if Jenkins currently has any running — stop or let the EC2 plugin terminate active agents first, or terminate them manually from the EC2 console. The generated `terraform/generated/jenkins-agent.pem` file is left on disk after `destroy`; delete it manually if you want a completely clean workspace.

The S3 transfer bucket is not managed by this Terraform configuration. Remove it separately only after confirming that it is no longer used.
