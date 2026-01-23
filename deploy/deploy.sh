#!/bin/bash
set -e

# Configuration
PROJECT_ID=$(gcloud config get-value project)
REGION="us-central1"
TOPIC_NAME="trigger-every-1min"
SCHEDULER_NAME="scheduler-1min"
FUNCTION_NAME="monitor_vpc_connectors"
SERVICE_ACCOUNT_NAME="vpc-monitor-sa"

echo "Deploying to Project: $PROJECT_ID"

# 1. Enable APIs (Added eventarc.googleapis.com)
echo "Enabling APIs..."
gcloud services enable cloudfunctions.googleapis.com \
    cloudscheduler.googleapis.com \
    vpcaccess.googleapis.com \
    monitoring.googleapis.com \
    run.googleapis.com \
    cloudbuild.googleapis.com \
    artifactregistry.googleapis.com \
    eventarc.googleapis.com

echo "  > Waiting 30 seconds for API propagation..."
sleep 30

# 2. Fix Default Build Permissions
echo "Verifying Cloud Build permissions..."
PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")
DEFAULT_COMPUTE_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"

gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:$DEFAULT_COMPUTE_SA" \
    --role="roles/cloudbuild.builds.builder" \
    --condition=None --quiet > /dev/null

# 3. Create Service Account
echo "Creating Service Account..."
if ! gcloud iam service-accounts describe ${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com > /dev/null 2>&1; then
    gcloud iam service-accounts create $SERVICE_ACCOUNT_NAME --display-name "VPC Monitor Service Account"
    echo "  > Waiting 30 seconds for Service Account propagation..."
    sleep 30
else
    echo "  > Service Account already exists."
fi
SA_EMAIL="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

# 4. Grant Permissions
echo "Granting Permissions..."
gcloud projects add-iam-policy-binding $PROJECT_ID --member="serviceAccount:$SA_EMAIL" --role="roles/vpcaccess.viewer" --condition=None --quiet > /dev/null
gcloud projects add-iam-policy-binding $PROJECT_ID --member="serviceAccount:$SA_EMAIL" --role="roles/monitoring.metricWriter" --condition=None --quiet > /dev/null

# 5. Define Custom Metric
echo "Defining Custom Metric..."
export GCP_PROJECT=$PROJECT_ID

if [ ! -d "venv" ]; then
    echo "  > Creating virtual environment..."
    python3 -m venv venv
fi

source venv/bin/activate

echo "  > Installing dependencies..."
pip install --upgrade pip
pip install -r src/requirements.txt --extra-index-url https://pypi.org/simple

echo "  > Running setup_metric.py..."
python src/setup_metric.py
deactivate
echo "  > Metric setup complete."

# 6. Create Scheduler Infrastructure
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

# 7. Deploy Cloud Function
echo "Deploying Cloud Function..."
gcloud functions deploy $FUNCTION_NAME \
    --gen2 \
    --region $REGION \
    --runtime python310 \
    --source ./src \
    --entry-point monitor_connectors \
    --trigger-topic $TOPIC_NAME \
    --service-account $SA_EMAIL \
    --set-env-vars GCP_PROJECT=$PROJECT_ID,MONITOR_REGIONS=$REGION \
    --quiet

# 8. Grant Invoker Permission (UPDATED)
echo "Granting Invoker Permission..."
# Cloud Run replaces underscores with hyphens in the service name.
# We must use the hyphenated name for the Cloud Run command.
RUN_SERVICE_NAME=${FUNCTION_NAME//_/-}

gcloud run services add-iam-policy-binding $RUN_SERVICE_NAME \
    --region $REGION \
    --member="serviceAccount:$SA_EMAIL" \
    --role="roles/run.invoker" \
    --quiet

echo "Deployment Complete!"
