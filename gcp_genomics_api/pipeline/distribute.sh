for x in {1..3}; do
      echo $x "."
      gcloud alpha genomics pipelines run --pipeline-file cap-distributed.yaml --logging gs://${BUCKET_ID}/logs/cap$x.log --inputs START=$x,BUCKET=gs://${BUCKET_ID}  >> operations 2>&1
done