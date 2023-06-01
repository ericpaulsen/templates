## nfs-pod

This template provisions a Coder workspace Kubernetes pod, with an NFS share mounted
as a volume. The NFS share will synchronize the server-side files onto the client (the K8s pod workspace)
When you stop the Coder workspace and rebuild, the NFS share will be re-mounted, and the changes persisted.

The key difference with this template relative to others that create
a K8s pod, are the `volume` and `volume_mount` blocks in the pod and container spec,
respectively:

```terraform
resource "kubernetes_pod" "main" {
    container {
        volume_mount {
            mount_path = "/mnt/nfs-clientshare" # mount path on the pod
            name       = "nfs-share"
        }
    }
    volume {
        name = "nfs-share"
        nfs {
            path   = "/mnt/nfs-share" # path to be exported from the server
            server = "<IP-address>" # server IP address
        }
    }
}
```

## server-side configuration

1. Create an NFS mount on the server for the clients to access:

   ```console
   export NFS_MNT_PATH=/mnt/nfs_share
   # Create directory to shaare
   sudo mkdir -p $NFS_MNT_PATH
   # Assign UID & GIDs access
   sudo chown -R uid:gid $NFS_MNT_PATH
   sudo chmod 777 $NFS_MNT_PATH
   ```

1. Grant access to the client by updating the `/etc/exports` file, which
   controls the directories shared with remote clients. See
   [Red Hat's docs for more information about the configuration options](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/5/html/deployment_guide/s1-nfs-server-config-exports).

   ```console
   # Provides read/write access to clients accessing the NFS from any IP address.
   /mnt/nfs_share  *(rw,sync,no_subtree_check)
   ```

1. Export the NFS file share directory. You must do this every time you change
   `/etc/exports`.

   ```console
   sudo exportfs -a
   sudo systemctl restart <nfs-package>
   ```
