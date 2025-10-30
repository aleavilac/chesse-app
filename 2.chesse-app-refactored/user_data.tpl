#!/bin/bash
set -e
yum update -y
amazon-linux-extras install docker -y || yum install -y docker
systemctl enable docker
systemctl start docker
usermod -aG docker ec2-user

# Valor inyectado por Terraform:
IMAGE_REPO="${CHEESE_IMAGE}"

(docker rm -f cheese || true) >/dev/null 2>&1
docker run -d --restart=always --name cheese -p 80:80 "$IMAGE_REPO"