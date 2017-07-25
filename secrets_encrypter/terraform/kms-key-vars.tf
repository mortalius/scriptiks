variable "kms_key_alias" {
  default = "alias/kms-key"
}
variable "root_account_arn" {
  default = "arn:aws:iam::123456789012:root"
}                          
variable "key_admin_arns" {
  type = "list"
  default = [
              "arn:aws:iam::123456789012:user/mortalius"
            ]
}
variable "power_user_arns" {
  type = "list"
  default = [
              "arn:aws:iam::123456789012:user/mortalius"
            ] 
}
variable "decrypt_only_arns" {
  type = "list"
  default = [
              "arn:aws:iam::123456789012:role/some_decrypt_only_role"
            ]
}
