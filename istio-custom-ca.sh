
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
    echo "  -e=                  --env=                      - Targetenvironment (dev, prd)."
    echo "  -c=                  --cluster-name=             - Cluster Name (e.g my-eks-dev)"
    echo "  -key_id=             --aws_access_key_id=        - AWS access key"
    echo "  -access_key=         --aws_secret_access_key=    - AWS secret key"
    echo "  -f                   --force                     - Force the operation (don't wait for user input)"
    echo ""
    echo "If AWS credentials already added to the environment (cat ~/.aws/credentials) we can leave blank  the [-key_id=] and [-access_key=] parameters"
    echo "Example usage: ./$(basename $0) -e=dev -c=tp-dev -r=us-east-1  -key_id= -access_key="
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
    -e=*|--env=*)
    ENV_NAME="${i#*=}"
    shift # past argument=value
    ;;
    -c=*|--cluster-name=*)
    EKS_CLUSTER_NAME="${i#*=}"
    shift # past argument=value
    ;;
    -r=*|--default-region=*)
    AWS_REGION="${i#*=}"
    shift # past argument=value
    ;;
    -key_id=*|--aws_access_key_id=*)
    AWS_ACCESS_KEY_ID="${i#*=}"
    shift # past argument=value
    ;;
    -access_key=*|--aws_secret_access_key=*)
    AWS_SECRET_ACCESS_KEY="${i#*=}"
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
 if [ -z "${EKS_CLUSTER_NAME}" ]; then
    echoerr "EKS cluster name required! "
    print_usage
    exit 1
 fi
 if [ -z "$AWS_REGION" ]; then
    echoerr "Error: AWS_REGION is not set"
    print_usage
    exit 1
fi
if [ -z "${ENV_NAME}" ]; then
    echoerr "Target environment not selected!"
    print_usage
    exit 1
elif [[ "${ENV_NAME}" != "dev" && "${ENV_NAME}" != "prd" ]]; then
    echoerr "Unsupported environment: ${ENV_NAME} , supported ([dev] or [prd]) "
    exit 1
fi


 # recreate the container with the configuration directory contains setup files and aws credentials.

CONTAINER_ID=$(\
docker run  \
  -v ~/.aws/credentials:/root/.aws/credentials:ro \
  -v $MYPATH/environments/$ENV_NAME:/root/environments/$ENV_NAME \
  -e AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} \
  -e AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY} \
  -t -d testproject-aws-tools \
  ) &&  echo "Container running with id: $CONTAINER_ID"

# Connect container to proper EKS server
docker exec $CONTAINER_ID bash -c "\
source /etc/profile \
&& rm -f ~/.kube/config \
&& echo Updating K8S Environment... \
&& aws eks update-kubeconfig --name $EKS_CLUSTER_NAME --region us-east-1 \
&& kubectl get nodes
"

echo $CONTAINER_ID
echo $COMMON_NAME
# Function
# Create \"cacerts\"  in name space \"istio-system\" with custom CA and upload 
create_upload() {
    docker exec -it $CONTAINER_ID bash \
    -c "kubectl create secret generic cacerts -n istio-system \
    --from-file=root-cert.pem=environments/$ENV_NAME/ROOT-CA/certs/root-cert-eks-dev.pem \
    --from-file=ca-cert.pem=environments/$ENV_NAME/ROOT-CA/certs/intermediate-cert-eks-dev.pem \
    --from-file=ca-key.pem=environments/$ENV_NAME/ROOT-CA/secrets/intermediate-key-eks-dev.pem \
    --from-file=cert-chain.pem=environments/$ENV_NAME/ROOT-CA/cert-chain/cert-chain-eks-dev.pem"

}

MESSAGE="Checking if secret \"cacerts\" exists in name space \"istio-system\"" ; green_echo

docker exec -it $CONTAINER_ID bash \
-c "kubectl get secret  cacerts -n istio-system && echo \"exists\" || echo \"failed\""  1> /dev/null
    
if [ $? -eq 1 ] 
then
    echo ".... Creating and uploading ...."
    func_result="$(create_upload)"
    echo $func_result
else
    echo "\"cacerts\"  exists in name space \"istio-system\""
    echo "Delete  \"cacerts\" from  name space \"istio-system\""
    docker exec -it $CONTAINER_ID bash \
    -c "kubectl delete secret  cacerts -n istio-system"
    echo "Create \"cacerts\"  in name space \"istio-system\" with custom CA and upload"
    sleep 5
    func_result="$(create_upload)"
    echo $func_result
fi

# Testing
MESSAGE="Read uploaded certificate" ; green_echo
docker exec -it $CONTAINER_ID bash \
-c "kubectl -n istio-system get secret cacerts -o=go-template='{{index .data \"root-cert.pem\"}}' | \
base64 -d > tmp-root-cert.pem && \
openssl x509 -in tmp-root-cert.pem -text -noout" 

MESSAGE="Restart \"istiod\" and \"ingress\" to pickup new certificate" ; green_echo
docker exec -it $CONTAINER_ID bash \
-c "kubectl delete po -n istio-system -l app=istiod && \
kubectl delete po -n istio-system -l app=istio-ingressgateway && \
kubectl -n istio-system wait --for=condition=ready pod -l app=istiod && \
kubectl -n istio-system wait --for=condition=ready pod -l app=istio-ingressgateway
"

# We are done - Removing container 
docker rm -f eks-cluster &>/dev/null && echo 'We are done - container removed'
