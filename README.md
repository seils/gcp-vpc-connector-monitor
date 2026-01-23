# Serverless VPC Connector Monitor

An automated monitoring solution that detects Serverless VPC Access Connectors in failed states (`ERROR` or `STATE_UNSPECIFIED`) and alerts via Google Cloud Monitoring.

## 🏗 Architecture

1.  **Cloud Scheduler**: Emits a "run" event every 1 minute.
2.  **Pub/Sub**: Delivers the event to the Cloud Function.
3.  **Cloud Function**:
    * Scans all VPC Connectors in the target region(s).
    * Extracts the current state (e.g., `READY`, `ERROR`).
    * Writes a custom metric `custom.googleapis.com/vpc_connector/status`.
4.  **Cloud Monitoring**: Alerts if the state is `ERROR`.

## 🚀 Usage

### Prerequisites
* Google Cloud SDK installed and authenticated.
* Python 3.10+ installed locally.

### Installation

1.  **Clone the repo:**
    ```bash
    git clone [https://github.com/your-username/gcp-vpc-connector-monitor.git](https://github.com/your-username/gcp-vpc-connector-monitor.git)
    cd gcp-vpc-connector-monitor
    ```

2.  **Run the deployment script:**
    ```bash
    chmod +x deploy/deploy.sh
    ./deploy/deploy.sh
    ```

### Alert Configuration
After deployment, create an Alert Policy in the Google Cloud Console:

* **Metric:** `custom.googleapis.com/vpc_connector/status`
* **Filter:** `state = 'ERROR'`
* **Trigger:** Any value present (Threshold > 0.9).
