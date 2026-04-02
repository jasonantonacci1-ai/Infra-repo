#AWS infrastructure --------------------------------------------------

provider "aws" {
  region = "us-east-1"
}

resource "aws_eip" "nat_eip" {
  domain = "vpc"
}

resource "aws_vpc" "main_vpc" {
  cidr_block = "10.0.0.0/16"
  
  tags = {
    Name = "DevOps-Project-VPC"
  }
}

#Key-pairs --------------------------------------------------
                # private key
resource "tls_private_key" "main_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

                # 2.public key for AWS
resource "aws_key_pair" "deployer_key" {
  key_name   = "devops-project-key"
  public_key = tls_private_key.main_key.public_key_openssh
}

                # 3.local file 
resource "local_file" "ssh_key" {
  content  = tls_private_key.main_key.private_key_pem
  filename = "${path.module}/devops-project-key.pem"

provisioner "local-exec" {
    command = "chmod 400 ${path.module}/devops-project-key.pem"
	}
}
# Local File stuff --------------------------------------------------
        #grabs IP's
resource "local_file" "ansible_inventory" {
  content = <<-EOT
    [jenkins]
    ${aws_instance.jenkins.private_ip}

    [sonarqube]
    ${aws_instance.sonarqube.private_ip}
  EOT
  filename = "${path.module}/ansible/inventory"
}
         #tunnels
resource "local_file" "sonarqube_tunnel" {
  content = <<-EOT
    ssh -i "${path.module}/devops-project-key.pem" -L 9000:${aws_instance.sonarqube.private_ip}:9000 ubuntu@${aws_instance.bastion.public_ip}
  EOT
  filename = "${path.module}/ansible/connect-sonarqube.sh"
  
  provisioner "local-exec" {
    command = "chmod +x ${path.module}/ansible/connect-sonarqube.sh"
  }
}
         #keys .pem files
resource "local_file" "jenkins_tunnel" {
  content = <<-EOT
    ssh -i "${path.module}/devops-project-key.pem" -L 8080:${aws_instance.jenkins.private_ip}:8080 ubuntu@${aws_instance.bastion.public_ip}
  EOT
  filename = "${path.module}/ansible/connect-jenkins.sh"
  
    provisioner "local-exec" {
    command = "chmod +x ${path.module}/ansible/connect-jenkins.sh"
  }
}
#password generation ---------------------------------------------------------
         #ansible password generation (jenkins)
resource "random_password" "jenkins_pass" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}
          #ansible password generation (sonarqube)
resource "random_password" "sonarqube_pass" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}
          #places password into secret file
resource "local_file" "ansible_secrets" {
  filename = "${path.module}/ansible/secrets.yml"
  content  = "sonarqube_admin_password: \"${random_password.sonarqube_pass.result}\"\njenkins_admin_password: \"${random_password.jenkins_pass.result}\""
}

resource "null_resource" "encrypt_secrets" {
  depends_on = [local_file.ansible_secrets]
  provisioner "local-exec" {
    command = "echo '${random_password.sonarqube_pass.result}' > vault_pass.txt && ansible-vault encrypt ansible/secrets.yml --vault-password-file vault_pass.txt"
  }
}
#Subnet ID's / tags --------------------------------------------------

resource "aws_subnet" "public_subnet_1" {
  vpc_id     = aws_vpc.main_vpc.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "us-east-1b"
  map_public_ip_on_launch = true
  
  tags = {
    Name = "Public-Subnet-1"
  }
}

resource "aws_subnet" "public_subnet_2" {
  vpc_id     = aws_vpc.main_vpc.id
  cidr_block = "10.0.2.0/24"
  availability_zone = "us-east-1b"
  map_public_ip_on_launch = true
  
  tags = {
    Name = "Public-Subnet-2"
  }
}

resource "aws_subnet" "private_subnet_1" {
  vpc_id     = aws_vpc.main_vpc.id
  cidr_block = "10.0.3.0/24"
  availability_zone = "us-east-1b"
  
  tags = {
    Name = "Private-Subnet-1"
  }
}

resource "aws_subnet" "private_subnet_2" {
  vpc_id     = aws_vpc.main_vpc.id
  cidr_block = "10.0.4.0/24"
  availability_zone = "us-east-1b"
    
  tags = {
    Name = "Private-Subnet-2"
  }
}

