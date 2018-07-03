kind: Service
apiVersion: v1
metadata:
  name: wordpress
  namespace: wordpress
  labels:
    app: wordpress
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-backend-protocol: http
    service.beta.kubernetes.io/aws-load-balancer-ssl-ports: "443"
    service.beta.kubernetes.io/aws-load-balancer-ssl-cert: ${acm_arn}
spec:
  selector:
    app: wordpress
  ports:
  - protocol: TCP
    port: 443
    targetPort: 80
  type: LoadBalancer
