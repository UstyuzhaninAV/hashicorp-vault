disable_cache = true
disable_mlock = true

ui = true

listener "tcp" {
    address = "0.0.0.0:8200"
    tls_disable = "1"
}

storage "s3" {
    access_key = "****"
    secret_key = "****"
    bucket     = "secrets-vault"
    kms_key_id = "****"
    region     = "eu-west-1"
}
entropy "seal" {
    mode = "augmentation"
}
