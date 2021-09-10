#!/usr/bin/env nextflow

// Developer notes
// 
// This template workflow provides a basic structure to copy in order
// to create a new workflow. Current recommended pratices are:
//     i) create a simple command-line interface.
//    ii) include an abstract workflow scope named "pipeline" to be used
//        in a module fashion.
//   iii) a second concreate, but anonymous, workflow scope to be used
//        as an entry point when using this workflow in isolation.

import groovy.json.JsonBuilder
nextflow.enable.dsl = 2

include { fastq_ingress } from './lib/fastqingress' 

def helpMessage(){
    log.info """
Workflow template'

Usage:
    nextflow run epi2melabs/wf-template [options]

Script Options:
    --fastq        DIR     Path to FASTQ directory (required)
    --samples      FILE    CSV file with columns named `barcode` and `sample_name`
                           (or simply a sample name for non-multiplexed data).
    --out_dir      DIR     Path for output (default: $params.out_dir)
    --report_name  STR     Optional report suffix (default: $params.report_name)
"""
}


process summariseReads {
    // concatenate fastq and fastq.gz in a dir

    label "pysam"
    cpus 1
    input:
        tuple path(directory), val(sample_name)
    output:
        path "${sample_name}.stats"
    shell:
    """
    fastcat -s ${sample_name} -r ${sample_name}.stats -x ${directory} > /dev/null
    """
}


process getVersions {
    label "pysam"
    cpus 1
    output:
        path "versions.txt"
    script:
    """
    python -c "import pysam; print(f'pysam,{pysam.__version__}')" >> versions.txt
    fastcat --version | sed 's/^/fastcat,/' >> versions.txt
    """
}

process getParams {
    label "pysam"
    cpus 1
    output:
        path "params.json"
    script:
        def paramsJSON = new JsonBuilder(params).toPrettyString()
    """
    # Output nextflow params object to JSON
    echo '$paramsJSON' > params.json
    """
}

process makeReport {
    label "pysam"
    input:
        path "seqs.txt"
        path "versions/*"
        path "params.json"
    output:
        path "wf-template-*.html"
    script:
        // report naming
        report_name = "wf-template-" + params.report_name + '.html'
    """
    report.py $report_name --versions versions seqs.txt --params params.json
    """
}


// See https://github.com/nextflow-io/nextflow/issues/1636
// This is the only way to publish files from a workflow whilst
// decoupling the publish from the process steps.
process output {
    // publish inputs to output directory
    label "pysam"
    publishDir "${params.out_dir}", mode: 'copy', pattern: "*"
    input:
        path fname
    output:
        path fname
    """
    echo "Writing output files"
    """
}


// workflow module
workflow pipeline {
    take:
        reads
    main:
        summary = summariseReads(reads)
        software_versions = getVersions()
        workflow_params = getParams()
        report = makeReport(summary, software_versions.collect(), workflow_params)
    emit:
        summary.concat(report)
}

// entrypoint workflow
workflow {

    if (params.help) {
        helpMessage()
        exit 1
    }

    if (!params.fastq) {
        helpMessage()
        println("")
        println("`--fastq` is required")
        exit 1
    }

    samples = fastq_ingress(
        params.fastq, params.out_dir, params.samples, params.sanitize_fastq)

    results = pipeline(samples)
    output(results)
}
