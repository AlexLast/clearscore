apiVersion: v1
kind: Secret
metadata:
  name: wordpress
  namespace: wordpress
type: Opaque
data:
  mysql_user: ${mysql_user}
  mysql_pass: ${mysql_pass}
  mysql_host: ${mysql_host}
  mysql_db: ${mysql_db}
