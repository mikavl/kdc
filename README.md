# Kerberos 5 Administration Server and Key Distribution Center

This repository includes a container image and Helm chart for running a Kerberos 5 administration server (kadmind) and one or more key distribution centers (KDCs).

## Installation

1. Set the namespace and some helper variables (the domain depends on the release name you pass to Helm, so make sure to change it also here if you do):

```
NAMESPACE=kerberos
DOMAIN=kdc.$NAMESPACE.svc.cluster.local

PRIMARY=kdc-0
SECONDARY=kdc-1
TERTIARY=kdc-2
```

2. Install the Kerberos administration server and key distribution centers. Create a `values.yaml` file or use `--set` to customize any options you need:

```
helm upgrade --install kdc charts/kdc --namespace $NAMESPACE --create-namespace
```

The default install three KDCs, one of which is the administration server.

3. Create the Kerberos database on the primary server:

```
kubectl exec -it -n $NAMESPACE $PRIMARY -c init-realm -- \
  kdb5_util create -s
```

4. Create and add the principals for the administration server (`kiprop/` is automatically created):

```
kubectl exec -n $NAMESPACE $PRIMARY -c kadmind-kpropd -- \
  kadmin.local -p local -q "addprinc -randkey host/$PRIMARY.$DOMAIN"

kubectl exec -n $NAMESPACE $PRIMARY -c kadmind-kpropd -- \
  kadmin.local -p local -q "ktadd host/$PRIMARY.$DOMAIN kiprop/$PRIMARY.$DOMAIN"
```

5. Create and add the principals for the secondary and tertiary servers:

```
kubectl exec -n $NAMESPACE $PRIMARY -c kadmind-kpropd -- \
  kadmin.local -p local -q "addprinc -randkey host/$SECONDARY.$DOMAIN"

kubectl exec -n $NAMESPACE $PRIMARY -c kadmind-kpropd -- \
  kadmin.local -p local -q "addprinc -randkey kiprop/$SECONDARY.$DOMAIN"

kubectl exec -n $NAMESPACE $PRIMARY -c kadmind-kpropd -- \
  kadmin.local -p local -q "ktadd -k /tmp/$SECONDARY.keytab host/$SECONDARY.$DOMAIN kiprop/$SECONDARY.$DOMAIN"

kubectl exec -n $NAMESPACE $PRIMARY -c kadmind-kpropd -- \
  kadmin.local -p local -q "addprinc -randkey host/$TERTIARY.$DOMAIN"

kubectl exec -n $NAMESPACE $PRIMARY -c kadmind-kpropd -- \
  kadmin.local -p local -q "addprinc -randkey kiprop/$TERTIARY.$DOMAIN"

kubectl exec -n $NAMESPACE $PRIMARY -c kadmind-kpropd -- \
  kadmin.local -p local -q "ktadd -k /tmp/$TERTIARY.keytab host/$TERTIARY.$DOMAIN kiprop/$TERTIARY.$DOMAIN"
```

6. Transfer the stash and keytabs to the secondary KDC. Maybe use a more secure method:

```
STASH=$(kubectl exec -n $NAMESPACE $PRIMARY -c kadmind-kpropd -- \
  cat /var/lib/krb5kdc/stash | base64 -w0)

SECONDARY_KEYTAB=$(kubectl exec -n $NAMESPACE $PRIMARY -c kadmind-kpropd -- \
  /bin/sh -c "cat /tmp/$SECONDARY.keytab | base64 -w0 && rm -f /tmp/$SECONDARY.keytab")

kubectl exec -n $NAMESPACE $SECONDARY -c init-realm -- \
  /bin/sh -c "umask 0077 && echo '$SECONDARY_KEYTAB' | base64 -d > /var/lib/krb5kdc/krb5.keytab"

kubectl exec -n $NAMESPACE $SECONDARY -c init-realm -- \
  /bin/sh -c "umask 0077 && echo '$STASH' | base64 -d > /var/lib/krb5kdc/stash"

```

7. Repeat the process for the tertiary KDC:

```
TERTIARY_KEYTAB=$(kubectl exec -n $NAMESPACE $PRIMARY -c kadmind-kpropd -- \
  /bin/sh -c "cat /tmp/$TERTIARY.keytab | base64 -w0 && rm -f /tmp/$TERTIARY.keytab")

kubectl exec -n $NAMESPACE $TERTIARY -c init-realm -- \
  /bin/sh -c "umask 0077 && echo '$TERTIARY_KEYTAB' | base64 -d > /var/lib/krb5kdc/krb5.keytab"

kubectl exec -n $NAMESPACE $TERTIARY -c init-realm -- \
  /bin/sh -c "umask 0077 && echo '$STASH' | base64 -d > /var/lib/krb5kdc/stash"
```

8. Check the `kpropd` logs if the initial synchronization was successful:

```
kubectl logs -n $NAMESPACE $SECONDARY -c kadmind-kpropd
kubectl logs -n $NAMESPACE $TERTIARY -c kadmind-kpropd
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
