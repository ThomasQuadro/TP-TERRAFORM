# TP Terraform – Déploiement d'une infrastructure auto-scalable sur AWS

**Auteur :** Thomas Quadro  
**Master :** InfraCloud Aix 

---

## 📁 Structure du projet

```bash
tp-terraform-TQO/
├── provider.tf         # Provider AWS
├── variables.tf        # Variables du projet
├── outputs.tf          # Valeur(s) affichée(s) à la fin
├── main.tf             # Infrastructure principale
└── install_web.sh      # Script de configuration des instances
```

---

## ⚙️ Étapes d'installation
Création et confguration des fichiers de Terraform et des identifiants AWS.

```bash
mkdir tp-terraform-web && cd tp-terraform-web
touch provider.tf variables.tf outputs.tf main.tf install_web.sh
chmod +x install_web.sh
aws configure
```

---

## 📄 Fichier : `provider.tf`
Ce bloc configure Terraform pour utiliser AWS comme provider, dans la région `us-east-1`.

```hcl
provider "aws" {
  region = "us-east-1"
}
```


---

## 📄 Fichier : `variables.tf`
Déclaration des variables de configuration de base pour nos ressources AWS (région, AMI, type d'instance, clé SSH).

```hcl
variable "region"        { default = "us-east-1" }
variable "ami_id"        { default = "ami-000ec6c25978d5999" }
variable "instance_type" { default = "t2.micro" }
variable "key_name"      { default = "vockey" }
```


---

## 📄 Fichier : `install_web.sh`
Ce script shell est exécuté automatiquement par chaque instance EC2 au démarrage. Il installe le serveur Apache et crée une page d'accueil contenant le nom d'hôte de l'instance.

```bash
#!/bin/bash
sudo yum update -y
sudo yum install -y httpd
sudo systemctl start httpd
sudo systemctl enable httpd
echo "Bonjour depuis $(hostname -f)" | sudo tee /var/www/html/index.html
```


---

## 📄 Fichier : `main.tf`

### 🧱 Création d'un VPC personnalisé
Ce VPC est le réseau principal qui hébergera tous les composants (subnets, instances, etc).

```hcl
resource "aws_vpc" "TQO-main" {
  cidr_block = "10.0.0.0/16"
}
```

### 🌐 Deux sous-réseaux publics dans deux AZ différentes
Chaque sous-réseau est placé dans une zone de disponibilité différente pour garantir la haute disponibilité.

```hcl
resource "aws_subnet" "TQO-subnet1" {
  vpc_id            = aws_vpc.TQO-main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"
}

resource "aws_subnet" "TQO-subnet2" {
  vpc_id            = aws_vpc.TQO-main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1b"
}
```

### 🌍 Internet Gateway
Permet aux instances dans le VPC d’accéder à Internet.

```hcl
resource "aws_internet_gateway" "TQO-igw" {
  vpc_id = aws_vpc.TQO-main.id
}
```

### 🚦 Table de routage
Redirige le trafic sortant vers l’Internet Gateway.

```hcl
resource "aws_route_table" "TQO-rt" {
  vpc_id = aws_vpc.TQO-main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.TQO-igw.id
  }
}
```

### 🔗 Association de la table de routage aux subnets
Associe la table de routage publique aux deux subnets créés précédemment.

```hcl
resource "aws_route_table_association" "TQO-a1" {
  subnet_id      = aws_subnet.TQO-subnet1.id
  route_table_id = aws_route_table.TQO-rt.id
}

resource "aws_route_table_association" "TQO-a2" {
  subnet_id      = aws_subnet.TQO-subnet2.id
  route_table_id = aws_route_table.TQO-rt.id
}
```

### 🔐 Groupe de sécurité
Contrôle les flux réseau : ici, on autorise le trafic SSH (22) et HTTP (80).

```hcl
resource "aws_security_group" "TQO-web_sg" {
  name   = "TQO-web-sg"
  vpc_id = aws_vpc.TQO-main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
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
```

### ⚖️ Load Balancer (ALB)
Routage du trafic HTTP vers les instances EC2 via un Load Balancer public.

```hcl
resource "aws_lb" "TQO-web_lb" {
  name               = "TQO-web-lb"
  internal           = false
  load_balancer_type = "application"
  subnets            = [aws_subnet.TQO-subnet1.id, aws_subnet.TQO-subnet2.id]
  security_groups    = [aws_security_group.TQO-web_sg.id]
}
```

### 🎯 Target Group
Regroupe les instances qui recevront le trafic du Load Balancer.

```hcl
resource "aws_lb_target_group" "TQO-web_tg" {
  name     = "TQO-web-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.TQO-main.id
}
```

### 🎧 Listener HTTP
Écoute le trafic HTTP (port 80) sur le Load Balancer et le redirige vers le target group.

```hcl
resource "aws_lb_listener" "TQO-web_listener" {
  load_balancer_arn = aws_lb.TQO-web_lb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.TQO-web_tg.arn
  }
}
```

### 🧩 Launch Template
Modèle de lancement utilisé par l’ASG pour créer des instances EC2 avec Apache préinstallé.

```hcl
resource "aws_launch_template" "TQO-lt" {
  name_prefix   = "TQO-lt-"
  image_id      = var.ami_id
  instance_type = var.instance_type
  key_name      = var.key_name
  vpc_security_group_ids = [aws_security_group.TQO-web_sg.id]

  user_data = <<-EOL
    #!/bin/bash
    sudo yum update -y
    sudo yum install -y httpd
    sudo systemctl start httpd
    sudo systemctl enable httpd
    echo "Bonjour depuis $(hostname -f)" | sudo tee /var/www/html/index.html
  EOL

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "TQO-ASG-Instance-\${aws:instance-id}"
    }
  }
}
```

### 📈 Auto Scaling Group
Groupe de scaling automatique avec un minimum de 2 instances.

```hcl
resource "aws_autoscaling_group" "TQO-asg" {
  name                = "TQO-asg"
  desired_capacity    = 2
  max_size            = 3
  min_size            = 1
  vpc_zone_identifier = [aws_subnet.TQO-subnet1.id, aws_subnet.TQO-subnet2.id]

  launch_template {
    id      = aws_launch_template.TQO-lt.id
    version = "$Latest"
  }

  target_group_arns = [aws_lb_target_group.TQO-web_tg.arn]

  tag {
    key                 = "Name"
    value               = "TQO-ASG-Instance-\${aws:instance-id}"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}
```


---

## 📄 Fichier : `outputs.tf`
Affiche l’URL publique du Load Balancer à la fin de l’exécution.

```hcl
output "TQO-load_balancer_dns" {
  value = aws_lb.TQO-web_lb.dns_name
}
```


---

## 🚀 Commandes à exécuter

```bash
terraform init
terraform validate
terraform plan
terraform apply
```

---

## ✅ Résultat attendu

- Terraform affiche l'URL du Load Balancer (`TQO-load_balancer_dns`)
- En accédant à cette URL, tu vois une page avec le message :
  ```
  Bonjour depuis ip-...
  ```

---

## 🧹 Nettoyage

```bash
terraform destroy
```