# Routing / Gateways --------------------------------------------------
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main_vpc.id

  tags = {
    Name = "DevOps-Project-IGW"
  }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main_vpc.id

  route {
    cidr_block = "0.0.0.0/0" 
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "Public-Route-Table"
  }
}

	#Public

resource "aws_route_table_association" "public_rta_1" {
  subnet_id      = aws_subnet.public_subnet_1.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "public_rta_2" {
  subnet_id      = aws_subnet.public_subnet_2.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_nat_gateway" "nat_gw" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_subnet_1.id

  tags = {
    Name = "NAT-Gateway"
  }
}

	#Private

resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.main_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gw.id
  }

  tags = {
    Name = "Private-Route-Table"
  }
}

resource "aws_route_table_association" "private_rta_1" {
  subnet_id      = aws_subnet.private_subnet_1.id
  route_table_id = aws_route_table.private_rt.id
}

resource "aws_route_table_association" "private_rta_2" {
  subnet_id      = aws_subnet.private_subnet_2.id
  route_table_id = aws_route_table.private_rt.id
}

# bastion infrastructure --------------------------------------------------

resource "aws_instance" "bastion" {
  ami           = "ami-0c7217cdde317cfec" # standard Ubuntu image for us-east-1
  instance_type = "c7i-flex.large"
  subnet_id     = aws_subnet.public_subnet_1.id
  vpc_security_group_ids = [aws_security_group.bastion_sg.id]
  associate_public_ip_address = true
  key_name = aws_key_pair.deployer_key.key_name
  
  tags = {
    Name = "Bastion-Host"
  }
}

resource "aws_security_group" "bastion_sg" {
  name   = "bastion-sg"
  vpc_id = aws_vpc.main_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

#Jenkins Infrastructure --------------------------------------------------

resource "aws_instance" "jenkins" {
  ami           = "ami-0c7217cdde317cfec"
  instance_type = "c7i-flex.large" # hopefully no slow jenkins?
  subnet_id              = aws_subnet.private_subnet_1.id
  vpc_security_group_ids = [aws_security_group.jenkins_sg.id]
  key_name = aws_key_pair.deployer_key.key_name
  root_block_device {
    volume_size           = 20
    volume_type           = "gp3"
    delete_on_termination = true # This is the "nuke" switch
  }
  tags = {
    Name = "Jenkins-Server"
  }
}

resource "aws_security_group" "jenkins_sg" {
  name   = "jenkins-sg"
  vpc_id = aws_vpc.main_vpc.id

#entryway test

ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${aws_instance.bastion.private_ip}/32"]
}
  ingress {
    from_port       = 22
    to_port         = 22    #for internal to internal moves
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion_sg.id]
  }
  
  ingress {
    from_port   = 8080   # jenkins default port
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"] # Allow internal VPC traffic to see the UI
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}



#SonarQube Infrastructure --------------------------------------------------

resource "aws_instance" "sonarqube" {
  ami                    = "ami-0c7217cdde317cfec"
  instance_type          = "c7i-flex.large" 
  subnet_id              = aws_subnet.private_subnet_2.id
  vpc_security_group_ids = [aws_security_group.sonarqube_sg.id]
  key_name = aws_key_pair.deployer_key.key_name
  root_block_device {
    volume_size           = 20
    volume_type           = "gp3"
    delete_on_termination = true # This is the "nuke" switch
  }
  tags = {
    Name = "SonarQube-Server"
  }
}

resource "aws_security_group" "sonarqube_sg" {
  name   = "sonarqube-sg"
  vpc_id = aws_vpc.main_vpc.id

  # SSH access only from Bastion
  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion_sg.id]
  }

  # SonarQube UI/API access from Jenkins AND Bastion (for the tunnel)
  ingress {
    from_port       = 9000
    to_port         = 9000
    protocol        = "tcp"
    security_groups = [aws_security_group.jenkins_sg.id, aws_security_group.bastion_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
#Terraform IP instructions --------------------------------------------------

resource "local_file" "ansible_config" {
  content = <<-EOT
    [defaults]
    inventory = inventory
    host_key_checking = False
    remote_user = ubuntu
    private_key_file = ../devops-project-key.pem
    
    [ssh_connection]
    ssh_args = -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ProxyCommand="ssh -W %h:%p -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ../devops-project-key.pem ubuntu@${aws_instance.bastion.public_ip}"
  EOT
  
  filename = "${path.module}/ansible/ansible.cfg"
}
