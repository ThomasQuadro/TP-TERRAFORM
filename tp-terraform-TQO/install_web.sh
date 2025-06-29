#!/bin/bash
sudo yum update -y
sudo yum install -y httpd
sudo systemctl start httpd
sudo systemctl enable httpd
echo "Bonjour depuis $(hostname -f)" | sudo tee /var/www/html/index.html