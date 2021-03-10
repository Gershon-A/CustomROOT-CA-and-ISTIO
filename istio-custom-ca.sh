
#!/bin/bash
# a script that replaced ISTIO CA with custom.
set -e # exit on error

# Helper functions
echoerr() { 
    tput bold;
    tput setaf 1;
    echo "$@";
    tput sgr0; 1>&2; }
# Prints success/info $MESSAGE in green foreground color
#
# For e.g. You can use the convention of using GREEN color for [S]uccess messages
green_echo() {
    echo -e "\x1b[1;32m[S] $SELF_NAME: $MESSAGE\e[0m"
}

simple_green_echo() {
    echo -e "\x1b[1;32m$MESSAGE\e[0m"
}
blue_echo() {
    echo -e "\x1b[1;34m[I] $SELF_NAME: $MESSAGE\e[0m"
}

simple_blue_echo() {
    echo -e "\x1b[1;34m$MESSAGE\e[0m"
}
# Define Directory
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

print_usage() {
    echo "Replace ISTIO CA with Custom CA"
    echo "This script required that all certificates already created, exists and accesible!!"
    echo "  -h                   --help                      - Show usage information"
    echo "  -d                    --dir                      - The root directory name for the project e.g MY-ROOT"
    echo "  -f                   --force                     - Force the operation (don't wait for user input)"
    echo ""
    echo "Example usage: ./$(basename $0) -d=MY-ROOT "
}

# Prepare env and path solve the docker copy on windows when using bash
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        MYPATH=$PWD
        echo "Operation System dedected is:$OSTYPE"
        echo "MYPATH set to: $MYPATH"
        echo "HOME set to: $HOME"
elif [[ "$OSTYPE" == "darwin"* ]]; then
        # Mac OSX
        MYPATH=$PWD
        echo "Operation System dedected is:$OSTYPE"
        echo "MYPATH set to: $MYPATH"
        echo "HOME set to: $HOME"
elif [[ "$OSTYPE" == "cygwin" ]]; then
        # POSIX compatibility layer and Linux environment emulation for Windows
        MYPATH="$(cygpath -w $PWD)"
        HOME="$(cygpath -w $HOME)"
        echo "Operation System dedected is:$OSTYPE"
        echo "MYPATH set to: $MYPATH"
        echo "HOME set to: $HOME"
elif [[ "$OSTYPE" == "msys" ]]; then
        # Lightweight shell and GNU utilities compiled for Windows (part of MinGW)
        MYPATH="$(cygpath -w $PWD)"
        HOME="$(cygpath -w $HOME)"
        echo "Operation System dedected is:$OSTYPE"
        echo "MYPATH set to: $MYPATH"
        echo "HOME set to: $HOME"
elif [[ "$OSTYPE" == "win32" ]]; then
        # I'm not sure this can happen.
        MYPATH="$(cygpath -w $PWD)"
        HOME="$(cygpath -w $HOME)"
        echo "Operation System dedected is:$OSTYPE"
        echo "MYPATH set to: $MYPATH"
        echo "HOME set to: $HOME"
elif [[ "$OSTYPE" == "freebsd"* ]]; then
        MYPATH=$PWD
        echo "Operation System dedected is:$OSTYPE"
        echo "MYPATH set to: $MYPATH"
        echo "HOME set to: $HOME"
fi
# Parse command line arguments
for i in "$@"
do
case $i in
    -h|--help)
    print_usage
    exit 0
    ;;
    -d=*|--dir=*)
    ROOT_DIRECTORY="${i#*=}"
    shift # past argument=value
    ;;    
    -f|--force)
    FORCE=1
    ;;
    *)
    echoerr "ERROR: Unknown argument"
    print_usage
    exit 1
    # unknown option
    ;;
esac
done
### Print total arguments and their values
# Validate mandatory input
# Validate mandatory input
if [ -z "$MYPATH" ]; then
    echoerr "Error: local path is not set"
    print_usage
    exit 1
