#!/bin/bash

# Upload to S3!
printf "\n-> Uploading to S3"

printf "\n--> Syncing"
s3cmd sync --acl-public --exclude '*.*' --include 'index.html' . s3://www.whaletech.co
s3cmd sync --acl-public assets/ s3://www.whaletech.co/assets/
s3cmd sync --acl-public archive/ s3://www.whaletech.co/archive/

# Invalidate the cloudfront distribution to force a refresh
distribution_id="EIE5WI5MRUPL5"
invalidation_batch_file="/tmp/batch.json"
cat << EOF > ${invalidation_batch_file}
{
  "Paths": {
    "Quantity": 1,
    "Items": ["/*"]
  },
  "CallerReference": "my-invalidation-$(date +%s)"
}
EOF
aws cloudfront create-invalidation  --distribution-id ${distribution_id} --invalidation-batch file://${invalidation_batch_file}
rm ${invalidation_batch_file}
