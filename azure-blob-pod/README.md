# Azure Blob Storage Template

This template mounts a static, pre-existing Azure Storage Account blob into the
Coder workspace. The following pre-requisites are needed for this template to work:

- Azure AKS cluster with [Azure Blob CSI Driver enabled](https://learn.microsoft.com/en-us/azure/aks/azure-blob-csi?tabs=NFS#enable-csi-driver-on-a-new-or-existing-aks-cluster)
- [Azure Storage Account](https://learn.microsoft.com/en-us/azure/storage/common/storage-account-create?tabs=azure-portal)

## 1. Create the Azure Blob Storage K8s Secret

Once the CSI Driver is enabled and Storage Account created, you will need to give
Kubernetes credentials to access the blob storage. Create the secret with the command
below using your storage account name and access key:

```console
kubectl create secret generic azure-secret -n coder --from-literal azurestorageaccountname="NAME" --from-literal azurestorageaccountkey="KEY" --type=Opaque
```

## 2. Create the PersistentVolume

Next, create the PersistentVolume in your cluster that references the Storage Account.
Note that the PV _must_ be in the same namespace as the secret created above.

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  annotations:
    pv.kubernetes.io/provisioned-by: blob.csi.azure.com
  name: pv-blob
  namespace: coder
spec:
  capacity:
    storage: 10Gi
  accessModes:
    - ReadOnlyMany
  persistentVolumeReclaimPolicy: Retain  # If set as "Delete" container would be removed after pvc deletion
  # this StorageClass is created automatically when enabling the Azure Blob CSI Driver
  storageClassName: azureblob-fuse-premium
  mountOptions:
    - -o allow_other
    - --file-cache-timeout-in-seconds=120
  csi:
    driver: blob.csi.azure.com
    readOnly: false
    # volumeid has to be unique for every identical storage blob container in the cluster
    # character `#` is reserved for internal use and cannot be used in volumehandle
    volumeHandle: <arbitrary-name>
    # the below fields are required
    volumeAttributes:
      containerName: <blob-container-name>
      resourceGroup: <resource-group-name>
      storageAccount: <storage-account-name>
    nodeStageSecretRef:
      name: azure-secret
      namespace: coder
```

## 3. Create the workspace

Now that the PV and K8s secret are created, you can use the template to create
the Coder workspace. By default, the template will create two PVCs, one for the
`/home/coder` directory (using the `default` StorageClass, mounted as an Azure Persistent Disk)
and one for the Azure Blob Storage Account, mounted in the `/blob` directory.

> Note: the PVC disk size must be the same size as the PV; it must also have the
> same AccessMode.
