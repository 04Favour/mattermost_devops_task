resource "aws_subnet" "public_subnet_a" {
    vpc_id = aws_vpc.mattermost_vpc.id
    cidr_block = "10.0.1.0/24"
    map_public_ip_on_launch = true
    availability_zone = "us-east-1a"
    tags = {
        Name = "mattermost-public-subnet-a"
        "kubernetes.io/role/elb" = "1"
        "kubernetes.io/cluster/mattermost-cluster" = "shared"
        }
}

resource "aws_subnet" "public_subnet_b" {
    vpc_id = aws_vpc.mattermost_vpc.id
    cidr_block = "10.0.2.0/24"
    map_public_ip_on_launch = true
    availability_zone = "us-east-1b"
    tags = {
      Name = "mattermost-public-subnet-b"
      "kubernetes.io/role/elb" = "1"
      "kubernetes.io/cluster/mattermost-cluster" = "shared"
    }
}