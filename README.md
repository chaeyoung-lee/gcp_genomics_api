# Internship Report

**Intern:** Chae Young Lee (chaeyoung.lee@yale.edu)<br>
**Supervisor:** Dr. Robert Bjornson (robert.bjornson@yale.edu)<br>
Yale Center for Research Computing ([YCRC](https://research.computing.yale.edu/))

### Work Period
- 12/02/19 - 12/13/19 (2wk)
- 01/20/20 - 03/06/20 (6wk)

### Work Hours
- 11.5hrs/wk, academic year
- Thu 10:30 AM - 2:00 PM, Fri 9:00 AM - 5:00 PM.
<br>

## Table of Contents
1. [Overview](#overview)
2. [GCP](#gcp)
3. [Genomics API](#genomics-api)
4. [NextFlow](#nextflow)
<br>

# Overview

## Motivation

- Importance of batch processing in high throughput tasks
- Ex) Bioinformatics: genome alignment, variant calling

<p align="center"><img src=gcp_genomics_api/workflow.png width="600">

- More and more researchers use cloud computing services such as GCP and AWS
- AWS has AWS Batch for batch processing; however GCP doesn't

## Layout

### Goal: Run a serverless batch processing with GCP

| Subject | Duration | Tasks |
|:-:|:-:|:-|
| GCP | 1wk | - A thorough overview<br>- Resolved a few confusions |
| Genomics API | 3wk | - Direct call from batch<br>- Explored feasibility, compatibility |
| NextFlow | 4wk | - One code, multiple environments<br>- |
<br>


# GCP

### Capping costs on GCP
- Problem: GCP does not support a function that disables billing when the cost exceeds the given budget. Instead, it simply sends notifications. How can we cap costs on GCP?
- [Solution 1](https://cloud.google.com/billing/docs/how-to/notify#cap_disable_billing_to_stop_usage): caps one project, uses Cloud Function.
- [Solution 2](https://medium.com/faun/capping-costs-on-gcp-for-many-projects-with-a-budget-for-many-months-without-paying-a-penny-dc461525c2d2): caps multiple projects, separate admin project, uses Cloud Pub/Sub.

### Roles and Permissions in GCP
- **A role is a collection of permissions**. You grant roles not permissions to users.
- Roles are composed of owner (w, r, manage roles and billings), editor (w, r), and viewer (r).
- There are [predefined roles](https://cloud.google.com/iam/docs/understanding-roles#predefined_roles) that can limit roles to a specific Cloud function (e.g. app engine, billing, android management). For each function, there are basically three types of roles: owner, editor, and viewer.
<br>

# Genomics API

### What is it?
The Genomics API (now known as the "Life Sciences API") is part of Google Cloud Platform's [Cloud Life Sciences](https://cloud.google.com/life-sciences/docs/concepts/introduction), a suite of services and tools for managing, processing, and analyzing life science data. The API provides a simple way to create, run, and delete multiple Compute Engines (GCP VMs).

### Why use it?
- Can use existing life science tools to process hundreds or thousands of files.
- Can run a batch of processes without modifying the script.

However, the Life Sciences API is not the alternative of [AWS Batch](https://docs.aws.amazon.com/batch/latest/userguide/what-is-batch.html). ~Managing Compute Engines is done implicitly and it's very difficult to create complex workflows~ (This isn't true anymore with the help of WDL like NextFlow; read [tutorial](https://github.com/ycrc/intern-report-cylee/tree/master/gcp_genomics_api/nextflow)).

Recommend using the API if you are planning to use existing life science tools and docker images that GCP already provides (e.g. [GATK](https://gatk.broadinstitute.org/hc/en-us), [Sentieon](https://www.sentieon.com/)).

## Overview

<p align="center"><img src=gcp_genomics_api/architecture.png width="800">

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

<p align="center"><img src=gcp_genomics_api/scenario.png width="400">

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
<br>

# NextFlow

- Link to [Official Tutorial](https://cloud.google.com/life-sciences/docs/tutorials/nextflow) and [Official GitHub implementation](https://github.com/nextflow-io/rnaseq-nf).
- NextFlow interacts with GCP implicitly: `-work-dir` flag automatically places the work directory inside the gs bucket and save scripts, inputs, and outputs.
- The name of GCS Bucket shouldn't contain underscore and the work directory must contain a subdirectory under the bucket storage.

```bash
$ ./nextflow run rnaseq-nf -profile gls -work-dir gs://my-bucket/work
```

- NextFlow requires two components: `main.nf` and `nextflow.config`.

## Overview

### `nextflow.config`
The `nextflow.config` file contains configuration information of a profile that we set with a flag `-profile gls`, where gls refers to Google Cloud Platform. NextFlow also supports AWS and Slurm. 
```
profiles {
  gls {
      params.transcriptome = 'gs://rnaseq-nf/data/ggal/transcript.fa'
      params.reads = 'gs://rnaseq-nf/data/ggal/gut_{1,2}.fq'
      params.multiqc = 'gs://rnaseq-nf/multiqc'
      process.executor = 'google-pipelines'
      process.container = 'nextflow/rnaseq-nf:latest'
      workDir = 'gs://my-bucket/log'        // REPLACE!!
      google.region  = 'us-central1'
      google.project = 'PROJECT-ID'       // REPLACE!!
  }  
}
```
- The work directory can be also specified with the configuration file.
- Configurations with `parmas.` are parameters that are piped into the `main.nf` workflow file. 
- The `process.container` is the address of the docker container. The user can either build the docker container or specify the address of a pre-built docker from [dockerhub](https://hub.docker.com/u/nextflow).

Additionally, NextFlow allows users to use different Docker / Singularity images for different processes. To this end, add this in your profile:
```
process {
    withName:processA {
        container = 'image_name_1'
    }
    withName:processB {
        container = 'image_name_2'
    }
}
```


### `main.nf`

The `main.nf` file is the workflow file written in Groovy programming language. Each `process` corresponds to one compute engine in the GCP. The pipeline (e.g. which program outputs input data to which program) among processes can be constructed using `Channel`.
```groovy
// sample Channel
Channel
    .fromFilePairs( params.reads, checkExists:true )
    .into { read_pairs_ch; read_pairs2_ch }

// sample process
process fastqc {
    tag "FASTQC on $sample_id"
    publishDir params.outdir

    input:
    set sample_id, file(reads) from read_pairs2_ch

    output:
    file("fastqc_${sample_id}_logs") into fastqc_ch


    script:
    """
    mkdir fastqc_${sample_id}_logs
    fastqc -o fastqc_${sample_id}_logs -f fastq -q ${reads}
    """
}
```
- All scripts (commands), output files, and stderr/stdout are logged in the work directory specified through either the flag or `nextflow.config`.
- Through `publishDir params.outdir`, you can save the output of each process into `params.outdir` (either locally or on GCS Bucket).

## Nextflow in Slurm

One of the advantages of NextFlow is that you can run the same script in different environments (GCP, AWS, Slurm, Shell) without changing the script. Have a `nextflow.config` that simply specifies different environments, then you are all set to run your script in any environment.

In Slurm, the key difference from running in other environments is that you'll use [Singularity](https://journals.plos.org/plosone/article?id=10.1371/journal.pone.0177459) instead of [Docker](https://docs.docker.com/). Singularity is very much similar to Docker, it's just more suited in shared-user environments such as the clusters (where Slurm is mainly used).

Now, compare the profile of **slurm** and **GCP** in `nextflow.config`. They are almost identical.
```
profiles {
  slurm {
      process.executor = 'slurm'
      process.container = 'nextflow/rnaseq-nf:latest'       // Singularity image from Docker Hub
      singularity.enabled = true
  }
  
  gls {
      process.executor = 'google-pipelines'
      process.container = 'nextflow/rnaseq-nf:latest'     // Docker image from Docker Hub
      google.region  = 'us-central1'
      google.project = 'PROJECT-ID'
  }
}
```

## Getting Started

```shell
# Open interactive session
$ srun --pty -p interactive bash

# Singularity requires Java module
$ module load Java

# Install NextFlow
$ curl https://get.nextflow.io | bash

# Run NextFlow
$ ./nextflow run rna-seq -profile slurm
```
- Instead of running an interactive session, you can also script the whole process and run a `sbatch`.

### Using the GCS Bucket
```shell
$ export GOOGLE_APPLICATION_CREDENTIALS= ${PWD}/[GOOGLE_APPLICATION_CREDENTIALS].json
$ export NXF_MODE=google
```
- `scp` your GOOGLE_APPLICATION_CREDENTIALS to your compute node so that your system can read and write files from your GCS Bucket.
- Note that the `Singularity` image file can't be stored in a remote work directory (in this case, GCS Bucket). So do not set your `-work-dir` as your GCS Bucket.
- `NXF_MODE=google` will allow your NextFlow script to read and write files from GCS Bucket as if it's your local directory.
