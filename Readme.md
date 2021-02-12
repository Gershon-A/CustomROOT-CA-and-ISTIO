### Overview
This flow used "SmallStep" to create and manage certificates.

### Requirements
- Kubernetes Cluster 
- ISTIO 1.8.2 with "demo" profile installed
- istioctl installed

### The flow
In this flow, we will Create and upload Custom ROOT CA to ISTIO, then we can enable "MUTUAL" authentication for each name space to use mTLS only inside our workload

![ISTIO Custom CA](https://i.imgur.com/FfRAMcC.png)
### To setup all automatically run 
```
istio-custom-ca.sh -d=TEST-CA
```
### Manual procedure
1. Prepare
- I use Windows, to mount folder correctly add `MYPATH` to environment. 
```
export  MYPATH="$(cygpath -w $PWD)"
```
- Create a directory, where the certificates will reside.
```
mkdir ROOT-CA
```
2. I'll be going to use "smallstep" docker image..

We need to specify `--name` (we going to use it latter) and `--network host` we need to communicate with it lattes as well.
        - Start "smallstep"
```
docker run --name smallstep --network host -it --user root -v "$MYPATH/ROOT-CA":/home/step smallstep/step-ca sh
```
3. In the smallstep container terminal, start the initials setup
```
/home/step # step ca init
✔ What would you like to name your new PKI? (e.g. Smallstep): ISTIO
✔ What DNS names or IP addresses would you like to add to your new CA? (e.g. ca.smallstep.com[,1.1.1.1,etc.]): localhost
✔ What address will your new CA listen at? (e.g. :443): :9001
✔ What would you like to name the first provisioner for your new CA? (e.g. you@smallstep.com): istiotest
✔ What do you want your password to be? [leave empty and we'll generate one]: ☺☺☺☺☺☺

Generating root certificate...
all done!

Generating intermediate certificate...
all done!
```

4. Optional: We want to create custom Intermediate for ISTIO 
(password to decrypt is the password Yu provided in the `step ca init` step )

== New ROOT CA ==
```
step certificate create "EKS DEV ISTIO Root CA"  --profile root-ca  certs/root-cert-istio-dev.pem secrets/root-key-istio-dev.pem --kty RSA --no-password --insecure --not-after 87600h --san *.example.com
```
== Intermediate CA for ROOT CA ==
```
step certificate create "Example ISTIO Intermediate CA" certs/intermediate-cert-istio-dev.pem secrets/intermediate-key-istio-dev.pem --profile intermediate-ca --kty RSA --ca certs/root-cert-istio-dev.pem   --ca-key secrets/root-key-istio-dev.pem  --no-password --insecure --not-after 43800h --san *.dev.example.com,*.example.com
Your certificate has been saved in certs/intermediate-cert-istio-dev.pem.
Your private key has been saved in secrets/intermediate-key-istio-dev.pem.
```

5. Create Chain

== Chain ==
```
mkdir cert-chain 
step certificate bundle certs/intermediate-cert-istio-dev.pem certs/root_ca.crt ./cert-chain/cert-chain-istio-dev.pem
```
exit from container to regular shell.

6.  Plug-in created certificates to ISTIO.

If ISTIO already running, be sure to recreate istiod, ingress and egress pod's to pick up new certificate
```
kubectl create secret generic cacerts -n istio-system \
--from-file=root-cert.pem=ROOT-CA/certs/root-cert-istio-dev.pem \
--from-file=ca-cert.pem=ROOT-CA/certs/intermediate-cert-istio-dev.pem \
--from-file=ca-key.pem=ROOT-CA/secrets/intermediate-key-istio-dev.pem \
--from-file=cert-chain.pem=ROOT-CA/cert-chain/cert-chain-istio-dev.pem
```
7. Recreate istiod and ingress
```
kubectl delete po -n istio-system -l app=istiod && \
kubectl delete po -n istio-system -l app=istio-ingressgateway && \
kubectl -n istio-system wait --for=condition=ready pod -l app=istiod && \
kubectl -n istio-system wait --for=condition=ready pod -l app=istio-ingressgateway
```
8. Read uploaded certificate
```
kubectl -n istio-system get secret cacerts -o=go-template='{{index .data "root-cert.pem"}}' | \
base64 -d > tmp-root-cert.pem && \
openssl x509 -in tmp-root-cert.pem -text -noout
```
### Test
- set up sample services
```
istioctl kube-inject -f test/resources/sleep.yaml | kubectl apply -f -
istioctl kube-inject -f test/resources/httpbin.yaml | kubectl apply -f -
```

- remove the hpa for istiod
```
kubectl delete -n istio-system hpa/istiod 
```
- Turning mTLS to strict
```
kubectl apply -f test/resources/default-peerauth.yaml -n istio-system
```
- Let's check the logs to make sure our cacert got picked up
```
ISTIOD_POD=$(kubectl get po -n istio-system | grep Running | grep istiod | awk '{print $1}')
kubectl logs  $ISTIOD_POD -n istio-system | sed -n '/JWT policy is/,/validationServer/p'
```
- Let's check proxy is connected
```
istioctl proxy-status
NAME                                 CDS        LDS        EDS        RDS        ISTIOD                      VERSION
httpbin-74fb669cc6-w4n6p.default     SYNCED     SYNCED     SYNCED     SYNCED     istiod-7f785478df-gt442     1.8.2
sleep-854565cb79-b7zr7.default       SYNCED     SYNCED     SYNCED     SYNCED     istiod-7f785478df-gt442     1.8.2
```
- Let's check we still can communicate
```
SLEEP_POD=$(kubectl get po -n default | grep -i running | grep sleep | awk '{print $1}')
kubectl exec -it $SLEEP_POD -c sleep -- curl httpbin:8000/headers
{
  "headers": {
    "Accept": "*/*",
    "Content-Length": "0",
    "Host": "httpbin:8000",
    "User-Agent": "curl/7.69.1",
    "X-B3-Parentspanid": "850ed68d5c7993c9",
    "X-B3-Sampled": "1",
    "X-B3-Spanid": "5b48ddfa859e3e2f",
    "X-B3-Traceid": "43e6ad4fe6efe341850ed68d5c7993c9",
    "X-Envoy-Attempt-Count": "1",
    "X-Forwarded-Client-Cert": "By=spiffe://cluster.local/ns/default/sa/httpbin;Hash=e38f9aa43589c9732823292745596b63be862bcaa2e1b6240932a3e7cf1e44da;Subject=\"\";URI=spiffe://cluster.local/ns/default/sa/sleep"
  }
}
```
- Let's check what certificate used by pod
```
kubectl exec -it $SLEEP_POD -c istio-proxy -- openssl s_client -showcerts -connect httpbin:8000
```
### Run the official ISTIO Mutual TLS test:
-
```
kubectl create ns foo
istioctl kube-inject -f test/resources/sleep.yaml | kubectl apply -n foo -f -
istioctl kube-inject -f test/resources/httpbin.yaml | kubectl apply -n foo -f -
kubectl create ns bar
istioctl kube-inject -f test/resources/sleep.yaml | kubectl apply -n bar -f -
istioctl kube-inject -f test/resources/httpbin.yaml | kubectl apply -n bar -f -
```
```
kubectl create ns legacy
kubectl apply -f test/resources/sleep.yaml -n legacy
```
- Check peerauthentication enabled
```
kubectl get peerauthentication --all-namespaces
NAMESPACE      NAME      AGE
istio-system   default   10m
```
if does not:
```
kubectl apply -f test/resources/default-peerauth.yaml -n istio-system
```
- Now, we should see the request from sleep.legacy to httpbin.foo failing.
```
for from in "foo" "bar" "legacy"; do for to in "foo" "bar"; do kubectl exec "$(kubectl get pod -l app=sleep -n ${from} -o jsonpath={.items..metadata.name})" -c sleep -n ${from} -- curl http://httpbin.${to}:8000/ip -s -o /dev/null -w "sleep.${from} to httpbin.${to}: %{http_code}\n"; done; done
```            