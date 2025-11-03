aws_region       = "us-east-1"
instance_types_map = {
  dev  = "t2.micro"
  prod = "t3.small"
}
allowed_ssh_cidr = "186.10.139.14/32"
environment = "dev"