#!/bin/bash
# Generates the CA certificate fixtures for JerdSystemTests. Usage: make-certificates.sh <output folder>
# Run it again only to replace every fixture; the golden JSON files embed jerd-ca.der.
set -euo pipefail
out="$1"
mkdir -p "$out"
cd "$out"
ID=6BA7B810-9DAD-11D1-80B4-00C04FD430C8
OTHER=3F2504E0-4F89-41D3-9A0C-0305E82C3301
gen() {
  openssl ecparam -name prime256v1 -genkey -noout -out "$1.key" 2>/dev/null
  printf "[req]\ndistinguished_name=dn\n[dn]\n[ext]\n$3\n" > "$1.cnf"
  openssl req -x509 -new -key "$1.key" -subj "$2" -days 36500 -config "$1.cnf" -extensions ext -outform DER -out "$1.der"
}
gen jerd-ca "/CN=Jerd Local CA $ID" "basicConstraints=critical,CA:TRUE\nkeyUsage=critical,keyCertSign,cRLSign"
gen jerd-ca-other "/CN=Jerd Local CA $OTHER" "basicConstraints=critical,CA:TRUE\nkeyUsage=critical,keyCertSign,cRLSign"
gen not-ca "/CN=Jerd Local CA $ID" "basicConstraints=critical,CA:FALSE"
gen wrong-name "/CN=Other Local CA $ID" "basicConstraints=critical,CA:TRUE"
openssl ecparam -name prime256v1 -genkey -noout -out issued.key
openssl req -new -key issued.key -subj "/CN=Jerd Local CA $ID" -config jerd-ca.cnf -out issued.csr
openssl x509 -req -in issued.csr -CA jerd-ca-other.der -CAform DER -CAkey jerd-ca-other.key -set_serial 7 \
  -days 36500 -extfile jerd-ca.cnf -extensions ext -outform DER -out not-self-issued.der
openssl x509 -inform DER -in jerd-ca.der -outform PEM -out jerd-ca.pem
for f in *.der; do echo "$f"; openssl x509 -inform DER -in "$f" -noout -subject -issuer; done
