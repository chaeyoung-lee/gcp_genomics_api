# Google Life Sciences API

### What is it?
The Life Sciences API is part of Google Cloud Platform's [Cloud Life Sciences](https://cloud.google.com/life-sciences/docs/concepts/introduction), a suite of services and tools for managing, processing, and analyzing life science data. The API provides a simple way to create, run, and delete multiple Compute Engines (GCP VMs).

### Why use it?
- Can use existing life science tools to process hundreds or thousands of files.
- Can run a batch of processes without modifying the script.

However, the Life Sciences API is not the alternative of [AWS Batch](https://docs.aws.amazon.com/batch/latest/userguide/what-is-batch.html). ~Managing Compute Engines is done implicitly and it's very difficult to create complex workflows~ (This isn't true anymore with the help of WDL like NextFlow; read [tutorial](https://github.com/ycrc/intern-report-cylee/tree/master/gcp_genomics_api/nextflow)).

Recommend using the API if you are planning to use existing life science tools and docker images that GCP already provides (e.g. [GATK](https://gatk.broadinstitute.org/hc/en-us), [Sentieon](https://www.sentieon.com/)).

## Overview

<p align="center"><img src=./architecture.png width="800">

### Docker

Contains the main script (.py, .c) and sometimes the input data. We use [Google Container Builder](https://cloud.google.com/blog/products/gcp/google-cloud-container-builder-a-fast-and-flexible-way-to-package-your-software) to build a docker image in GCP. Every time the Life Sciences API creates a VM, that VM instantiates this docker image we built in the Container Registry.

GCP provides pre-built docker images for commonly used bioinformatics tools such as GATK and Sentieon. They can be accessed through known addresses:
```python3
# GATK
gcr.io/broad-dsde-outreach/wdl_runner:2019_04_15
# Sentieon DNASeq
sentieon/sentieon-google-cloud:0.2.2
```

More addresses can be found in [the official tutorial](https://cloud.google.com/life-sciences/docs/tutorials).

### Data

The input data used in the process must be present in the VM while the script is running. There are two ways to place the input data in the VM. If the data size is small enough, the easiest way is to copy them in the docker image by adding `ADD input ./input` in the `Dockerfile`. However, in most cases, input data (data to be processed) are heavy and it is inefficient to download the entire dataset in every VM that processes only a part of the dataset, let alone the storage issue.

Thus, the standard approach is to write a main script so that it downloads only the necessary part of the data. Since we're using GCP services, using GS Bucket allows you to form one of the most efficient pipelines for I/O.

After segmnting the dataset into parts that each VM will process, give the appropriate input parameter to the VM at every `run` command, which creates the VM and runs the main script. The most obvious way to do that would be by naming them with ascending numbers:
```
input_gene_00000.txt
input_gene_00001.txt
input_gene_00002.txt
...
input_gene_99999.txt
```

An example configuration to create hundred VMs, each processing hundred texts, is
```
for x in {0..100}; do
    ...   --inputs START=$((x*100 + 1)),END=$(((x+1)*100))
done
```

The output data, on the other handn, **must** be written in GS Bucket. You can either directly write files to GS Bucket or print the output in `stdout`. All data in `stdout` and `stderr` will be stored in GS Bucket if you give a flag `--logging gs://${BUCKET_ID}/logs/cap$x.log`.

### Local

The local machine is where the `run` command call the API (this creates the VM, automatically deletes it when the process is complete). Note that every VM requires a configuration file in the `.yaml` format containing two fields: `inputParameters` and `docker`. Add a flag `--pipeline-file primes.yaml` when running the `run` command. The script is to simply call the `run` command multiple times with varying input parameters.


## Getting Started

Here is an example scenario of using the Life Sciences API: create a python script `cap.py` that capitalizes the input text file. The scenario is to allocate one VM for each input file and capitalize it.

<p align="center"><img src=./scenario.png width="400">

### 1. Write a script.

The first step is to write the main script `cap.py`. The main script is what runs in every VM. So to make it process different input files, the script must be parametrized through system argument. In this example, the number to specify the input file `input#.txt` is acquired as system argument.

```Python3
import sys, glob

# read file
file = 'input/input{}.txt'.format(sys.argv[1])
text = open(file, 'r').read()
text = text.upper()

# output file
print(text)
output = 'output/output{}.txt'.format(sys.argv[1])
with open(output, 'w') as f:
	f.write(text)
```

The output of this process, the capitalized text, can be retrieved in two ways:
- The text is printed to `stdout`, and we can retrieve `stdout` in the GCS Bucket log directory.
- `output/output#.txt` will be uploaded to the GCS Bucket output directory.


### 2. Create a GCS Bucket.

Create a GCS Bucket to store the input/output files and log data. The API automatically logs `stdout` and `stderr` of each run in the GCS Bucket when specified through a `--logging` flag later in the `run` command.

```bash
$ export BUCKET_ID="str_bucket"
$ gsutil mb gs://${BUCKET_ID}
```

### 3. Build a Docker Image.

Create a `Dockerfile` to build a Python 3 environment. To download and upload files from GCS Bucket, we will use `gsutil` from Google-Cloud-SDK.

```docker
FROM python:3

# Install gsutil
RUN apt-get update && \
    apt-get install -y \
        curl \
        python-pip \
        gcc \
        lsb-release && \
    export CLOUD_SDK_REPO="cloud-sdk-$(lsb_release -c -s)" && \
    echo "deb http://packages.cloud.google.com/apt $CLOUD_SDK_REPO main" | tee -a /etc/apt/sources.list.d/google-cloud-sdk.list && \
    curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add - && \
    apt-get update && apt-get install -y google-cloud-sdk && \
    pip install crcmod

WORKDIR /root
ADD cap.py cap.py
RUN mkdir -p input output

CMD ["python", "/root/cap.py", "1"]
```

Then use Google Container Builder to register your docker image in GCP.

```bash
$ gcloud builds submit --tag gcr.io/[PROJECT_ID]/str-image .
```


### 4. Run the code in the pipeline.

The `pipeline/cap-distributed.yaml` file configures the address of the docker image, run command, and input parameters. Note that the command line in this file first download the required input files from the GCS Bucket, run the Python script, and upload the output files to the GCS Bucket. To handle multiple files, simply 

```yaml
name: cap-distributed
inputParameters:
  - name: START
    defaultValue: "1"
  - name: BUCKET
    defaultValue: "gs://str_bucket"
docker:
  imageName: gcr.io/chae-project-61147/str-image:latest
  cmd: "gsutil cp ${BUCKET}/input/input${START}.txt ./input
  && python /root/cap.py ${START}
  && gsutil cp ./output/output${START}.txt ${BUCKET}/output/output${START}.txt"
```

To run a batch of processes, a .yaml file needs input parameters (in this scenario, `START` and `BUCKET`). `START` lets each process to handle a different range of numbers and `BUCKET` is the address to the GCS Bucket, which will contain input and output files. To this end, write a bash file `distribute.sh`, which launches the job with different `START` values.
```bash
for x in {1..3}; do
      echo $x "."
      gcloud alpha genomics pipelines run --pipeline-file cap-distributed.yaml --logging gs://${BUCKET_ID}/logs/cap$x.log --inputs START=$x,BUCKET=gs://${BUCKET_ID}  >> operations 2>&1
done
```

### 5. Monitor the progress.

When the `gcloud alpha genomics pipelines run` command is called, a file `operations` is created in the working directory. This file contains the operation ID of each process, where x's are the operation ID.
```
Running [operations/xxxxxxxxxxxxxxxxxxxxxxxxxx].
```

Using the operation ID, You can monitor the progress of each operation.
```bash
$ gcloud alpha genomics operations describe [OPERATION_ID]
```

You can list all operations you've performed by using different filters in the `operations list` command. Examples of such filters can be found [here](https://cloud.google.com/sdk/gcloud/reference/alpha/genomics/operations/list).
```bash
$ gcloud alpha genomics operations list --where='status = RUNNING'
```

After the operation is complete, the output can be accessed by either the [web console](https://console.cloud.google.com/storage) or:
```bash
$ gsutil cat gs://${BUCKET_ID}/logs/cap1-stdout.log
$ gsutil cat gs://${BUCKET_ID}/output/output1.txt

```
