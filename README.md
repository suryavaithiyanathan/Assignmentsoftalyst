Overview of this repo : 
This project deploys a highly available, scalable, and secure web application infrastructure on AWS using Terraform.
It includes a VPC, subnets, EC2 Auto Scaling, an internet-facing ALB, RDS for database backend, and NAT gateways for secure private subnet access.

AWS services to create :
- A custom VPC with public and private subnets across 2 Availability Zones
- Internet Gateway and NAT Gateways for routing
- Auto Scaling Group of EC2 instances (web servers) in private subnets
- Application Load Balancer (ALB)
- PostgreSQL RDS instance in private subnets (Multi-AZ)
- Properly scoped security groups for ALB, EC2, and RDS
- IAM role for EC2 with Systems Manager (SSM) access
- User data script that installs Ngnix and serves "Hello World" on port 80

Structure of the project : 
Assignmentsoftalyst
├── main.tf
├── variables.tf
├── output.tf
├── provider.tf
└── README.md
