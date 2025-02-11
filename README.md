# Configuration-driven Maintenance Library (CDM Library)
The CDM Library acts a single centrally managed code repository which is integrated into the runtime code of the CDM Checks and Tasks framework via the pipeline. This enables the CDM framework to scale across multiple clients.

The CDM Library supports Pester variants enabling flexibility when invoking Pester tests. The CDM Library contains the follwing code:

- Checks:
    - Invoke-CDMCheck.ps1
    - Pester tests with Pester variants
- Integrations:
    - ADO
        - Invoke-ADOIntegration.ps1
        - CreateWorkItem.ps1
- PowerShell
    - Functions

## Repository Structure
```
├───checks
│   ├───aws
│   │   └───aws_elastic_kubernetes_service
│   │       └───sre
│   ├───azure
│   │   ├───azure_application_gateway
│   │   │   └───sre
│   │   ├───azure_devops
│   │   │   └───sre
│   │   └───azure_kubernetes_service
│   │       └───sre
│   ├───digicert
│   │   └───sre
│   ├───github
│   │   └───sre
│   └───terraform
│       └───sre
├───integrations
│   └───ado
│       └───ensonodigitaluk
│           └───sre
└───powershell
    └───functions
```
