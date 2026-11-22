# H2 paper module

The main report source is now **H2.Rmd**. It includes all R analysis functions, methods text, results tables and figures in one document. It can be knitted without run_h2_paper.R or build_report.py. Open it in RStudio and click Knit to PDF. PDF is the default and only configured output format. The selected LaTeX engine is Tectonic, which downloads its TeX resources on first use.

With the folder uploaded as H2 alongside Prepared Data, render it from the repository root with the following command after installing rmarkdown, knitr, data.table, igraph and sandwich.

    Rscript -e 'rmarkdown::render("H2/H2.Rmd", output_format="pdf_document")'

PDF rendering requires Pandoc, which RStudio supplies, and the Tectonic engine on PATH. Set the data_dir and output_dir parameters to override the automatically detected prepared-data location and the output folder. The R Markdown PDF is output/H2.pdf. The earlier separately formatted PDF is output/H2 Paper Results.pdf.

This folder presents the original H2 specification on the cleaned repository data as a standalone research module. It contains one standalone R script, machine-readable estimates, manuscript text, regression tables, three sets of figures and a four-page results PDF.

## Run

From the workspace root, run the following command.

    Rscript "H2 Local Run/Paper Style/run_h2_paper.R"

On this machine, Rscript is at C:/Program Files/R/R-4.6.1/bin/Rscript.exe. Required packages are data.table, igraph and sandwich. The runner uses the workspace .r-library if present. Dependencies are not installed automatically.

The default input is the local repository snapshot in tmp/H2-repository-2026-11-22/Prepared Data. Specify another prepared-data folder and output destination to use the module on another machine.

    Rscript "path/to/run_h2_paper.R" "path/to/Prepared Data" "path/to/output"

Render the results PDF after running R with the bundled Python runtime or another Python environment with reportlab installed.

    python "H2 Local Run/Paper Style/build_report.py"

The PDF builder formats R-generated results. Statistical estimation and all figure creation use R. The PDF renderer currently uses the Arial fonts installed on Windows.

## Merge with H1 and H3

- Copy output/h2_manuscript_insert.md into the group write-up and edit to fit the shared word budget.
- Use output/h2_regression_table.md for the complete four-model table.
- Append output/h2_coefficients.csv or h2_estimates.csv to combined project tables. They use hypothesis, sample, primary, outcome, term, estimate, standard_error, ci_low, ci_high, p_value, n and adjusted_r2 columns.
- p_value contains the unadjusted two-sided value. p_holm_h2 adjusts only the two H2 outcomes within a sample. Apply the final project-wide correction to the agreed primary tests after combining hypotheses.
- All figures have H2_F1-H2_F3 filenames and both vector PDF and PNG formats. Captions in the PDF explain selection and inference.
- Both network panels use the same five artists. Display credits and artist IDs are exported for verification. Their small illustrative sample is separate from the model samples.
- The standalone script contains the sample construction, regression models, figures and exports in one file. The analysis has no automatic execution when sourced. A parent R script can source run_h2_paper.R and call run_h2_paper(data_dir, output_dir). Package dependencies must be available in the parent's library paths.
- Outputs use H2 prefixes and caller-specified paths so they can coexist with other hypothesis modules.

## Findings and limits

Full-catalogue brokerage is positively associated with both outcomes. The negative popularity association appears only in the popularity >=65 sensitivity sample. This finding is sample-dependent. The specification measures 1 / weighted Burt constraint, uses the largest component, and controls for eigenvector centrality, track count and danceability. It does not directly test genre crossover or causal follower growth.

The R pipeline independently checks the HC1 covariance formula. The two models within each sample share the same complete-case artists. Input checksums and session information accompany the outputs. Alternative brokerage measures and dependence-aware uncertainty remain further work.

All files in this folder are local. They have not been added to GitHub.
