<p align="center">
  <img src="https://raw.githubusercontent.com/cert-manager/cert-manager/d53c0b9270f8cd90d908460d69502694e1838f5f/logo/logo-small.png" height="256" width="256" alt="cert-manager project logo" />
  <br>
  <a href="https://godoc.org/github.com/cert-manager/csi-driver-spiffe"><img src="https://godoc.org/github.com/cert-manager/csi-driver-spiffe?status.svg"></a>
  <a href="https://goreportcard.com/report/github.com/cert-manager/csi-driver-spiffe"><img alt="Go Report Card" src="https://goreportcard.com/badge/github.com/cert-manager/csi-driver-spiffe" /></a>
</p>


Hello KubeCon Amsterdam 2023! 👋

This repo contains a fork of the upstream [cert-manager
csg-driver-spiffe](https://github.com/cert-manager/csi-driver-spiffe) repo with
additions to generate an AWS client using the returned SVID.

Installation is the [same (including installing
cert-manager)](https://cert-manager.io/docs/projects/csi-driver-spiffe/#installation),
except for the image name and tag. Remember to disable the default approver in
cert-manager!:

```bash
helm upgrade -i -n cert-manager cert-manager-csi-driver-spiffe jetstack/cert-manager-csi-driver-spiffe --wait \
 --set image.tag=aws \
 --set image.repository.driver=ghcr.io/joshvanl/cert-manager-csi-driver \
 --set image.repository.approver=ghcr.io/joshvanl/cert-manager-csi-driver-approver \
 --set "app.logLevel=1" \
 --set "app.trustDomain=my.trust.domain" \
 --set "app.approver.signerName=clusterissuers.cert-manager.io/csi-driver-spiffe-ca" \
 \
 --set "app.issuer.name=csi-driver-spiffe-ca" \
 --set "app.issuer.kind=ClusterIssuer" \
 --set "app.issuer.group=cert-manager.io"
 ```

 To create an AWS credentials file, you must provide the following Volume
 Attributes to volume definition in the Pod template/spec:

```
      volumes:
        - name: spiffe
          csi:
            driver: spiffe.csi.cert-manager.io
            readOnly: true
            volumeAttributes:
              aws.spiffe.csi.cert-manager.io/trust-profile: "" # ARN of the trust profile
              aws.spiffe.csi.cert-manager.io/trust-anchor: "" # ARN of the trust anchor
              aws.spiffe.csi.cert-manager.io/role: "" # ARN of the role to assume
              aws.spiffe.csi.cert-manager.io/enable: "true"
```

You can find an example deployment in the
[`./deploy/example/example-app.yaml`](./deploy/example/example-app.yaml).

You can find more information on how to configure trust between your CA and AWS
in the ["Roles Anywhere"
documentation](https://docs.aws.amazon.com/rolesanywhere/latest/userguide/trust-model.html).
For the demo I used the following Role Trust Relationship and Trust Profile Session Policy:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "rolesanywhere.amazonaws.com"
            },
            "Action": [
                "sts:AssumeRole",
                "sts:TagSession",
                "sts:SetSourceIdentity"
            ],
            "Condition": {
                "StringLike": {
                    "aws:PrincipalTag/x509SAN/URI": "spiffe://cert-manager.kubecon2023/ns/*/sa/*"
                },
                "ArnEquals": {
                    "aws:SourceArn": "arn:aws:rolesanywhere:eu-west-3:xxxx:trust-anchor/xxxx"
                }
            }
        }
    ]
}
```

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
          "Sid":"statement1",
          "Effect": "Allow",
          "Action": [
            "s3:PutObject",
            "s3:PutObjectAcl",
            "s3:GetObject",
            "s3:GetObjectAcl"
          ],
          "Resource": [
              "arn:aws:s3:::kubecon-2023-spiffe-demo",
              "arn:aws:s3:::kubecon-2023-spiffe-demo/*"
          ],
          "Condition": {
              "StringLike": {
                  "aws:PrincipalTag/x509SAN/URI": "spiffe://cert-manager.kubecon2023/ns/app-a/sa/*"
              }
          }
        },
        {
          "Sid":"statement2",
          "Effect": "Allow",
          "Action": [
            "s3:GetObject",
            "s3:GetObjectAcl"
          ],
          "Resource": [
              "arn:aws:s3:::kubecon-2023-spiffe-demo",
              "arn:aws:s3:::kubecon-2023-spiffe-demo/*"
          ],
          "Condition": {
              "StringLike": {
                  "aws:PrincipalTag/x509SAN/URI": "spiffe://cert-manager.kubecon2023/ns/app-b/sa/*"
              }
          }
        }
    ]
}
```

