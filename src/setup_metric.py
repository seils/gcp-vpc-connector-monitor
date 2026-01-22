import os
from google.api import label_pb2 as ga_label
from google.api import metric_pb2 as ga_metric
from google.cloud import monitoring_v3

# Configuration
PROJECT_ID = os.environ.get('GCP_PROJECT') 
METRIC_TYPE = 'custom.googleapis.com/vpc_connector/status'

def create_metric_descriptor():
    client = monitoring_v3.MetricServiceClient()
    project_name = f"projects/{PROJECT_ID}"
    
    descriptor = ga_metric.MetricDescriptor()
    descriptor.type = METRIC_TYPE
    descriptor.metric_kind = ga_metric.MetricDescriptor.MetricKind.GAUGE
    descriptor.value_type = ga_metric.MetricDescriptor.ValueType.INT64
    descriptor.description = "Status of Serverless VPC Connector. 1 = Present in this state."
    
    # Define the 'state' label (e.g. READY, ERROR)
    state_label = ga_label.LabelDescriptor()
    state_label.key = "state"
    state_label.value_type = ga_label.LabelDescriptor.ValueType.STRING
    state_label.description = "The current state of the connector (e.g., READY, ERROR)"
    descriptor.labels.append(state_label)

    try:
        result = client.create_metric_descriptor(
            name=project_name,
            metric_descriptor=descriptor
        )
        print(f"Success! Created metric descriptor: {result.name}")
    except Exception as e:
        print(f"Failed to create descriptor: {e}")

if __name__ == "__main__":
    if not PROJECT_ID:
        print("Error: GCP_PROJECT env var is missing.")
    else:
        create_metric_descriptor()
