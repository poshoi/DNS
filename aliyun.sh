#!/bin/sh

set -e

if [ $1 ]; then
	ApiId=$1
fi

if [ $2 ]; then
	ApiKey=$2
fi

if [ $3 ]; then
	Domain=$3
fi

if [ -z "$ApiId" -o -z "$ApiKey" -o -z "$Domain" ]; then
	echo "����ȱʧ"
	exit 1
fi

if [ $4 ]; then
	SubDomain=$4
fi

if [ -z "$SubDomain" ]; then
	SubDomain="@"
fi

Nonce=$(date -u "+%N")	# ��bug?
Timestamp=$(date -u "+%Y-%m-%dT%H%%3A%M%%3A%SZ")	# SB ������, ʲô��ʱ���ʽ
Nonce=$Timestamp

urlencode() {
	local raw="$1";
	local len="${#raw}"
	local encoded=""

	for i in `seq 1 $len`; do
		local j=$((i+1))
		local c=$(echo $raw | cut -c$i-$i)

		case $c in [a-zA-Z0-9.~_-]) ;;
			*)
			c=$(printf '%%%02X' "'$c") ;;
		esac

		encoded="$encoded$c"
	done

	echo $encoded
}

# $1 = query string
getSignature() {
	local encodedQuery=$(urlencode $1)
	local message="GET&%2F&$encodedQuery"
	local sig=$(echo -n "$message" | openssl dgst -sha1 -hmac "$ApiKey&" -binary | openssl base64)
	echo $(urlencode $sig)
}

sendRequest() {
	local sig=$(getSignature $1)
	local result=$(wget -qO- --no-check-certificate --content-on-error "https://alidns.aliyuncs.com?$1&Signature=$sig")
	echo $result
}

getRecordId() {
	echo "��ȡ $SubDomain.$Domain �� IP..." >&2
	local queryString="AccessKeyId=$ApiId&Action=DescribeSubDomainRecords&Format=JSON&SignatureMethod=HMAC-SHA1&SignatureNonce=$Nonce&SignatureVersion=1.0&SubDomain=$SubDomain.$Domain&Timestamp=$Timestamp&Type=A&Version=2015-01-09"
	local result=$(sendRequest "$queryString")
	local code=$(echo $result | sed 's/.*,"Code":"\([A-z]*\)",.*/\1/')
	local recordId=$(echo $result | sed 's/.*,"RecordId":"\([0-9]*\)",.*/\1/')

	if [ "$code" = "$result" ] && [ ! "$recordId" = "$result" ]; then
		local ip=$(echo $result | sed 's/.*,"Value":"\([0-9\.]*\)",.*/\1/')

		if [ "$ip" == "$NewIP" ]; then
			echo "IP �ޱ仯, �˳��ű�..." >&2
			echo "quit"
		else
			echo $recordId
		fi
	else
		echo "null"
	fi
}

# $1 = record ID, $2 = new IP
updateRecord() {
	local queryString="AccessKeyId=$ApiId&Action=UpdateDomainRecord&DomainName=$Domain&Format=JSON&RR=$SubDomain&RecordId=$1&SignatureMethod=HMAC-SHA1&SignatureNonce=$Nonce&SignatureVersion=1.0&Timestamp=$Timestamp&Type=A&Value=$2&Version=2015-01-09"
	local result=$(sendRequest $queryString)
	local code=$(echo $result | sed 's/.*,"Code":"\([A-z]*\)",.*/\1/')

	if [ "$code" = "$result" ]; then
		echo "$SubDomain.$Domain ��ָ�� $NewIP." >&2
	else
		echo "����ʧ��." >&2
		echo $result >&2
	fi
}

# $1 = new IP
addRecord() {
	local queryString="AccessKeyId=$ApiId&Action=AddDomainRecord&DomainName=$Domain&Format=JSON&RR=$SubDomain&SignatureMethod=HMAC-SHA1&SignatureNonce=$Nonce&SignatureVersion=1.0&Timestamp=$Timestamp&Type=A&Value=$1&Version=2015-01-09"
	local result=$(sendRequest $queryString)
	local code=$(echo $result | sed 's/.*,"Code":"\([A-z]*\)",.*/\1/')

	if [ "$code" = "$result" ]; then
		echo "$SubDomain.$Domain ��ָ�� $NewIP." >&2
	else
		echo "���ʧ��." >&2
		echo $result >&2
	fi
}

# Get new IP address
echo "��ȡ��ǰ IP..."
NewIP=$(wget -qO- --no-check-certificate "http://members.3322.org/dyndns/getip")
echo "��ǰ IP Ϊ $NewIP."

# Get record ID of sub domain
recordId=$(getRecordId)

if [ ! "$recordId" = "quit" ]; then
	if [ "$recordId" = "null" ]; then
		echo "������¼������, ��� $SubDomain.$Domain �� $NewIP..."
		addRecord $NewIP
	else
		echo "������¼�Ѵ���, ���� $SubDomain.$Domain �� $NewIP..."
		updateRecord $recordId $NewIP
	fi
fi