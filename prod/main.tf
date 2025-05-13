# ################################################################################
# # VPC Module
# ################################################################################

module "vpc" {
  source      = "./../modules/vpc"
  main-region = var.main-region
}

# ################################################################################
# # EKS Cluster Module
# ################################################################################

module "eks" {
  source             = "./../modules/eks-cluster"
  cluster_name       = var.cluster_name
  rolearn            = var.rolearn
  security_group_ids = [module.eks-client-node.eks_client_sg]
  vpc_id             = module.vpc.vpc_id
  private_subnets    = module.vpc.private_subnets
}

# ################################################################################
# # AWS ALB Controller
# ################################################################################

module "aws_alb_controller" {
  source = "./../modules/aws-alb-controller"

  main-region  = var.main-region
  env_name     = var.env_name
  cluster_name = var.cluster_name

  vpc_id            = module.vpc.vpc_id
  oidc_provider_arn = module.eks.oidc_provider_arn
}


module "eks-client-node" {
  source                 = "./../modules/eks-client-node"
  ami_id                 = local.final_ami_id
  instance_type          = var.instance_type
  aws_region             = var.main-region
  subnet_id              = module.vpc.public_subnets[0]
  vpc_id                 = module.vpc.vpc_id
  vpc_security_group_ids = [module.eks-client-node.eks_client_sg]
  cluster_name           = module.eks.cluster_name
  tags = {
    Name = "eks_client_node"
  }
  key_name = module.eks-client-node.eks_client_private_key
  user_data = base64encode(<<-EOF
    #!/bin/bash
set -euo pipefail

echo "Updating packages and installing prerequisites..."
sudo apt-get update -y
sudo apt-get install -y unzip gnupg software-properties-common curl lsb-release wget apt-transport-https ca-certificates

echo "Installing AWS CLI..."
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip -q awscliv2.zip
sudo ./aws/install
rm -rf awscliv2.zip aws

echo "Installing Terraform..."
wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg > /dev/null
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
    sudo tee /etc/apt/sources.list.d/hashicorp.list > /dev/null
sudo apt-get update -y
sudo apt-get install -y terraform

echo "Installing kubectl for Amazon EKS..."
KUBECTL_VERSION="1.31.3"
KUBECTL_DATE="2024-12-12"
ARCH="amd64"
curl -LO "https://s3.us-west-2.amazonaws.com/amazon-eks/${KUBECTL_VERSION}/${KUBECTL_DATE}/bin/linux/${ARCH}/kubectl"
chmod +x kubectl
mkdir -p "$HOME/bin"
mv kubectl "$HOME/bin/kubectl"

# Add $HOME/bin to PATH if not already there
if [[ ":$PATH:" != *":$HOME/bin:"* ]]; then
    echo 'export PATH="$HOME/bin:$PATH"' >> "$HOME/.bashrc"
    export PATH="$HOME/bin:$PATH"
fi

echo "Installing Amazon SSM Agent..."
if snap list | grep -q amazon-ssm-agent; then
    echo "Amazon SSM Agent is already installed."
else
    sudo snap install amazon-ssm-agent --classic
    sudo systemctl enable snap.amazon-ssm-agent.amazon-ssm-agent.service
    sudo systemctl start snap.amazon-ssm-agent.amazon-ssm-agent.service
fi

echo "Installing Docker..."
sudo apt-get remove -y docker docker-engine docker.io containerd runc || true
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] \
  https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update -y
sudo apt-get install -y docker-ce docker-ce-cli containerd.io
sudo systemctl enable docker
sudo systemctl start docker
sudo usermod -aG docker "$USER"

echo
echo "✅ Installation of AWS CLI, Terraform, kubectl, Amazon SSM Agent, and Docker is complete."
echo "⚠️  You may need to log out and log back in or run 'newgrp docker' for Docker group changes to take effect."




module "acm" {
  source          = "./../modules/acm"
  domain_name     = var.domain_name
  san_domains     = var.san_domains
  route53_zone_id = var.route53_zone_id
  tags            = local.common_tags
}


module "ecr" {
  source         = "./../modules/ecr"
  aws_account_id = var.aws_account_id
  repositories   = var.repositories
  tags           = local.common_tags
}


module "iam" {
  source      = "./../modules/iam"
  environment = var.env_name
  tags        = local.common_tags
}


##############################################
# EKS TOOLS
##############################################
module "jenkins-server" {
  source            = "./../modules/jenkins-server"
  ami_id            = local.final_ami_id
  instance_type     = var.instance_type
  key_name          = var.key_name
  main-region       = var.main-region
  security_group_id = module.eks-client-node.eks_client_sg
  subnet_id         = module.vpc.public_subnets[0]
}


module "terraform-node" {
  source            = "./../modules/terraform-node"
  ami_id            = local.final_ami_id
  instance_type     = var.instance_type
  key_name          = var.key_name
  main-region       = var.main-region
  security_group_id = module.eks-client-node.eks_client_sg
  subnet_id         = module.vpc.public_subnets[0]
}

module "maven-sonarqube-server" {
  source            = "./../modules/maven-sonarqube-server"
  ami_id            = local.final_ami_id
  instance_type     = var.instance_type
  key_name          = var.key_name
  security_group_id = module.eks-client-node.eks_client_sg
  subnet_id         = module.vpc.public_subnets[0]
  # main-region   = var.main-region

  #   db_name              = var.db_name
  #   db_username          = var.db_username
  #   db_password          = var.db_password
  #   db_subnet_group      = var.db_subnet_group
  #   db_security_group_id = var.db_security_group_id
}





# ################################################################################
# # Managed Grafana Module
# ################################################################################

# module "managed_grafana" {
#   source             = "./modules/grafana"
#   env_name           = var.env_name
#   main-region        = var.main-region
#   private_subnets    = module.vpc.private_subnets
#   sso_admin_group_id = var.sso_admin_group_id
# }



# # ################################################################################
# # # Managed Prometheus Module
# # ################################################################################

# module "prometheus" {
#   source            = "./modules/prometheus"
#   env_name          = var.env_name
#   main-region       = var.main-region
#   cluster_name      = var.cluster_name
#   oidc_provider_arn = module.eks.oidc_provider_arn
#   vpc_id            = module.vpc.vpc_id
#   private_subnets   = module.vpc.private_subnets
# }



# # ################################################################################
# # # VPC Endpoints for Prometheus and Grafana Module
# # ################################################################################

# module "vpcendpoints" {
#   source                    = "./modules/vpcendpoints"
#   env_name                  = var.env_name
#   main-region               = var.main-region
#   vpc_id                    = module.vpc.vpc_id
#   private_subnets           = module.vpc.private_subnets
#   grafana_security_group_id = module.managed_grafana.security_group_id
# }


