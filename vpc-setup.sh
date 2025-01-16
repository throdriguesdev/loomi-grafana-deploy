#!/bin/bash

# Configurar região
aws configure set region us-east-2

# Criar a VPC
VPC_ID=$(aws ec2 create-vpc \
    --cidr-block 10.0.0.0/16 \
    --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=loomi-vpc}]' \
    --query 'Vpc.VpcId' \
    --output text)

echo "VPC ID: $VPC_ID"

# Habilitar hostnames DNS para a VPC
aws ec2 modify-vpc-attribute \
    --vpc-id $VPC_ID \
    --enable-dns-hostnames "{\"Value\":true}"

# Criar Internet Gateway
IGW_ID=$(aws ec2 create-internet-gateway \
    --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=loomi-igw}]' \
    --query 'InternetGateway.InternetGatewayId' \
    --output text)

echo "Internet Gateway ID: $IGW_ID"

# Anexar Internet Gateway à VPC
aws ec2 attach-internet-gateway \
    --vpc-id $VPC_ID \
    --internet-gateway-id $IGW_ID

# Criar Subnet Pública
PUBLIC_SUBNET_ID=$(aws ec2 create-subnet \
    --vpc-id $VPC_ID \
    --cidr-block 10.0.1.0/24 \
    --availability-zone us-west-1a \
    --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=loomi-subnet-public}]' \
    --query 'Subnet.SubnetId' \
    --output text)

echo "Public Subnet ID: $PUBLIC_SUBNET_ID"

# Habilitar auto-assign IP público na subnet pública
aws ec2 modify-subnet-attribute \
    --subnet-id $PUBLIC_SUBNET_ID \
    --map-public-ip-on-launch

# Criar Subnet Privada
PRIVATE_SUBNET_ID=$(aws ec2 create-subnet \
    --vpc-id $VPC_ID \
    --cidr-block 10.0.2.0/24 \
    --availability-zone us-west-1b \
    --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=loomi-subnet-private}]' \
    --query 'Subnet.SubnetId' \
    --output text)

echo "Private Subnet ID: $PRIVATE_SUBNET_ID"

# Criar Route Table pública
PUBLIC_RTB_ID=$(aws ec2 create-route-table \
    --vpc-id $VPC_ID \
    --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=loomi-rtb-public}]' \
    --query 'RouteTable.RouteTableId' \
    --output text)

echo "Public Route Table ID: $PUBLIC_RTB_ID"

# Adicionar rota para Internet Gateway na Route Table pública
aws ec2 create-route \
    --route-table-id $PUBLIC_RTB_ID \
    --destination-cidr-block 0.0.0.0/0 \
    --gateway-id $IGW_ID

# Associar Route Table pública com a Subnet pública
aws ec2 associate-route-table \
    --subnet-id $PUBLIC_SUBNET_ID \
    --route-table-id $PUBLIC_RTB_ID

# Criar Security Group
SG_ID=$(aws ec2 create-security-group \
    --group-name loomi-sg \
    --description "Loomi Security Group for VPC" \
    --vpc-id $VPC_ID \
    --query 'GroupId' \
    --output text)

echo "Security Group ID: $SG_ID"

# Adicionar tag ao Security Group
aws ec2 create-tags \
    --resources $SG_ID \
    --tags "Key=Name,Value=loomi-sg"

# Adicionar regras ao Security Group
aws ec2 authorize-security-group-ingress \
    --group-id $SG_ID \
    --protocol tcp \
    --port 22 \
    --cidr 0.0.0.0/0

aws ec2 authorize-security-group-ingress \
    --group-id $SG_ID \
    --protocol tcp \
    --port 80 \
    --cidr 0.0.0.0/0

aws ec2 authorize-security-group-ingress \
    --group-id $SG_ID \
    --protocol tcp \
    --port 443 \
    --cidr 0.0.0.0/0

# Salvar IDs em um arquivo para referência
echo "# Loomi AWS Resources - us-west-1" > loomi_aws_resources.txt
echo "VPC_ID=$VPC_ID" >> loomi_aws_resources.txt
echo "IGW_ID=$IGW_ID" >> loomi_aws_resources.txt
echo "PUBLIC_SUBNET_ID=$PUBLIC_SUBNET_ID" >> loomi_aws_resources.txt
echo "PRIVATE_SUBNET_ID=$PRIVATE_SUBNET_ID" >> loomi_aws_resources.txt
echo "PUBLIC_RTB_ID=$PUBLIC_RTB_ID" >> loomi_aws_resources.txt
echo "SG_ID=$SG_ID" >> loomi_aws_resources.txt

echo "Infraestrutura Loomi criada com sucesso! Os IDs foram salvos em loomi_aws_resources.txt"

aws ec2 run-instances \
  --image-id ami-02576955a77abf0e6 \
  --instance-type t2.micro \
  --key-name thiago-key \
  --subnet-id $PUBLIC_SUBNET_ID \
  --security-group-ids $SG_ID \
  --block-device-mappings "[{\"DeviceName\":\"/dev/xvda\",\"Ebs\":{\"VolumeSize\":8,\"VolumeType\":\"gp2\"}}]" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=loomi-ec2}]" \
  --count 1
