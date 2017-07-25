resource "aws_kms_key" "kms_key" {
  description   = "KMS key for properties files"
  policy        = "${data.aws_iam_policy_document.kms_key_policy.json}"
  tags {
    cost = "test"
  }
}
resource "aws_kms_alias" "kms_key_alias" {
  name          = "${var.kms_key_alias}"
  target_key_id = "${aws_kms_key.kms_key.key_id}"
}


resource "aws_iam_instance_profile" "decrypt_role" {
  name  = "decrypt_role"
  role = "${aws_iam_role.decrypt_role.name}"
}
resource "aws_iam_role" "decrypt_role" {
  name               = "decrypt_role"
  assume_role_policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": "sts:AssumeRole",
            "Principal": {
               "Service": "ec2.amazonaws.com"
            },
            "Effect": "Allow",
            "Sid": ""
        }
    ]
}
EOF
}

data "aws_iam_policy_document" "kms_key_policy" {
  statement {
    sid = "Enable IAM User Permissions"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = [ "${var.root_account_arn}" ]
    }
    actions = [ "kms:*" ]
    resources = [ "*" ]
  }

  statement {
    sid = "Allow access for Key Administrators"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = "${var.key_admin_arns}"
    }
    actions = [ "kms:Create*",
                "kms:Describe*",
                "kms:Enable*",
                "kms:List*",
                "kms:Put*",
                "kms:Update*",
                "kms:Revoke*",
                "kms:Disable*",
                "kms:Get*",
                "kms:Delete*",
                "kms:TagResource",
                "kms:UntagResource",
                "kms:ScheduleKeyDeletion",
                "kms:CancelKeyDeletion" 
              ]
    resources = [ "*" ]
  }

  statement {
    sid = "Allow encrypt/decrypt with key for power users"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = "${var.power_user_arns}"
    }
    actions = [ "kms:Encrypt",
                "kms:Decrypt",
                "kms:ReEncrypt*",
                "kms:GenerateDataKey*",
                "kms:DescribeKey"]
    resources = [ "*" ]
  }

  statement {
    sid = "Allow decrypt only with key for automated deploy"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = "${var.decrypt_only_arns}"
    }
    actions = [ "kms:Decrypt",
                "kms:DescribeKey",
              ]
    resources = [ "*" ]
  }

  statement {
    sid = "Allow attachment of persistent resources"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = "${concat(var.decrypt_only_arns, var.power_user_arns, var.key_admin_arns)}"
    }
    actions = [ "kms:CreateGrant",
                "kms:ListGrants",
                "kms:RevokeGrant"
              ]
    resources = [ "*" ]    
    condition {
      test     = "Bool"
      variable = "kms:GrantIsForAWSResource"
      values = [ "true" ]
    }
  }
}