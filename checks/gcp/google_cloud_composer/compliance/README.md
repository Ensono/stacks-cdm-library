# Google Cloud Composer Upgrade Check

This check uses the gcloudCLI to check Google Cloud Composer environments for available upgrades. 
If there is an upgrade available, the check will fail. 

## Cavets
I would like to have been able to make this check more granular in checking that the current version of cloud composer is still in support with Google however, Google Cloud shows a waring when a version is due to run out of support in the console, but does not represent this warning in output from CLI calls or API calls so they are not detectable programatically. 

This is a limitation of Google Cloud. 

## Example Configurations

### Pipeline Job Parameters
```yaml
        jobs:
          - name: google_cloud_composer
            displayName: 'Google Cloud Composer Upgrade'
            dependsOn: []
            condition:
            variableGroups:
            variables:
            secureFiles:
              - name: 'GCLOUDCLI_KEYFILE'
                file: 'sre_cdm_keyfile_prod.json'
            tasks:
              useTaskCtl: false
              checkName: 'gcp/google_cloud_composer'
              cdmVariables:
              ADOVariables:
```
Note that due to gcloudCLI requiring a Json keyfile to authenticate you must upload the keyfile to Ado as a secure file and reference the filename in the `jobs.secureFiles` object.

### configuration.yaml
```yaml
gcp/google_cloud_composer:
  runbook: 'https://www.ensono.com'
  stages:
    - name: 'dev'
      targets:
        - project: 'vh-euw2-rg-data-dev'
          location: 'europe-west2'
          environment: 'vh-dp-composer-dev-green'

    - name: 'QA'
      targets:
        - project: 'vh-euw2-rg-data-qa'
          location: 'europe-west2'
          environment: 'vh-dp-composer-qa-green'

    - name: 'PAT'
      targets:
        - project: 'vh-euw2-rg-data-pat'
          location: 'europe-west2'
          environment: 'vh-dp-composer-pat-green'

    - name: 'prod'
      targets:
        - project: 'vh-euw2-rg-data-prod'
          location: 'europe-west2'
          environment: 'vh-dp-composer-prod'
```
The Google Cloud Project, Location and Composer Environment names must be configured here as they are used to configure the gcloudCLI for the check. 