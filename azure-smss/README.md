---
name: Develop in Windows on Azure
description: Get started with Windows development on Microsoft Azure.
tags: [cloud, azure, windows]
icon: /icon/azure.png
---

# azure-smss

Use this template to provision a Windows VM as a Coder workspace for accessing
Microsoft SQL Server Management Studio (SMSS) via RDP. The `Initialize.ps1.tftpl`
file runs on initial startup to initialize the home directory and install RDP, `git`,
and SMSS.

## Authentication

This template assumes that coderd is run in an environment that is authenticated
with Azure. For example, run `az login` then `az account set --subscription=<id>`
to import credentials on the system and user running coderd. For other ways to
authenticate [consult the Terraform docs](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs#authenticating-to-azure).

## Dependencies

This template depends on the Azure CLI tool (`az`) to start and stop the Windows VM. Ensure this
tool is installed and available in the path on the machine that runs coderd.

[Microsoft's RDP client](https://learn.microsoft.com/en-us/windows-server/remote/remote-desktop-services/clients/remote-desktop-clients) must be installed on the local machine to access the workspace.

## Accessing the Desktop

1. Create a new configuration in Microsoft's RDP client, adding 127.0.0.1:3301 as the host,
`coder` as the username and the randomly generated password and connect.
The randomly generated password can be retrieved from the workspace dashboard.

2. Port forward the Windows desktop to your client machine via the following commands:

```sh
coder login <your Coder deployment access URL>
coder tunnel <workspace-name> --tcp 3301:3389
```
