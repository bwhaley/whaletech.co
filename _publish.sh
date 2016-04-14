#!/bin/bash

# Run Jekyll
echo "-> Running Jekyll"
bundle exec jekyll build

# Upload to S3!
echo "\n\n-> Uploading to S3"

# Sync media files first (Cache: expire in 10weeks)
echo "\n--> Syncing media files..."
s3cmd sync --acl-public --exclude '*.*' --include '*.png' --include '*.jpg' --include '*.ico' --add-header="Expires: Sat, 20 Nov 2020 18:46:39 GMT" --add-header="Cache-Control: max-age=6048000"  _site/ s3://www.whaletech.co/

# Sync Javascript and CSS assets next (Cache: expire in 1 week)
echo "\n--> Syncing .js and .css files..."
s3cmd sync --acl-public --exclude '*.*' --include  '*.css' --include '*.js' --add-header="Cache-Control: max-age=604800"  _site/ s3://www.whaletech.co

# Sync html files (Cache: 2 hours)
echo "\n--> Syncing .html"
s3cmd sync --acl-public --exclude '*.*' --include  '*.html' --add-header="Cache-Control: max-age=7200, must-revalidate"  _site/ s3://www.whaletech.co

# Sync everything else, but ignore the assets!
echo "\n--> Syncing everything else"
s3cmd sync --acl-public --exclude '.DS_Store' --exclude 'assets/'  _site/ s3://www.whaletech.co/

# Sync: remaining files & delete removed
s3cmd sync --acl-public --delete-removed  _site/ s3://www.whaletech.co/

# Invalidate the cloudformation distribution to force a refresh
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