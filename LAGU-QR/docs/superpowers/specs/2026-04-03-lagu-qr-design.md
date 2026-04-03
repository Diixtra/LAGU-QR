# LAGU-QR Design

**Date:** 2026-04-03
**Status:** Draft
**Author:** James + Claude

## Problem

A friend's wedding reception programme keeps changing. Guests need a way to always see the latest version. Reprinting is impractical — a QR code on physical materials (invitations, table cards) must point to a stable URL that always serves the current programme image.

## Solution

A QR code that points to a single image file on S3. The image is replaceable via a simple drag-and-drop upload page backed by a Lambda. All infrastructure is provisioned by a Crossplane XRD claim, reconciled by Flux from this repo.

## Architecture

### Two User Flows

**Guest flow:** Scan QR code → browser loads S3 object URL → image renders natively. No HTML wrapper, no server.

**Upload flow:** Friend opens API Gateway URL → Lambda serves a drag-and-drop upload page → on file drop, JS calls `/presign` endpoint → Lambda returns a pre-signed S3 PUT URL (5-minute expiry) → browser uploads directly to S3 → overwrites `programme.jpeg` in place.

### AWS Resources

All provisioned by a single Crossplane `ImageHosting` claim:

| Resource | Purpose |
|----------|---------|
| S3 Bucket | Hosts `programme.jpeg` with public read on that key |
| Lambda | Serves upload page (`GET /`) and generates pre-signed URLs (`GET /presign`) |
| API Gateway HTTP API | Fronts the Lambda |
| IAM Role + Policy | Lambda permissions: `s3:PutObject`, `s3:GetObject` on the bucket |

### Two Stable URLs

- **View URL** (QR code target): `https://<bucket>.s3.eu-west-2.amazonaws.com/programme.jpeg`
- **Upload URL** (bookmarked by friend): `https://<api-id>.execute-api.eu-west-2.amazonaws.com/`

## Repo Split

### diixtra-forge (platform)
- `ImageHosting` XRD definition
- `ImageHosting` Composition (provisions S3 + Lambda + API Gateway + IAM)
- Flux `GitRepository` + `Kustomization` source pointing at LAGU-QR repo
- Crossplane AWS provider (already exists)

### LAGU-QR (this repo)
- `ImageHosting` claim YAML
- Lambda source code (single file)
- QR code generation script (one-time local use)

Flux reconciles the claim from this repo. The XRD/Composition in forge must exist before the claim can be applied.

## Lambda Design

Single file, no external dependencies (AWS SDK included in runtime). Two routes on the same API Gateway:

- **`GET /`** — Returns inline HTML: a drag-and-drop upload page. No framework, no build step. On file selection, JS calls `/presign`, then PUTs the file directly to S3. Shows success message on completion.
- **`GET /presign`** — Returns JSON: `{ "url": "<pre-signed PUT URL>", "key": "programme.jpeg" }`. Pre-signed URL expires after 5 minutes.

## Upload Page

Minimal inline HTML served by the Lambda response. Features:

- Drag-and-drop zone or file picker button
- Calls `/presign` on file selection
- Uploads directly from browser to S3 via pre-signed URL
- Success message: "Programme updated!"
- No authentication — the API Gateway URL itself is the access control (only people with the link can upload)

## File Management

- Fixed object key: `programme.jpeg`
- S3 PutObject overwrites in place — no old files to clean up
- No versioning needed

## QR Code

Generated once locally after the S3 bucket is provisioned and the view URL is known. CLI tool (`qrencode`) or Python library. Output is an image file sent to the friend for printing.

## Crossplane XRD

### Claim Interface

```yaml
apiVersion: platform.diixtra.com/v1alpha1
kind: ImageHosting
metadata:
  name: lagu-wedding
spec:
  region: eu-west-2
  objectKey: programme.jpeg
```

### Status Output

The claim status exposes the provisioned URLs:

```yaml
status:
  viewURL: https://<bucket>.s3.eu-west-2.amazonaws.com/programme.jpeg
  uploadURL: https://<api-id>.execute-api.eu-west-2.amazonaws.com/
```

### Composition

The `ImageHosting` Composition provisions:

1. **S3 Bucket** — `provider-aws` `Bucket` resource. Bucket policy grants public `GetObject` on the `programme.jpeg` key only.
2. **Lambda Function** — `provider-aws` `Function` resource. Runtime: Python 3.12. Code packaged as a zip in this repo and referenced by the Composition via S3. Flux reconciles the claim; the Lambda zip is uploaded to the same S3 bucket under a `lambda/` prefix.
3. **API Gateway HTTP API** — `provider-aws` `API` resource with Lambda integration.
4. **IAM Role** — `provider-aws` `Role` resource with trust policy for Lambda, and inline policy for `s3:PutObject` + `s3:GetObject` on the bucket.

## Security

- S3 bucket is not fully public — only `GetObject` on the specific object key
- Upload page has no authentication; the API Gateway URL is shared only with the friend
- Pre-signed upload URLs expire after 5 minutes
- Lambda IAM role is scoped to the single bucket

## Region

`eu-west-2` (London)
