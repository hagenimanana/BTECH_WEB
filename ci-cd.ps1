# ============================
# Windows PowerShell CI/CD Script
# Node.js + Minikube Deployment
# ============================

$ErrorActionPreference = "Stop"

# -----------------------------------
# 1. Ensure Minikube is Running
# -----------------------------------
Write-Host "Checking Minikube status..." -ForegroundColor Cyan
$mkStatus = minikube status | Select-String "Running"

if (-not $mkStatus) {
    Write-Host "Starting Minikube..." -ForegroundColor Yellow
    minikube start --driver=docker
} else {
    Write-Host "Minikube is already running." -ForegroundColor Green
}

# -----------------------------------
# 2. Configure Docker to use Minikube
# -----------------------------------
Write-Host "Switching Docker to Minikube environment..." -ForegroundColor Cyan
minikube docker-env | Invoke-Expression

# -----------------------------------
# 3. Build Docker Image
# -----------------------------------
$VERSION = (Get-Date -Format "yyyyMMdd-HHmmss")
$IMAGE_NAME = "btech:$VERSION"
Write-Host "Building Docker image $IMAGE_NAME ..." -ForegroundColor Cyan

try {
    docker build -t $IMAGE_NAME .
    # Also tag as dev
    docker tag $IMAGE_NAME btech:dev
} catch {
    Write-Host "ERROR: Failed to build Docker image!" -ForegroundColor Red
    exit 1
}

# -----------------------------------
# 4. Update deployment.yaml Image
# -----------------------------------
Write-Host "Updating deployment.yaml with image $IMAGE_NAME ..." -ForegroundColor Cyan

if (Test-Path "deployment.yaml") {
    (Get-Content deployment.yaml) `
        -replace "image: .*", "image: $IMAGE_NAME" |
        Set-Content deployment.yaml
} else {
    Write-Host "ERROR: deployment.yaml not found!" -ForegroundColor Red
    exit 1
}

# -----------------------------------
# 5. Apply Kubernetes YAML Files
# -----------------------------------
Write-Host "Applying Kubernetes deployment and service..." -ForegroundColor Cyan
try {
    kubectl apply -f deployment.yaml --validate=false
    kubectl apply -f service.yaml --validate=false
} catch {
    Write-Host "ERROR: Failed to apply Kubernetes YAML files!" -ForegroundColor Red
    exit 1
}

# -----------------------------------
# 6. Restart Deployment
# -----------------------------------
Write-Host "Restarting deployment..." -ForegroundColor Cyan
kubectl rollout restart deployment/node-deployment

# -----------------------------------
# 7. Wait for Pods to be Ready
# -----------------------------------
Write-Host "Waiting for pods to be ready..." -ForegroundColor Cyan
kubectl wait --for=condition=ready pod -l app=node-app --timeout=90s

# -----------------------------------
# 8. Display Pod & Service Status
# -----------------------------------
Write-Host "`nPods status:" -ForegroundColor Green
kubectl get pods -o wide

Write-Host "`nService info:" -ForegroundColor Green
kubectl get svc

# -----------------------------------
# 9. Port-Forward to localhost:3000
# -----------------------------------
Write-Host "Setting up port-forward to localhost:3000..." -ForegroundColor Cyan
Start-Process powershell -ArgumentList "kubectl port-forward svc/node-service 3000:3000"

# -----------------------------------
# 10. Show Logs Automatically
# -----------------------------------
Write-Host "Streaming pod logs (press CTRL+C to stop)..." -ForegroundColor Cyan

# Use single quotes to avoid string terminator issues
$pod = kubectl get pod -l app=node-app -o 'jsonpath={.items[0].metadata.name}'

kubectl logs -f $pod

# -----------------------------------
# 11. Success Message
# -----------------------------------
Write-Host "`n🎉 CI/CD Deployment completed successfully!" -ForegroundColor Green
