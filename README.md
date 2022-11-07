# Kerberos 5 Administration Server and Key Distribution Center

This repository includes a container image and Helm chart for running a Kerberos 5 administration server (kadmind) and one or more key distribution centers (KDCs).

## Installation

1. Set the namespace:

```
NAMESPACE=kerberos
```

2. Install the Kerberos administration server and key distribution centers:

```
helm upgrade --install kdc charts/kdc --namespace $NAMESPACE --create-namespace \
  --set persistence.storageClassName=local --set image.pullPolicy=Always --set image.tag=main --set replicaCount=2
```

3. Create the Kerberos database:

```
kubectl exec -it -n $NAMESPACE kdc-0 -c init-realm -- kdb5_util create -s
```

4. Add the principals for the KDCs in the statefulset (kiprop/kdc-0 is automatically created):

```
kubectl exec -n $NAMESPACE kdc-0 -c kadmind-kpropd -- kadmin.local -p local -q \
  "addprinc -randkey host/kdc-0.kdc.$NAMESPACE.svc.cluster.local"

kubectl exec -n $NAMESPACE kdc-0 -c kadmind-kpropd -- kadmin.local -p local -q \
  "ktadd host/kdc-0.kdc.$NAMESPACE.svc.cluster.local kiprop/kdc-0.kdc.$NAMESPACE.svc.cluster.local"
```
# KDC (repeat for each replica)

```
kubectl exec -n $NAMESPACE kdc-0 -c kadmind-kpropd -- kadmin.local -p local -q \
  "addprinc -randkey host/kdc-1.kdc.$NAMESPACE.svc.cluster.local"

kubectl exec -n $NAMESPACE kdc-0 -c kadmind-kpropd -- kadmin.local -p local -q \
  "addprinc -randkey kiprop/kdc-1.kdc.$NAMESPACE.svc.cluster.local"

kubectl exec -n $NAMESPACE kdc-0 -c kadmind-kpropd -- kadmin.local -p local -q \
  "ktadd -k /var/lib/krb5kdc/krb5.keytab.kdc-1 host/kdc-1.kdc.$NAMESPACE.svc.cluster.local kiprop/kdc-1.kdc.$NAMESPACE.svc.cluster.local"

```

5. Transfer the keytab to replica kdc:s /var/lib/krb5kdc/krb5.keytab:

```
KEYTAB=$(kubectl exec -n $NAMESPACE kdc-0 -c kadmind-kpropd -- cat /var/lib/krb5kdc/krb5.keytab.kdc-1 | base64 -w0)
kubectl exec -n $NAMESPACE -c init-realm kdc-1 -- /bin/sh -c "umask 0077 && echo '$KEYTAB' | base64 -d > /var/lib/krb5kdc/krb5.keytab"
kubectl exec -n $NAMESPACE kdc-0 -c kadmind-kpropd -- rm -f /var/lib/krb5kdc/krb5.keytab.kdc-1
```

6. Copy the stash file from the kadmind data volume to the kdc data volumes. Use a more secure method if you use this in a production environment for who knows what reason:

```
STASH=$(kubectl exec -n $NAMESPACE -c kadmind-kpropd kdc-0 -- cat /var/lib/krb5kdc/stash | base64 -w0)
kubectl exec -n $NAMESPACE -c init-realm kdc-1 -- /bin/sh -c "umask 0077 && echo '$STASH' | base64 -d > /var/lib/krb5kdc/stash"
```

7. Check the `kpropd` logs if the initial synchronization was successful:

```
kubectl logs -n $NAMESPACE kdc-1 -c kadmind-kpropd -f
```

   You should see something along the lines of:

```
KDC is synchronized with master.
Waiting for 120 seconds before checking for updates again
```

## Notes About Scaling

The Kerberos setup in this repository does not scale simply by increasing the replica count of the StatefulSet. Instead, the following steps need to be taken when scaling up the number of KDCs:

  1. The `kadm5.acl` needs to be modified so that each KDC has replication permissions with their `kiprop/` principal. This is handled by the Helm chart when installing or upgrading.
  2. The `krb5.conf` needs to be modified so that each KDC is added. This is also handled by the Helm chart when installing or upgrading.
  3. Each new KDC then needs:

    a) A keytab file with principals for `kiprop/` and `host/` for them.
    b) Database password stash.

Implementing scaling is left as an exercise for the reader.
