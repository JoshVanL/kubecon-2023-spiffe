/*
Copyright 2021 The cert-manager Authors.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package aws

import (
	"crypto"
	"crypto/ecdsa"
	"crypto/tls"
	"crypto/x509"
	"errors"
	"fmt"
	"net/http"
	"runtime"

	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/arn"
	"github.com/aws/aws-sdk-go/aws/request"
	"github.com/aws/aws-sdk-go/aws/session"
	awssh "github.com/aws/rolesanywhere-credential-helper/aws_signing_helper"
	"github.com/aws/rolesanywhere-credential-helper/rolesanywhere"

	"github.com/cert-manager/csi-driver-spiffe/internal/version"
)

type Options struct {
	TrustAnchorArn string
	ProfileArn     string
	RoleArn        string

	CertificateChainPEM      string
	CertificateLeaf          *x509.Certificate
	CertificateIntermediates []x509.Certificate
	PrivateKey               crypto.PrivateKey
	DurationSeconds          int64
}

// BuildProfile returns a string containing the AWS credentials file profile
// for the given options.
// Intended to be written to file.
func BuildProfile(opts Options) ([]byte, error) {
	credentials, err := credentials(opts)
	if err != nil {
		return nil, fmt.Errorf("failed to fetch credentials: %w", err)
	}

	profile := []byte("[default]\n")
	for key, value := range credentials {
		profile = append(profile, []byte(key+"="+value+"\n")...)
	}

	return profile, nil
}

// credentials returns a map of AWS credentials for the given options.
// The map is a set of key-value pairs which can be written to a profile in the
// AWS credentials file.
func credentials(opts Options) (map[string]string, error) {
	if len(opts.CertificateChainPEM) == 0 ||
		opts.CertificateLeaf == nil ||
		opts.PrivateKey == nil ||
		opts.DurationSeconds <= 0 ||
		opts.TrustAnchorArn == "" ||
		opts.ProfileArn == "" {
		return nil, errors.New("missing required options")
	}

	// assign values to region and endpoint if they haven't already been assigned
	trustAnchorArn, err := arn.Parse(opts.TrustAnchorArn)
	if err != nil {
		return nil, err
	}

	profileArn, err := arn.Parse(opts.ProfileArn)
	if err != nil {
		return nil, err
	}

	if trustAnchorArn.Region != profileArn.Region {
		return nil, errors.New("trust anchor and profile must be in the same region")
	}

	mySession, err := session.NewSession()
	if err != nil {
		return nil, err
	}

	key, ok := opts.PrivateKey.(*ecdsa.PrivateKey)
	if !ok {
		return nil, errors.New("private key must be an ECDSA key")
	}

	client := &http.Client{Transport: &http.Transport{
		TLSClientConfig: &tls.Config{MinVersion: tls.VersionTLS12},
	}}
	config := aws.NewConfig().WithRegion(trustAnchorArn.Region).WithHTTPClient(client).WithLogLevel(aws.LogOff)
	rolesAnywhereClient := rolesanywhere.New(mySession, config)

	rolesAnywhereClient.Handlers.Build.RemoveByName("core.SDKVersionUserAgentHandler")
	rolesAnywhereClient.Handlers.Build.PushBackNamed(request.NamedHandler{Name: "v4x509.CredHelperUserAgentHandler", Fn: request.MakeAddToUserAgentHandler("aws.spiffe.csi.cert-manager.io", version.String, runtime.Version(), runtime.GOOS, runtime.GOARCH)})
	rolesAnywhereClient.Handlers.Sign.Clear()
	rolesAnywhereClient.Handlers.Sign.PushBackNamed(request.NamedHandler{Name: "v4x509.SignRequestHandler", Fn: awssh.CreateSignFunction(*key, *opts.CertificateLeaf, opts.CertificateIntermediates)})

	createSessionRequest := rolesanywhere.CreateSessionInput{
		Cert:               &opts.CertificateChainPEM,
		ProfileArn:         &opts.ProfileArn,
		TrustAnchorArn:     &opts.TrustAnchorArn,
		DurationSeconds:    &opts.DurationSeconds,
		InstanceProperties: nil,
		RoleArn:            &opts.RoleArn,
		SessionName:        nil,
	}
	output, err := rolesAnywhereClient.CreateSession(&createSessionRequest)
	if err != nil {
		return nil, fmt.Errorf("failed to create session: %w", err)
	}

	if len(output.CredentialSet) == 0 {
		return nil, errors.New("unable to obtain temporary security credentials from CreateSession")
	}

	credentials := output.CredentialSet[0].Credentials
	// TODO: @joshvanl
	fmt.Printf("GOT EXPERATION: %s\n", *credentials.Expiration)
	return map[string]string{
		"aws_access_key_id":     *credentials.AccessKeyId,
		"aws_secret_access_key": *credentials.SecretAccessKey,
		"aws_session_token":     *credentials.SessionToken,
	}, nil
}