fi

# Create a directory, where the certificates will reside.
mkdir -p $ROOT_DIRECTORY
# I'll be going to use "smallstep" docker image..
# Generate password
echo "123" >> $MYPATH/$ROOT_DIRECTORY/password
docker rm -f smallstep
docker run --name smallstep  --network host --user root -v "$MYPATH/$ROOT_DIRECTORY":/home/step smallstep/step-ca step ca init --name "My CUSTOM CA" \
    --provisioner admin \
    --dns localhost \
    --address ":8443" \
    --password-file password 
 
docker start smallstep

# New ROOT CA ==
docker exec  smallstep sh -c "\
step certificate create \"EKS DEV ISTIO Root CA\"  --profile root-ca  certs/root-cert-istio-dev.pem secrets/root-key-istio-dev.pem --kty RSA --no-password --insecure --not-after 87600h --san *.example.com
"

# Intermediate CA for ROOT CA ==
docker exec  smallstep sh -c "\
step certificate create \"Example ISTIO Intermediate CA\" certs/intermediate-cert-istio-dev.pem secrets/intermediate-key-istio-dev.pem --profile intermediate-ca --kty RSA --ca certs/root-cert-istio-dev.pem   --ca-key secrets/root-key-istio-dev.pem  --no-password --insecure --not-after 43800h --san *.dev.example.com,*.example.com
"
# Chain
echo "Creating chain ..."
docker exec  smallstep sh -c "\
mkdir -p cert-chain && \
step certificate bundle certs/intermediate-cert-istio-dev.pem certs/root_ca.crt cert-chain/cert-chain-istio-dev.pem 
"
# Function
# Create \"cacerts\"  in name space \"istio-system\" with custom CA and upload 
create_upload() {
      kubectl create secret generic cacerts -n istio-system \
    --from-file=root-cert.pem=$ROOT_DIRECTORY/certs/root-cert-istio-dev.pem \
    --from-file=ca-cert.pem=$ROOT_DIRECTORY/certs/intermediate-cert-istio-dev.pem \
    --from-file=ca-key.pem=$ROOT_DIRECTORY/secrets/intermediate-key-istio-dev.pem \
    --from-file=cert-chain.pem=$ROOT_DIRECTORY/cert-chain/cert-chain-istio-dev.pem

}
MESSAGE="Checking if secret \"cacerts\" exists in name space \"istio-system\"" ; green_echo

kubectl get secret  cacerts -n istio-system && echo "exists" || echo "failed"  1> /dev/null
    
if [ $? -eq 1 ] 
then
    echo ".... Creating and uploading ...."
    func_result="$(create_upload)"
    echo $func_result
else
    echo "\"cacerts\"  exists in name space \"istio-system\""
    echo "Delete  \"cacerts\" from  name space \"istio-system\""
    kubectl delete secret  cacerts -n istio-system
    echo "Create \"cacerts\"  in name space \"istio-system\" with custom CA and upload"
    sleep 5
    func_result="$(create_upload)"
    echo $func_result
fi
# Testing
MESSAGE="Read uploaded certificate" ; green_echo
kubectl -n istio-system get secret cacerts -o=go-template='{{index .data "root-cert.pem"}}' | \
base64 -d > tmp-root-cert.pem && \
openssl x509 -in tmp-root-cert.pem -text -noout

MESSAGE="Restart \"istiod\" and \"ingress\" to pickup new certificate" ; green_echo

kubectl delete po -n istio-system -l app=istiod && \
kubectl delete po -n istio-system -l app=istio-ingressgateway && \
kubectl -n istio-system wait --for=condition=ready pod -l app=istiod && \
kubectl -n istio-system wait --for=condition=ready pod -l app=istio-ingressgateway


# We are done - Removing container 
docker rm -f smallstep &>/dev/null && echo 'We are done - container removed'
