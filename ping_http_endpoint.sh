#"http://crvw.tck6.ws.api.hmhco.com/services/DashboardManagementService.DashboardManagementServiceHttpSoap12Endpoint/fetchOrgEntitlements?wsdl"

URL=$1
TIMEOUT=$2

trap finish INT

function curl_endpoint {
    wait_timeout=$2
    ctime=$(date "+%H:%M:%S")
    status_code=$(timeout $wait_timeout curl -s -o /dev/null -w "%{http_code}\n" -I -X GET "$1")
    if [[ $status_code == "200" ]]; then
        echo -n "."
    else
        echo -n "!"
    fi
}

function finish() {
    echo
    date -R
    exit 0
}

date -R
while true; do
    curl_endpoint $URL $TIMEOUT
    #sleep 1
done
