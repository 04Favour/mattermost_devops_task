resource "aws_route_table" "mattermost_rt" {
    vpc_id = aws_vpc.mattermost_vpc.id
    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_internet_gateway.igw.id
    }

    tags = {Name = "mattermost-public-rt"}
}


resource "aws_route_table_association" "a" {
    subnet_id = aws_subnet.public_subnet_a.id
    route_table_id = aws_route_table.mattermost_rt.id
}

resource "aws_route_table_association" "b" {
    subnet_id = aws_subnet.public_subnet_b.id
    route_table_id = aws_route_table.mattermost_rt.id
}