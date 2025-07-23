# BigQuery Jobs Check

This jobs is aimed at checking whether a GCP BigQuery job or set of jobs ran successfully. 

## Example Configuration

```yaml
gcp/bigquery_jobs:
  runbook: 'https://www.ensono.com'
  stages:
    - name: 'prod'
      targets:
        - project: 'vh-euw2-rg-data-prod'
          jobType: 'EXTRACT'
          maxResults: '100'
          startTime: '00:00:00Z'
          endTime: '00:30:00Z'
```

<br>

`target.project` - The GCP project the check is aimed at

<br>

`target.jobType` - The Bigquery job type to filter on

<br>

`target.maxResults` - Maximum number of results to return in the API call to the GCP BigQuery API

<br>

`target.startTime` - If set, only jobs created after or at this timestamp are returned.

If you want to specify a time on the day the check runs you can use something like `00:00:00Z`

If you would like to specify a time on a specific date you can use something like `18/07/2025 00:00:00Z`

<br>

`target.endTime` - If set, only jobs created before or at this timestamp are returned.

If you want to specify a time on the day the check runs you can use something like `00:00:00Z`

If you would like to specify a time on a specific date you can use something like `18/07/2025 00:00:00Z`


<br>

## Todo

- Add more filters for retrieving jobs
- Implement paging to API calls for situations where many jobs need to be checked