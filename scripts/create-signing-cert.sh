#!/bin/bash
# この Mac でだけ使う、コード署名用の自己署名証明書をログインキーチェーンに作る（1 回だけ実行）。
#
# 毎回同じ証明書で署名すると、アプリを入れ直してもカレンダー / リマインダーの許可が引き継がれる。
# アドホック署名はビルドのたびに別のアプリ扱いになり、許可を聞き直される。
set -euo pipefail

IDENTITY="Dayo Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -p codesigning "$KEYCHAIN" | grep -q "\"$IDENTITY\""; then
    echo "証明書「${IDENTITY}」は既にあります。"
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/req.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $IDENTITY
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

# macOS 付属の openssl を使う。新しい OpenSSL が作る .p12 は security が読めないことがある。
OPENSSL=/usr/bin/openssl
# .p12 を取り込む間だけのパスワード（空だと security が取り込めない）。ファイルは終了時に消す。
P12_PASSWORD="$(uuidgen)"

"$OPENSSL" req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$WORK/req.cnf" \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" 2> /dev/null
"$OPENSSL" pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" -name "$IDENTITY" \
    -out "$WORK/identity.p12" -passout "pass:$P12_PASSWORD"

security import "$WORK/identity.p12" -k "$KEYCHAIN" -P "$P12_PASSWORD" -T /usr/bin/codesign

if ! security find-identity -p codesigning "$KEYCHAIN" | grep -q "\"$IDENTITY\""; then
    echo "証明書を取り込みましたが、コード署名用として見つかりません。" >&2
    exit 1
fi

echo "証明書「${IDENTITY}」を作りました。"
echo "初めて署名するときにキーチェーンのパスワードを聞かれたら、入力して「常に許可」を選んでください。"
