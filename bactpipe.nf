#!/usr/bin/env nextflow
// vim: syntax=groovy expandtab

nextflow.enable.dsl = 2

//================================================================================
// Constants
//================================================================================

BACTPIPE_VERSION = '3.E'

//================================================================================
// Log info
//================================================================================


log.info "".center(60, "=")
log.info "BACTpipe".center(60)
log.info "Version ${BACTPIPE_VERSION}".center(60)
log.info "Bacterial whole genome analysis pipeline".center(60)
log.info "https://bactpipe.readthedocs.io".center(60)
log.info "".center(60, "=")

params.help = false

//================================================================================
// Include modules and (soft) override module-level parameters
//================================================================================


include { ASSEMBLY_STATS } from "./modules/assembly_stats/assembly_stats.nf"
include { FASTP } from "./modules/fastp/fastp.nf"
include { MULTIQC } from "./modules/multiqc/multiqc.nf"
include { PROKKA } from "./modules/prokka/prokka.nf"
include { SCREEN_FOR_CONTAMINANTS } from "./modules/screen_for_contaminants/screen_for_contaminants.nf"
include { SHOVILL } from "./modules/shovill/shovill.nf"
include { printHelp; printSettings } from "./modules/utils/utils.nf"


//================================================================================
// Pre-flight checks and info
//================================================================================

if (workflow['profile'] in params.profiles_that_require_project) {
    if (!params.project) {
        log.error "BACTpipe requires that you set the 'project' parameter when running the ${workflow['profile']} profile.\n".center(60) +
                "Specify --project <project_name> on the command line, or tuple it in a custom configuration file.".center(60)
        exit(1)
    }
}

if (params.help) {
    printHelp()
    exit(0)
}


printSettings()


//================================================================================
// Prepare channels
//================================================================================

// If sra_ids are not specified by params, fallback to the default behavior of reading from filesystem.
if (!params.sra_ids) {

    fastp_input = Channel.fromFilePairs(params.reads)

    fastp_input
            .ifEmpty {
                log.error "Cannot find any reads matching: '${params.reads}'\n\n" +
                        "Did you specify --reads 'path/to/*_{1,2}.fastq.gz'? (note the single quotes)\n" +
                        "Specify --help for a summary of available commands."
                printHelp()
                exit(1)
            }

} else {

    if (!params.ncbi_api_key) {
        log.error "Please specify the API key via ncbi_api_key param."
        exit(1)
    }

    // Use a YML file to enumerate these IDs and pass it via -params-file option for the Nextflow CLI
    fastp_input = Channel.fromSRA(params.sra_ids, apiKey: params.ncbi_api_key)
}

//================================================================================
// Main workflow
//================================================================================


workflow {

    FASTP(fastp_input)
    SHOVILL(FASTP.out.shovill_input)
    SCREEN_FOR_CONTAMINANTS(SHOVILL.out[0])
    PROKKA(SHOVILL.out[0])
    ASSEMBLY_STATS(SHOVILL.out[0])
    MULTIQC(FASTP.out.fastp_reports.collect(),
            PROKKA.out.collect()
    )


}

//================================================================================
// Workflow onComplete action
//================================================================================


workflow.onComplete {
    log.info "".center(60, "=")
    if (workflow.success) {
        log.info "BACTpipe workflow completed without errors".center(60)
    } else {
        log.error "Oops .. something went wrong!".center(60)
    }
    log.info "Check output files in folder:".center(60)
    log.info "${params.output_dir}".center(60)
    log.info "".center(60, "=")
}

