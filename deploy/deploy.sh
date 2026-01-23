#!/bin/bash

# Configuration
PROJECT_ID=$(gcloud config get-value project)
REGION="us-central1"
TOPIC_NAME="trigger-every-1min"
SCHEDULER_NAME="scheduler-1min"
FUNCTION_NAME="monitor_vpc_connectors"
SERVICE_ACCOUNT_NAME="vpc-monitor-sa"

echo "Deploying to Project: $PROJECT_ID"

# 1. Enable APIs
echo "Enabling APIs..."
gcloud services enable cloudfunctions.googleapis.com \
    cloudscheduler.googleapis.com \
    vpcaccess.googleapis.com \
    monitoring.googleapis.com \
    run.googleapis.com \
    cloudbuild.googleapis.com

# 2. Create Service Account
echo "Creating Service Account..."
if ! gcloud iam service-accounts describe ${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com > /dev/null 2>&1; then
    gcloud iam service-accounts create $SERVICE_ACCOUNT_NAME --display-name "VPC Monitor Service Account"
fi
SA_EMAIL="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

# 3. Grant Permissions
echo "Granting Permissions..."
gcloud projects add-iam-policy-binding $PROJECT_ID --member="serviceAccount:$SA_EMAIL" --role="roles/vpcaccess.viewer"
gcloud projects add-iam-policy-binding $PROJECT_ID --member="serviceAccount:$SA_EMAIL" --role="roles/monitoring.metricWriter"

# 4. Define Custom Metric
echo "Defining Custom Metric..."
export GCP_PROJECT=$PROJECT_ID
pip install -r src/requirements.txt
python src/setup_metric.py

# 5. Create Scheduler Infrastructure
echo "Creating Scheduler & Topic..."
if ! gcloud pubsub topics describe $TOPIC_NAME > /dev/null 2>&1; then
    gcloud pubsub topics create $TOPIC_NAME
fi

if ! gcloud scheduler jobs describe $SCHEDULER_NAME --location=$REGION > /dev/null 2>&1; then
    gcloud scheduler jobs create pubsub $SCHEDULER_NAME \
        --schedule "* * * * *" \
        --topic $TOPIC_NAME \
        --message-body "tick" \
        --location $REGION
fi

# 6. Deploy Cloud Function
echo "Deploying Cloud Function..."
gcloud functions deploy $FUNCTION_NAME \
    --gen2 \
    --region $REGION \
    --runtime python310 \
    --source ./src \
    --entry-point monitor_connectors \
    --trigger-topic $TOPIC_NAME \
    --service-account $SA_EMAIL \
    --set-env-vars GCP_PROJECT=$PROJECT_ID,MONITOR_REGIONS=$REGION

# 7. Grant Invoker Permission
echo "Granting Invoker Permission..."
gcloud run services add-iam-policy-binding $FUNCTION_NAME \
    --region $REGION \
    --member="serviceAccount:$SA_EMAIL" \
    --role="roles/run.invoker"

echo "Deployment Complete!"
