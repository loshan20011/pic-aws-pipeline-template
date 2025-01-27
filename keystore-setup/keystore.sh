#!/bin/bash

set -e  # Exit on error
set -o pipefail  # Prevent masking of errors in pipes

# Variables
KEYSTORE_DIR="./keystore"
KEYSTORE_PASS="wso2_123"
TRUSTSTORE_PASS="wso2carbon"
KEY_ALIAS="wso2carbon"
CERT_FILE="wso2carbon.crt"
PEM_FILE="wso2carbon.pem"
KEY_FILE="wso2carbon.key"
TLS_SECRET_NAME="is-tls"
KEYSTORE_SECRET_NAME="keystores"
NAMESPACE="wso2is"

# Install Java (includes keytool)
echo "Installing Java..."
if ! sudo yum install -y java-11-openjdk-devel && ! sudo yum install -y java-17-openjdk-devel; then
    echo "Error: Unable to install Java. Exiting."
    exit 1
fi

# Ensure required tools are installed
if ! command -v keytool &> /dev/null || ! command -v openssl &> /dev/null; then
    echo "Error: 'keytool' and 'openssl' must be installed. Exiting."
    exit 1
fi

# Create namespace if it doesn't exist
if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
    echo "Creating Kubernetes namespace: $NAMESPACE"
    kubectl create namespace "$NAMESPACE"
else
    echo "Namespace '$NAMESPACE' already exists."
fi

# Create keystore directory
echo "Creating keystore directory..."
mkdir -p "$KEYSTORE_DIR"
cp ./wso2is-7.0.0/repository/resources/security/client-truststore.jks "$KEYSTORE_DIR/"

# Generate Keystore
echo "Generating keystore: internal.jks"
keytool -genkey -alias "$KEY_ALIAS" -keyalg RSA -keysize 2048 -keystore "$KEYSTORE_DIR/internal.jks" \
        -dname "CN=localhost, OU=Home, O=Home, L=SL, S=WS, C=LK" -storepass "$KEYSTORE_PASS" -keypass "$KEYSTORE_PASS" -noprompt

# Export Certificate
echo "Exporting certificate..."
keytool -exportcert -keystore "$KEYSTORE_DIR/internal.jks" -alias "$KEY_ALIAS" -file "$KEYSTORE_DIR/$CERT_FILE" -storepass "$KEYSTORE_PASS" -noprompt

# Remove existing alias in Truststore
echo "Removing old certificate from truststore..."
keytool -delete -noprompt -alias "$KEY_ALIAS" -keystore "$KEYSTORE_DIR/client-truststore.jks" -storepass "$TRUSTSTORE_PASS" || true

# Import new certificate into Truststore
echo "Importing certificate into Truststore..."
keytool -importcert -keystore "$KEYSTORE_DIR/client-truststore.jks" -alias "$KEY_ALIAS" -file "$KEYSTORE_DIR/$CERT_FILE" -storepass "$TRUSTSTORE_PASS" -noprompt

# Copy keystores
echo "Copying keystores..."
cp "$KEYSTORE_DIR/internal.jks" "$KEYSTORE_DIR/primary.jks"
cp "$KEYSTORE_DIR/internal.jks" "$KEYSTORE_DIR/tls.jks"

# Convert keystore to PKCS12 format
echo "Converting JKS to PKCS12..."
keytool -importkeystore -srckeystore "$KEYSTORE_DIR/tls.jks" -destkeystore "$KEYSTORE_DIR/tls.p12" \
        -srcstoretype JKS -deststoretype PKCS12 -srcalias "$KEY_ALIAS" -deststorepass "$KEYSTORE_PASS" -srcstorepass "$KEYSTORE_PASS" -noprompt

# Convert PKCS12 to private key
echo "Extracting private key..."
openssl pkcs12 -in "$KEYSTORE_DIR/tls.p12" -nocerts -nodes -out "$KEYSTORE_DIR/$KEY_FILE" -passin pass:"$KEYSTORE_PASS"

# Convert certificate to PEM
echo "Converting certificate to PEM..."
openssl x509 -inform der -in "$KEYSTORE_DIR/$CERT_FILE" -out "$KEYSTORE_DIR/$PEM_FILE"

# Check if TLS secret exists, create only if missing
if ! kubectl get secret "$TLS_SECRET_NAME" -n "$NAMESPACE" &>/dev/null; then
    echo "Creating Kubernetes TLS secret: $TLS_SECRET_NAME"
    kubectl create secret tls "$TLS_SECRET_NAME" --cert="$KEYSTORE_DIR/$PEM_FILE" --key="$KEYSTORE_DIR/$KEY_FILE" -n "$NAMESPACE"
else
    echo "Kubernetes TLS secret '$TLS_SECRET_NAME' already exists."
fi

# Check if Keystore secret exists, create only if missing
if ! kubectl get secret "$KEYSTORE_SECRET_NAME" -n "$NAMESPACE" &>/dev/null; then
    echo "Creating Kubernetes keystore secret: $KEYSTORE_SECRET_NAME"
    kubectl create secret generic "$KEYSTORE_SECRET_NAME" --from-file="$KEYSTORE_DIR/internal.jks" \
            --from-file="$KEYSTORE_DIR/primary.jks" --from-file="$KEYSTORE_DIR/tls.jks" \
            --from-file="$KEYSTORE_DIR/client-truststore.jks" -n "$NAMESPACE"
else
    echo "Kubernetes keystore secret '$KEYSTORE_SECRET_NAME' already exists."
fi

echo "All keystores and Kubernetes secrets have been successfully created."
