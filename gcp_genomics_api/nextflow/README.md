# NextFlow

- Link to [Official Tutorial](https://cloud.google.com/life-sciences/docs/tutorials/nextflow) and [Official GitHub implementation](https://github.com/nextflow-io/rnaseq-nf).
- NextFlow interacts with GCP implicitly: `-work-dir` flag automatically places the work directory inside the gs bucket and save scripts, inputs, and outputs.
- The name of GCS Bucket shouldn't contain underscore (_) and the work directory must contain a subdirectory under the bucket storage.

```bash
$ ./nextflow run rnaseq-nf -profile gls -work-dir gs://my-bucket/work
```

- NextFlow requires two components: `main.nf` and `nextflow.config`.

## `nextflow.config`
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


## `main.nf`

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

## Nextflow in Slurm (Clusters)

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

### Getting Started
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

### Using GCS Bucket
```shell
$ export GOOGLE_APPLICATION_CREDENTIALS= ${PWD}/[GOOGLE_APPLICATION_CREDENTIALS].json
$ export NXF_MODE=google
```
- `scp` your GOOGLE_APPLICATION_CREDENTIALS to your compute node so that your system can read and write files from your GCS Bucket.
- Note that the `Singularity` image file can't be stored in a remote work directory (in this case, GCS Bucket). So do not set your `-work-dir` as your GCS Bucket.
- `NXF_MODE=google` will allow your NextFlow script to read and write files from GCS Bucket as if it's your local directory.
