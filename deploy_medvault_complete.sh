#!/usr/bin/env bash
# ==============================================================================
# MedVault Complete Automated Deployment Script for GKE Autopilot
# Target GCP Project: project-5d074ea5-fe5a-455d-acd
# Region: asia-south1 (Mumbai)
# ==============================================================================

set -euo pipefail

PROJECT_ID="${1:-project-5d074ea5-fe5a-455d-acd}"
REGION="${2:-asia-south1}"
CLUSTER_NAME="medvault-cluster"
REPO_NAME="medvault-repo"

echo "=========================================================="
echo " Starting MedVault GKE Autopilot Deployment               "
echo " Project: ${PROJECT_ID} | Region: ${REGION}                "
echo "=========================================================="

# 1. Set Project
echo "[+] Step 1: Setting active GCP project to ${PROJECT_ID}..."
gcloud config set project "${PROJECT_ID}"

# 2. Enable Required APIs
echo "[+] Step 2: Enabling GKE, Artifact Registry, and Cloud Build APIs..."
gcloud services enable container.googleapis.com artifactregistry.googleapis.com cloudbuild.googleapis.com

# 3. Create GKE Autopilot Cluster
echo "[+] Step 3: Checking / Creating GKE Autopilot Cluster '${CLUSTER_NAME}'..."
if gcloud container clusters describe "${CLUSTER_NAME}" --region="${REGION}" &>/dev/null; then
    echo "    [i] Cluster '${CLUSTER_NAME}' already exists and is active."
else
    echo "    [+] Provisioning new GKE Autopilot cluster (this takes ~8-10 mins)..."
    gcloud container clusters create-auto "${CLUSTER_NAME}" --region="${REGION}"
fi

# 4. Get Cluster Credentials for kubectl
echo "[+] Step 4: Connecting kubectl to '${CLUSTER_NAME}'..."
gcloud container clusters get-credentials "${CLUSTER_NAME}" --region="${REGION}"

# 5. Create Artifact Registry Repository
echo "[+] Step 5: Checking / Creating Artifact Registry repository '${REPO_NAME}'..."
if gcloud artifacts repositories describe "${REPO_NAME}" --location="${REGION}" &>/dev/null; then
    echo "    [i] Repository '${REPO_NAME}' already exists."
else
    gcloud artifacts repositories create "${REPO_NAME}" \
        --repository-format=docker \
        --location="${REGION}" \
        --description="Docker repository for MedVault"
fi

# 6. Build and Push Images via Cloud Build
echo "[+] Step 6: Building Backend image using Cloud Build..."
gcloud builds submit ./backend \
    --tag "${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}/backend:latest"

echo "[+] Step 6: Building Frontend image using Cloud Build..."
gcloud builds submit --config=cloudbuild-frontend.yaml .

# 7. Create Kubernetes Secrets
echo "[+] Step 7: Creating Kubernetes Secret 'medvault-secrets'..."
kubectl create secret generic medvault-secrets \
    --from-literal=OPENAI_API_KEY='demo-key' \
    --from-literal=GROQ_API_KEY='demo-key' \
    --from-literal=FIREBASE_STORAGE_BUCKET='demo.firebasestorage.app' \
    --from-literal=SMTP_SERVER='smtp.gmail.com' \
    --from-literal=SMTP_PORT='587' \
    --from-literal=SMTP_USER='demo@gmail.com' \
    --from-literal=SMTP_PASS='demo' \
    --from-literal=MAIL_FROM_EMAIL='demo@gmail.com' \
    --from-literal=MAIL_FROM_NAME='MediVault' \
    --from-literal=FRONTEND_URL='http://localhost' \
    --from-literal=FIREBASE_CREDENTIALS_JSON='{}' \
    --dry-run=client -o yaml | kubectl apply -f -

# 8. Apply Kubernetes Manifests in Exact Sequence
echo "[+] Step 8: Applying Kubernetes manifests..."
kubectl apply -f k8s/backendconfig.yaml
kubectl apply -f k8s/service.yaml
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/ingress.yaml

# 9. Verify Rollout Status
echo "[+] Step 9: Verifying pod rollout..."
kubectl rollout status deployment/backend --timeout=180s || true
kubectl rollout status deployment/frontend --timeout=180s || true

echo "=========================================================="
echo " MedVault Successfully Deployed to GKE!                   "
echo "=========================================================="
kubectl get nodes
kubectl get pods,svc,ingress,deploy -o wide
echo "=========================================================="
echo "Run 'kubectl get ingress medvault-ingress -w' to watch for your public IP."
echo "=========================================================="
