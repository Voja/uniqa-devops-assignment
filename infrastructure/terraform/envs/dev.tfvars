# dev environment. Secrets/IDs (subscription_id, sql_server_name, sql_admin_password) are NOT here:
# they are passed as TF_VAR_* environment variables (see README.md).
environment          = "dev"
enable_custom_domain = false

# Environment-specific Application Settings merged on top of the defaults in main.tf.
app_settings = {
  LOG_LEVEL         = "DEBUG"
  FEATURE_FLAG_DEMO = "true"
}
