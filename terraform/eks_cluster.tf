resource "aws_eks_cluster" "eks_cluster" {
    name = "mattermost-cluster"
    role_arn = aws_iam_role.cluster_role.arn
    version = "1.31"

    vpc_config {
      subnet_ids = [
        aws_subnet.public_subnet_a.id,
        aws_subnet.public_subnet_b.id
      ]
      endpoint_public_access = true
    }

    depends_on = [ 
        aws_iam_role_policy_attachment.cluster_AmazonEKSClusterPolicy
     ]

     tags = { Name= "mattermost-cluster" }

}