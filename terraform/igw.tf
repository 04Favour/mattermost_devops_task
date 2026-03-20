resource "aws_internet_gateway" "igw"{
    vpc_id = aws_vpc.mattermost_vpc.id
    tags = {Name = "mattermost-igw"}
}