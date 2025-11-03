data "external" "reg_password_hash" {
  # the salt is only provided to guarantee idempotency
  program = ["./utils/hash-password.py", var.vm_regular_password, var.vm_regular_pass_salt]
}
