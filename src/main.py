import os
import time
from google.cloud import vpcaccess_v1
from google.cloud import monitoring_v3

METRIC_TYPE = 'custom.googleapis.com/vpc_connector/status'

def monitor_connectors(event, context):
    """
    Scans VPC Connectors and reports their status to Cloud Monitoring.
    """
    project_id = os.environ.get('GCP_PROJECT')
    regions_env = os.environ.get('MONITOR_REGIONS', 'us-central1')
    regions = regions_env.split(',')
    
    if not project_id:
        print("Error: GCP_PROJECT environment variable is not set.")
        return

    vpc_client = vpcaccess_v1.VpcAccessServiceClient()
    metrics_client = monitoring_v3.MetricServiceClient()
    
    project_name = f"projects/{project_id}"
    time_series_list = []
    
    print(f"Starting check for project: {project_id} in regions: {regions}")

    for region in regions:
        parent = f"projects/{project_id}/locations/{region}"
        try:
            request = vpcaccess_v1.ListConnectorsRequest(parent=parent)
            for connector in vpc_client.list_connectors(request=request):
                connector_short_name = connector.name.split('/')[-1]
                state_name = connector.state.name 
                
                now = time.time()
                seconds = int(now)
                nanos = int((now - seconds) * 10**9)
                
                point = monitoring_v3.Point({
                    "interval": {"end_time": {"seconds": seconds, "nanos": nanos}},
                    "value": {"int64_value": 1}
                })

                series = monitoring_v3.TimeSeries()
                series.metric.type = METRIC_TYPE
                series.metric.labels["state"] = state_name
                
                series.resource.type = "generic_task"
                series.resource.labels["project_id"] = project_id
                series.resource.labels["location"] = region
                series.resource.labels["namespace"] = "vpc-access"
                series.resource.labels["job"] = "connector-monitor"
                series.resource.labels["task_id"] = connector_short_name
                
                series.points = [point]
                time_series_list.append(series)
                
        except Exception as e:
            print(f"Error scanning region {region}: {e}")

    if time_series_list:
        try:
            metrics_client.create_time_series(
                request={"name": project_name, "time_series": time_series_list}
            )
            print(f"Successfully wrote {len(time_series_list)} metric data points.")
        except Exception as e:
            print(f"Failed to write metrics: {e}")
    else:
        print("No connectors found to report.")
