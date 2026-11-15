# test environment. Secrets/IDs (subscription_id, sql_server_name, sql_admin_password) are NOT here:
# they are passed as TF_VAR_* environment variables (see README.md).
environment          = "test"
enable_custom_domain = true

# Environment-specific Application Settings merged on top of the defaults in main.tf.
app_settings = {
  LOG_LEVEL         = "INFO"
  FEATURE_FLAG_DEMO = "false"
}
