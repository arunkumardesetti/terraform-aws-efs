provider "aws" {
  region = "ap-south-1"
  profile = "default"
}

#Creating Security Group
resource "aws_security_group" "http_sg" {
  name        = "http_sg"
ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
tags = {
    Name = "http_sg"
  }
}

# create efs
resource "aws_efs_file_system" "tfefs" {
 creation_token = "tfefs"
 tags = {
 Name = "tfefs"
 }
}

# mount efs
resource "aws_efs_mount_target" "mountefs" {
 depends_on = [
 aws_efs_file_system.tfefs
 ]
 file_system_id = aws_efs_file_system.tfefs.id
 subnet_id      = aws_instance.web.subnet_id
 security_groups = ["${aws_security_group.http_sg.id}"]
}
# access point efs
resource "aws_efs_access_point" "efs_access" {
 depends_on = [
 aws_efs_file_system.tfefs,
 ]
 file_system_id = aws_efs_file_system.tfefs.id
}

#Launching Instance
resource "aws_instance" "web" {
  depends_on = [
  aws_efs_file_system.tfefs
  ]
  ami           = "ami-0447a12f28fddb066"
  instance_type = "t2.micro"
  key_name 	=  "arunawskey"
  security_groups = [ "http_sg" ]

   connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = file("C:/Users/KIIT/Downloads/arunawskey.pem")
    host     = aws_instance.web.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      "sudo su <<END",
      "yum install git php httpd amazon-efs-utils -y",
      "rm -rf /var/www/html/*",
      "/usr/sbin/httpd",
      "efs_id=${aws_efs_file_system.tfefs.id}",
      "mount -t efs $efs_id:/ /var/www/html",
      "git clone https://github.com/notarunkumar/terraform-aws-efs.git /var/www/html/",
      "END",
    ]
  }
  
  tags = {
    Name = "TaskOS"
  }
}

# Saving IP of the instance in a file
output "instance_ip" {
	value = aws_instance.web.public_ip
}
resource "null_resource" "nulllocal"  {
	provisioner "local-exec" {
	    command = "echo  ${aws_instance.web.public_ip} > publicip.txt"
  	}
}

#Download Github Repository
resource "null_resource" "nulllocal2"  {
  provisioner "local-exec" {
      command = "git clone https://github.com/notarunkumar/terraform-aws-efs.git ./gitcode"
    }
}  

#Creating S3 Bucket
resource "aws_s3_bucket" "corruptgenius" {
  bucket = "corruptbucket"
  acl    = "public-read"
  tags = {
      Name = "corruptgenius"
  }
}

output "bucket" {
  value = aws_s3_bucket.corruptgenius
}

resource "aws_s3_bucket_object" "bucket_obj" {
  bucket = "${aws_s3_bucket.corruptgenius.id}"
  key    = "Arun.jpg"
  source = "./gitcode/Arun.jpg"
  acl	 = "public-read"
}

#Creating CloudFront
resource "aws_cloudfront_distribution" "cfd" {
  origin {
    domain_name = "${aws_s3_bucket.corruptgenius.bucket_regional_domain_name}"
    origin_id   = "${aws_s3_bucket.corruptgenius.id}"
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "S3 Web Distribution"

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "${aws_s3_bucket.corruptgenius.id}"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }
    
    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  restrictions {
    geo_restriction {
      restriction_type = "whitelist"
      locations        = ["IN"]
    }
  }

  tags = {
    Name        = "Web-CF-Distribution"
    Environment = "Production"
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  depends_on = [
    aws_s3_bucket.corruptgenius
  ]
}